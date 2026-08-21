import Foundation
import Observation
import SwiftData

struct ConversationProcessingContext {
    var structuredContext: String
    var session: ConversationSession
    var dataSpace: DataSpace
    var gyms: [GymProfile]
    var equipment: [GymEquipment]
    var ai: AIService
    var modelContext: ModelContext
}

@MainActor
@Observable
final class ConversationProcessingService {
    static let maximumAnalysisImageCount = 12
    /// 配合 step 检查点分段续跑；到期前会落盘检查点。
    private static let executionLeaseDuration: TimeInterval = 45
    private let runnerOwner = UUID().uuidString.lowercased()

    private(set) var isProcessing = false
    private(set) var dataSpace: DataSpace?
    private(set) var sessionID: UUID?
    private(set) var liveAssistantText = ""
    private(set) var liveAgentActivity: String?
    private(set) var liveEventRevision = 0

    @ObservationIgnored
    private var processingTask: Task<Void, Never>?

    @ObservationIgnored
    private var retryTask: Task<Void, Never>?

    @ObservationIgnored
    private let backgroundLease: BackgroundExecutionLease

    @ObservationIgnored
    private var backgroundLeaseExpired = false

    init(
        backgroundLease: BackgroundExecutionLease? = nil
    ) {
        self.backgroundLease = backgroundLease ?? UIKitBackgroundExecutionLease()
    }

    @discardableResult
    func submit(
        text: String,
        attachments: [PendingAttachment],
        context: ConversationProcessingContext,
        includeLocation: Bool,
        locationService: LocationContextService,
        selectedShortcutID: String? = nil,
        forceLocal: Bool = false
    ) -> Bool {
        // ADR 0045：发送不再以 LLM 当前可用为前提，也不因为已有任务在途而拒绝。
        let useRemote = !forceLocal && RemoteAgentPreference.isEnabled()
        let selectedShortcut = selectedShortcutID.flatMap {
            AgentInputShortcutStore.shortcut(id: $0)
        }
        let persistedAttachments: [MediaAttachmentReference]
        do {
            persistedAttachments = try persistPendingAttachments(attachments)
        } catch {
            return false
        }

        let displayText = text.isEmpty
            ? mediaDisplaySummary(persistedAttachments)
            : text
        let submittedAt = Date.now
        let turnID = UUID()
        let businessDate = context.businessDate(for: text, turnSentAt: submittedAt)
        let contextEnvelope = AgentTurnContextBuilder.build(
            turnID: turnID,
            userText: text,
            hasCurrentMedia: !persistedAttachments.isEmpty,
            turnSentAt: submittedAt,
            businessSummary: context.structuredContext(for: businessDate),
            effectiveBusinessDate: businessDate,
            sessionID: context.session.id,
            in: context.modelContext
        )
        let userMessage = CoachMessage(
            date: submittedAt,
            sessionID: context.session.id,
            isFromCoach: false,
            text: text,
            mediaKind: persistedAttachments.first?.kind ?? .none,
            mediaPath: persistedAttachments.first?.path,
            mediaAttachments: persistedAttachments,
            turnID: turnID
        )
        let job = AgentJob(
            turnID: turnID,
            sessionID: context.session.id,
            userMessageID: userMessage.id,
            dataSpace: context.dataSpace,
            backend: useRemote ? .remote : .local,
            userText: text,
            mediaAttachments: persistedAttachments,
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: contextEnvelope.promptText(at: submittedAt),
                includeLocation: includeLocation,
                createdAt: submittedAt,
                envelope: contextEnvelope
            ),
            turnSentAt: submittedAt,
            effectiveBusinessDate: businessDate,
            businessTimeZone: context.session.businessTimeZone,
            // PRD 033：快捷按钮绑定的 Skill 在发送时冻结，之后改配置不影响在途 Turn。
            selectedSkillID: selectedShortcut?.skillID,
            selectedShortcutID: selectedShortcut?.id,
            createdAt: submittedAt
        )

        do {
            context.session.recordUserMessage(displayText, at: submittedAt)
            try AgentJobStore.enqueue(
                job,
                userMessage: userMessage,
                in: context.modelContext,
                at: submittedAt
            )
        } catch {
            context.modelContext.rollback()
            for persistedAttachment in persistedAttachments {
                _ = MediaStore.removeStoredFile(at: persistedAttachment.path)
            }
            return false
        }

        dispatch(
            job: job,
            userMessage: userMessage,
            context: context,
            locationService: locationService
        )
        return true
    }

    /// 落盘成功后决定这条 Job 是立即执行、排队等待，还是进入暂存。
    func dispatch(
        job: AgentJob,
        userMessage: CoachMessage,
        context: ConversationProcessingContext,
        locationService: LocationContextService?
    ) {
        let jobs = (
            try? context.modelContext.fetch(
                FetchDescriptor<AgentJob>(sortBy: [SortDescriptor(\.createdAt)])
            )
        ) ?? []
        if jobs.contains(where: {
            $0.dataSpace == context.dataSpace
                && $0.id != job.id
                && $0.createdAt <= job.createdAt
                && $0.state == .waitingForUser
        }) {
            try? AgentJobStore.stage(
                job,
                message: "前一条消息等待手动重试；本条已按发送顺序暂存。",
                retryDelay: nil,
                in: context.modelContext
            )
            return
        }
        if job.executionKind == .react,
           let reason = backendUnavailableReason(job.backend, ai: context.ai)
        {
            try? AgentJobStore.stage(
                job,
                message: reason,
                retryDelay: nil,
                in: context.modelContext
            )
            return
        }
        // 已有任务在途时保持 FIFO：当前任务结束后由 startNextPendingJob 领取。
        guard !isProcessing else { return }
        start(
            job: job,
            userMessage: userMessage,
            context: context,
            locationService: locationService
        )
    }

    private func isBackendAvailable(
        _ backend: AgentExecutionBackendKind,
        ai: AIService
    ) -> Bool {
        backendUnavailableReason(backend, ai: ai) == nil
    }

    func isExecutionAvailable(_ job: AgentJob, ai: AIService) -> Bool {
        job.executionKind == .deterministicWorkout
            || isBackendAvailable(job.backend, ai: ai)
    }

    private func backendUnavailableReason(
        _ backend: AgentExecutionBackendKind,
        ai: AIService
    ) -> String? {
        switch backend {
        case .remote:
            guard RemoteAgentPreference.baseURL() == nil else { return nil }
            return "后台持续处理还没有可用的服务地址，消息已暂存。"
        case .local:
            guard ai.hasRequiredAPIKey else {
                return "还没有可用的 LLM 配置，消息已暂存。"
            }
            let provider = ai.provider(for: .standard)
            let model = ai.model(for: provider, tier: .standard)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = ai.baseURL(for: provider, tier: .standard)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard model.isEmpty || baseURL.isEmpty else { return nil }
            return "标准模型还缺少模型 ID 或服务地址，消息已暂存。"
        }
    }

    private func beginProcessing(
        dataSpace: DataSpace,
        sessionID: UUID
    ) -> Bool {
        guard !isProcessing else { return false }
        isProcessing = true
        self.dataSpace = dataSpace
        self.sessionID = sessionID
        liveAssistantText = ""
        liveAgentActivity = "正在启动 Agent…"
        return true
    }

    private func start(
        job: AgentJob,
        userMessage: CoachMessage,
        context: ConversationProcessingContext,
        locationService: LocationContextService?
    ) {
        guard beginProcessing(
            dataSpace: context.dataSpace,
            sessionID: context.session.id
        ) else {
            return
        }
        // ADR 0083：崩溃时进程没有机会写任何东西，所以在开始执行前先把上下文存好。
        AppRunSentinel.shared.recordActivity(
            sessionID: context.session.id,
            turnID: job.turnID,
            activity: "agent-turn backend=\(job.backend.rawValue)"
        )
        do {
            try AgentJobStore.claim(
                job,
                owner: runnerOwner,
                leaseDuration: Self.executionLeaseDuration,
                in: context.modelContext
            )
        } catch {
            finishProcessing()
            return
        }
        if job.backend == .remote {
            startRemoteProcessing(
                job: job,
                userMessage: userMessage,
                context: context,
                locationService: locationService
            )
            return
        }
        backgroundLeaseExpired = false
        backgroundLease.begin { [weak self] in
            guard let self else { return }
            backgroundLeaseExpired = true
            if job.state == .running {
                try? job.transition(to: .waitingForForeground)
                job.leaseOwner = nil
                job.leaseExpiresAt = nil
                _ = try? AgentJobStore.append(
                    kind: .waitingForForeground,
                    payload: .init(message: "后台执行时间已结束，等待前台恢复。"),
                    to: job,
                    in: context.modelContext
                )
                try? context.modelContext.save()
            }
            processingTask?.cancel()
        }

        processingTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = job.contextSnapshot
            if snapshot?.includeLocation == true,
               userMessage.location == nil,
               let locationService
            {
                liveAgentActivity = "正在获取本次位置…"
                userMessage.location = await locationService.requestSnapshot()
                try? context.modelContext.save()
            }
            if job.executionKind == .deterministicWorkout {
                await runDeterministicWorkoutAttempt(
                    job: job,
                    userMessage: userMessage,
                    context: context
                )
                finishProcessing()
                if let locationService {
                    startNextPendingJob(
                        dataSpace: context.dataSpace,
                        ai: context.ai,
                        modelContext: context.modelContext,
                        locationService: locationService
                    )
                }
                return
            }
            let mediaStartedAt = Date.now
            var media = await prepareStoredMedia(
                job.mediaAttachments,
                frameLimit: Self.maximumAnalysisImageCount,
                directVideoCapability: directVideoCapability(
                    for: userMessage,
                    attachments: job.mediaAttachments,
                    context: context
                )
            )
            media.preparationMilliseconds = Int(
                (Date.now.timeIntervalSince(mediaStartedAt) * 1000).rounded()
            )
            guard job.state == .running, !backgroundLeaseExpired else {
                finishProcessing()
                return
            }
            await runAttempt(
                job: job,
                userMessage: userMessage,
                media: media,
                context: context,
                locationService: locationService
            )
            finishProcessing()
            if let locationService {
                startNextPendingJob(
                    dataSpace: context.dataSpace,
                    ai: context.ai,
                    modelContext: context.modelContext,
                    locationService: locationService
                )
            }
        }
    }

    private func startRemoteProcessing(
        job: AgentJob,
        userMessage: CoachMessage,
        context: ConversationProcessingContext,
        locationService: LocationContextService?
    ) {
        processingTask = Task { [weak self] in
            guard let self else { return }
            if job.contextSnapshot?.includeLocation == true,
               userMessage.location == nil,
               let locationService
            {
                liveAgentActivity = "正在获取本次位置…"
                userMessage.location = await locationService.requestSnapshot()
                try? context.modelContext.save()
            }
            await runRemoteAttempt(
                job: job,
                userMessage: userMessage,
                context: context
            )
            finishProcessing()
            if let locationService {
                startNextPendingJob(
                    dataSpace: context.dataSpace,
                    ai: context.ai,
                    modelContext: context.modelContext,
                    locationService: locationService
                )
            }
        }
    }

    private func runRemoteAttempt(
        job: AgentJob,
        userMessage: CoachMessage,
        context: ConversationProcessingContext
    ) async {
        guard let baseURL = RemoteAgentPreference.baseURL(),
              let turnID = userMessage.turnID,
              job.dataSpace == context.dataSpace,
              !job.state.isTerminal
        else {
            failRemoteJob(
                job,
                message: RemoteAgentError.endpointMissing.localizedDescription,
                context: context
            )
            return
        }

        let client = RemoteAgentClient(baseURL: baseURL)
        let responseMessage = remoteResponseMessage(
            for: job,
            turnID: turnID,
            sessionID: context.session.id,
            in: context.modelContext
        )
        let trace = remoteTrace(
            for: responseMessage,
            turnID: turnID,
            dataSpace: context.dataSpace,
            endpoint: baseURL,
            input: userMessage.text,
            in: context.modelContext
        )

        do {
            liveAgentActivity = job.remoteJobID == nil
                ? "正在投递后台任务…"
                : "正在同步后台进度…"
            if job.remoteJobID == nil {
                let submissionStartedAt = Date.now
                let prepared = try await prepareRemoteSubmission(
                    job: job,
                    userMessage: userMessage,
                    turnID: turnID,
                    context: context,
                    client: client
                )
                if let summary = prepared.compactionSummary {
                    projectRemoteSpan(
                        AgentTraceSpan(
                            kind: .output,
                            title: "已压缩更早对话",
                            status: .succeeded,
                            startedAt: submissionStartedAt,
                            endedAt: .now,
                            output: summary,
                            metadata: AgentTraceText.jsonObject([
                                "strategy": prepared.compactionStrategy?.rawValue
                                    ?? "unknown"
                            ])
                        ),
                        job: job,
                        responseMessage: responseMessage,
                        trace: trace,
                        context: context
                    )
                }
                let submitted = try await client.submit(job: AgentJobSubmission(
                    clientJobID: remoteClientJobID(for: job),
                    turnID: turnID,
                    sessionID: context.session.id,
                    modelInput: prepared.modelInput,
                    mediaMode: prepared.mediaMode,
                    liveActivityEnabled: UserDefaults.standard.bool(
                        forKey: AgentSystemPreference.liveActivitiesKey
                    ),
                    requestAttempt: job.remoteRequestAttempt
                ))
                guard !job.state.isTerminal else {
                    try? await client.cancel(remoteJobID: submitted.id)
                    return
                }
                job.remoteJobID = submitted.id
                job.remoteEventCursor = 0
                let submissionEndedAt = Date.now
                projectRemoteSpan(
                    AgentTraceSpan(
                        kind: .output,
                        title: "远程媒体上传与任务投递",
                        status: .succeeded,
                        startedAt: submissionStartedAt,
                        endedAt: submissionEndedAt,
                        metadata: AgentTraceText.jsonObject([
                            "attachment_count": job.mediaAttachments.count,
                            "history_exchange_count": prepared.historyExchangeCount,
                            "video_count": job.mediaAttachments.count {
                                $0.kind == .video
                            },
                            "media_mode": prepared.mediaMode.rawValue,
                            "request_attempt": job.remoteRequestAttempt,
                            "duration_ms": Int(
                                submissionEndedAt.timeIntervalSince(
                                    submissionStartedAt
                                ) * 1000
                            )
                        ])
                    ),
                    job: job,
                    responseMessage: responseMessage,
                    trace: trace,
                    context: context
                )
                try context.modelContext.save()
            }
            guard let remoteJobID = job.remoteJobID else {
                throw RemoteAgentError.invalidResponse
            }

            let catchUpPage = try await client.events(
                remoteJobID: remoteJobID,
                after: job.remoteEventCursor
            )
            try await applyRemoteEvents(
                catchUpPage.events,
                remoteJobID: remoteJobID,
                job: job,
                userMessage: userMessage,
                responseMessage: responseMessage,
                trace: trace,
                context: context,
                client: client
            )

            if !job.state.isTerminal, !catchUpPage.terminal {
                if job.state == .running {
                    try job.transition(to: .remoteRunning)
                }
                job.leaseOwner = nil
                job.leaseExpiresAt = nil
                job.nextRetryAt = nil
                responseMessage.agentStatus = .running
                try context.modelContext.save()

                for try await event in client.eventStream(
                    remoteJobID: remoteJobID,
                    after: job.remoteEventCursor
                ) {
                    try await applyRemoteEvents(
                        [event],
                        remoteJobID: remoteJobID,
                        job: job,
                        userMessage: userMessage,
                        responseMessage: responseMessage,
                        trace: trace,
                        context: context,
                        client: client
                    )
                    if job.state.isTerminal {
                        break
                    }
                }
            }

            let finalPage = try await client.events(
                remoteJobID: remoteJobID,
                after: job.remoteEventCursor
            )
            try await applyRemoteEvents(
                finalPage.events,
                remoteJobID: remoteJobID,
                job: job,
                userMessage: userMessage,
                responseMessage: responseMessage,
                trace: trace,
                context: context,
                client: client
            )
            if job.remoteEventCursor > 0 {
                let acknowledgedCursor = job.remoteEventCursor
                Task {
                    try? await client.acknowledge(
                        remoteJobID: remoteJobID,
                        through: acknowledgedCursor
                    )
                }
            }

            if job.state.isTerminal {
                job.nextRetryAt = nil
            } else if finalPage.terminal || catchUpPage.terminal {
                if job.state == .running || job.state == .remoteRunning {
                    try job.transition(
                        to: .failed,
                        error: "后台任务已结束，但没有返回可展示的结果。"
                    )
                }
                job.nextRetryAt = nil
            } else {
                throw URLError(.networkConnectionLost)
            }
            context.session.touch(at: .now)
            try context.modelContext.save()
        } catch let fallback as RemoteVideoKeyframeFallbackRequired {
            guard job.remoteRequestAttempt == 1,
                  !job.state.isTerminal
            else {
                failRemoteJob(
                    job,
                    message: "完整视频直传失败，且关键帧降级已用尽。",
                    context: context
                )
                return
            }
            if job.state == .remoteRunning {
                try? job.transition(to: .running)
            }
            job.remoteRequestAttempt = 2
            job.remoteJobID = nil
            job.remoteEventCursor = 0
            job.responseTextSnapshot = ""
            responseMessage.text = ""
            responseMessage.agentStatus = .running
            projectRemoteSpan(
                AgentTraceSpan(
                    kind: .output,
                    title: "完整视频降级为关键帧",
                    status: .succeeded,
                    startedAt: .now,
                    endedAt: .now,
                    metadata: AgentTraceText.jsonObject([
                        "fallback_reason": fallback.code,
                        "media_mode": "keyframes",
                        "request_attempt": 2
                    ])
                ),
                job: job,
                responseMessage: responseMessage,
                trace: trace,
                context: context
            )
            try? context.modelContext.save()
            await runRemoteAttempt(
                job: job,
                userMessage: userMessage,
                context: context
            )
            return
        } catch {
            let message = error.localizedDescription
            job.submissionAttemptCount += 1
            if isTransientNetworkError(error) {
                if job.state == .running {
                    try? job.transition(to: .waitingForNetwork, error: message)
                }
                job.leaseOwner = nil
                job.leaseExpiresAt = nil
                job.nextRetryAt = .now.addingTimeInterval(
                    min(pow(2, Double(job.submissionAttemptCount)), 60)
                )
                responseMessage.agentStatus = .running
                liveAgentActivity = "网络暂时不可用，后台任务仍会继续。"
                _ = try? AgentJobStore.append(
                    kind: .waitingForNetwork,
                    payload: .init(message: liveAgentActivity),
                    to: job,
                    in: context.modelContext
                )
                try? context.modelContext.save()
            } else {
                trace.apply(.failed(
                    message: message,
                    cancelled: false,
                    at: .now
                ))
                failRemoteJob(job, message: message, context: context)
                responseMessage.text = "这次后台任务没有处理成功：\(message)"
                responseMessage.agentStatus = .failed
                responseMessage.applyAgentEvent(.failed(
                    message: message,
                    cancelled: false,
                    at: .now
                ))
                try? context.modelContext.save()
            }
        }
    }

    func applyRemoteEvent(
        _ event: RemoteAgentEvent,
        remoteJobID: String,
        job: AgentJob,
        userMessage: CoachMessage,
        responseMessage: CoachMessage,
        trace: AgentTrace,
        context: ConversationProcessingContext,
        client: RemoteAgentClient
    ) async throws {
        if let request = RemoteDeviceToolRequest(event: event) {
            updateRemoteModelSpan(
                firstDeltaAt: nil,
                completedAt: event.createdAt,
                status: .succeeded,
                trace: trace,
                responseMessage: responseMessage
            )
            guard let name = AgentToolName(rawValue: request.name),
                  name.supportedSchemaVersions.contains(request.schemaVersion),
                  name.isMutation == request.mutation,
                  job.turnID == userMessage.turnID,
                  job.state == .running || job.state == .remoteRunning
            else {
                throw RemoteAgentError.toolRejected(
                    "后台请求的 Tool 与当前 Turn、空间或 Schema 不匹配。"
                )
            }
            let argumentData = try JSONEncoder().encode(request.arguments)
            try AgentToolSchemaValidator.validate(
                argumentData,
                for: name,
                schemaVersion: request.schemaVersion
            )
            let arguments = try JSONDecoder().decode(
                AgentToolArguments.self,
                from: argumentData
            )
            let call = AgentToolCall(name: name, arguments: arguments)
            try job.transition(to: .waitingForDevice)
            _ = try? AgentJobStore.append(
                kind: .waitingForDevice,
                payload: .init(message: "正在本机执行 \(name.displayTitle)。"),
                to: job,
                in: context.modelContext
            )
            let currentGymID = GymSelection.current(in: context.gyms)?.id
            let result = try await executeAgentTool(
                call,
                turnID: job.turnID,
                userMessage: userMessage,
                sourceDate: job.stableDefaultOccurredAt,
                mediaAttachments: job.mediaAttachments,
                preferredGymID: currentGymID,
                context: context
            )
            try await client.submitToolResult(
                remoteJobID: remoteJobID,
                toolCallID: request.toolCallID,
                result: result
            )
            try job.transition(to: .remoteRunning)
            projectRemoteSpan(
                AgentTraceSpan(
                    sequence: event.sequence,
                    step: event.sequence,
                    kind: name == .loadSkill ? .skill : .tool,
                    title: name.displayTitle,
                    status: result.ok ? .succeeded : .failed,
                    startedAt: event.createdAt,
                    endedAt: .now,
                    input: AgentTraceText.json(arguments),
                    output: AgentTraceText.json(result),
                    errorMessage: result.ok ? nil : result.observation
                ),
                job: job,
                responseMessage: responseMessage,
                trace: trace,
                context: context
            )
            return
        }

        if projectRemoteRuntimeTool(
            event,
            job: job,
            responseMessage: responseMessage,
            trace: trace,
            context: context
        ) {
            return
        }

        if event.kind == "text",
           event.phase == "updated",
           let delta = event.payload["delta"]?.stringValue
        {
            updateRemoteModelSpan(
                firstDeltaAt: event.createdAt,
                completedAt: nil,
                status: nil,
                trace: trace,
                responseMessage: responseMessage
            )
            let itemID = event.payload["itemID"]?.stringValue
                .flatMap(UUID.init(uuidString:))
                ?? UUID(uuidString: event.id)
                ?? UUID()
            let traceEvent = AgentTraceEvent.assistantTextDelta(
                itemID: itemID,
                delta: delta
            )
            trace.apply(traceEvent)
            job.responseTextSnapshot += delta
            responseMessage.text += delta
            responseMessage.agentStatus = .running
            responseMessage.applyAgentEvent(traceEvent)
            applyLiveAgentEvent(traceEvent)
            _ = try? AgentJobStore.append(
                kind: .assistantTextDelta,
                payload: .init(itemID: itemID, text: delta),
                to: job,
                in: context.modelContext,
                at: event.createdAt
            )
        } else if event.kind == "text", event.phase == "completed" {
            let itemID = event.payload["itemID"]?.stringValue
                .flatMap(UUID.init(uuidString:))
                ?? UUID(uuidString: event.id)
                ?? UUID()
            let traceEvent = AgentTraceEvent.assistantTextCompleted(
                itemID: itemID,
                at: event.createdAt
            )
            trace.apply(traceEvent)
            responseMessage.applyAgentEvent(traceEvent)
            applyLiveAgentEvent(traceEvent)
            _ = try? AgentJobStore.append(
                kind: .assistantTextCompleted,
                payload: .init(itemID: itemID),
                to: job,
                in: context.modelContext,
                at: event.createdAt
            )
        } else if event.kind == "model", event.phase == "started" {
            let exposedToolNames = event.payload["exposedToolNames"]?
                .stringArrayValue ?? []
            projectRemoteSpan(
                AgentTraceSpan(
                    sequence: event.sequence,
                    kind: .model,
                    title: "Soma 后台模型",
                    status: .running,
                    startedAt: event.createdAt,
                    endedAt: event.createdAt,
                    metadata: remoteModelSpanMetadata(event)
                ),
                job: job,
                responseMessage: responseMessage,
                trace: trace,
                context: context
            )
            AgentDiagnostics.modelRequest(
                step: event.sequence,
                provider: event.payload["provider"]?.stringValue ?? "managed",
                model: event.payload["model"]?.stringValue ?? "configured",
                tier: "后台持续处理",
                skillID: job.selectedSkillID,
                toolNames: exposedToolNames,
                messageCount: nil
            )
        } else if event.kind == "output",
                  event.phase == "completed",
                  let answer = event.payload["answer"]?.stringValue
        {
            updateRemoteModelSpan(
                firstDeltaAt: nil,
                completedAt: event.createdAt,
                status: .succeeded,
                trace: trace,
                responseMessage: responseMessage
            )
            let presentedAnswer = job.remoteRequestAttempt > 1
                ? "本次完整视频直传失败，已降级为关键帧分析。\n\n\(answer)"
                : answer
            job.responseTextSnapshot = presentedAnswer
            responseMessage.text = presentedAnswer
            responseMessage.agentStatus = .succeeded
            trace.apply(.completed(answer: presentedAnswer, at: event.createdAt))
            if job.state == .running || job.state == .remoteRunning {
                try job.transition(to: .succeeded, at: event.createdAt)
            }
            _ = try? AgentJobStore.append(
                kind: .completed,
                payload: .init(text: presentedAnswer),
                to: job,
                in: context.modelContext,
                at: event.createdAt
            )
            responseMessage.applyAgentEvent(.completed(
                answer: presentedAnswer,
                at: event.createdAt
            ))
            applyLiveAgentEvent(.completed(
                answer: presentedAnswer,
                at: event.createdAt
            ))
        } else if event.phase == "cancelled" {
            updateRemoteModelSpan(
                firstDeltaAt: nil,
                completedAt: event.createdAt,
                status: .cancelled,
                trace: trace,
                responseMessage: responseMessage
            )
            let message = "后台任务已取消。"
            stopAutomaticRetry()
            trace.apply(.failed(
                message: message,
                cancelled: false,
                at: event.createdAt
            ))
            responseMessage.text = message
            responseMessage.agentStatus = .failed
            responseMessage.applyAgentEvent(.failed(
                message: message,
                cancelled: false,
                at: event.createdAt
            ))
            try? AgentJobStore.waitForUser(
                job,
                message: message,
                in: context.modelContext
            )
        } else if event.kind == "error" || event.phase == "failed" {
            updateRemoteModelSpan(
                firstDeltaAt: nil,
                completedAt: event.createdAt,
                status: .failed,
                trace: trace,
                responseMessage: responseMessage
            )
            let code = event.payload["code"]?.stringValue ?? "remote_failed"
            let mediaMode = event.payload["mediaMode"]?.stringValue
            let requestAttempt = event.payload["requestAttempt"]?.intValue
            if ["provider_timeout", "provider_unavailable"].contains(code),
               mediaMode == "direct_video",
               requestAttempt == 1,
               job.remoteRequestAttempt == 1,
               job.responseTextSnapshot.isEmpty,
               job.mediaAttachments.contains(where: { $0.kind == .video })
            {
                throw RemoteVideoKeyframeFallbackRequired(code: code)
            }
            let message = "后台任务未完成（\(code)）。"
            trace.apply(.failed(
                message: message,
                cancelled: false,
                at: event.createdAt
            ))
            failRemoteJob(job, message: message, context: context)
            responseMessage.text = message
            responseMessage.agentStatus = .failed
            responseMessage.applyAgentEvent(.failed(
                message: message,
                cancelled: false,
                at: event.createdAt
            ))
        }
    }
}

private extension ConversationProcessingService {
    private func runAttempt(
        job: AgentJob,
        userMessage: CoachMessage,
        media: PreparedConversationMedia,
        context: ConversationProcessingContext,
        locationService: LocationContextService?
    ) async {
        guard let turnID = userMessage.turnID else {
            try? job.transition(
                to: .failed,
                error: "用户消息缺少稳定 Turn ID。"
            )
            try? context.modelContext.save()
            return
        }
        let displayText = userMessage.text.isEmpty
            ? media.displaySummary
            : userMessage.text
        let resolution = GymLocationResolver.resolve(
            text: userMessage.text,
            snapshot: userMessage.location,
            gyms: context.gyms
        )
        userMessage.effectiveGymID = resolution.gymID
        let effectiveGym = resolution.gymID.flatMap { id in
            context.gyms.first { $0.id == id }
        }
        let prepared = await prepareHistory(
            excludingTurnID: turnID,
            currentFrameCount: media.frames.count,
            currentText: userMessage.text,
            hasCurrentMedia: !media.attachments.isEmpty,
            selectedHistoricalTurnIDs: job.contextSnapshot?.envelope?
                .selectedHistoricalTurnIDs,
            context: context
        )
        let projection = prepared.projection
        let history = prepared.history
        let historicalFrameCount = history.reduce(0) { $0 + $1.images.count }
        let compaction = await ConversationCompactionMiddleware.prepare(
            sessionID: job.sessionID,
            excludingTurnID: turnID,
            ai: context.ai,
            in: context.modelContext
        )
        let persistentContext = composePersistentContext(
            job: job,
            userMessage: userMessage,
            turnID: turnID,
            effectiveGym: effectiveGym,
            resolution: resolution,
            context: context
        )
        let weatherGuidance: String? = if let location = userMessage.location {
            await WeatherContextProvider.transientGuidance(
                for: location,
                text: userMessage.text
            )
        } else {
            nil
        }
        let compactionContext = compaction.summary.map { "更早对话的可审查滚动摘要：\n\($0)" }
        let agentContext = [persistentContext, compactionContext, weatherGuidance]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        var performedRecordType: ConversationIntent?
        var activeTrace: AgentTrace?
        // 同一 Job 无论失败发生在第几个 step，都复用原回复气泡。
        let resumable = job.responseMessageID != nil
        let (responseMessage, attemptNumber) = bindResponseMessage(
            job: job,
            turnID: turnID,
            resumable: resumable,
            context: context
        )
        try? context.modelContext.save()

        do {
            let route = context.ai.route(
                text: userMessage.text,
                hasMedia: !media.attachments.isEmpty,
                hasVideo: media.hasVideo
            )
            let directVideos = ModelCapability.supportsDirectVideo(
                provider: route.provider,
                model: route.model
            ) ? media.videos : []
            if media.failedVideoCount > 0,
               directVideos.count != media.videoCount
            {
                throw ConversationMediaPreparationError.videoFramesUnavailable
            }
            let provider = route.provider
            let trace = AgentTrace(
                provider: provider.displayName,
                model: route.model,
                endpoint: provider.endpoint(
                    baseURL: route.baseURL,
                    path: "chat/completions"
                )?.absoluteString ?? route.baseURL,
                dataSpaceRaw: context.dataSpace.rawValue,
                userInput: displayText,
                contextSnapshot: """
                \(persistentContext)
                Session 上下文投影：最近 \(history.count) 个来回；重新提供历史视觉帧 \(historicalFrameCount) 张。
                媒体模式：\(media.mode.rawValue)；视频字节 \(media.videos.reduce(0) { $0 + $1.data.count })；关键帧 \(media.mode == .keyframes ? media.frames.count : 0)。
                本地准备耗时 \(prepared.preparationMilliseconds) ms（含被明确引用的历史媒体准备）。
                """,
                mediaKind: media.primaryKind,
                imageCount: media.frames.count + historicalFrameCount,
                imageAttachmentCount: media.imageCount,
                videoAttachmentCount: media.videoCount,
                turnID: turnID,
                attemptNumber: attemptNumber
            )
            activeTrace = trace
            responseMessage.agentTraceID = trace.id
            context.modelContext.insert(trace)
            let traceNow = Date.now
            let mediaSpan = AgentTraceSpan(
                kind: .output,
                title: "媒体准备",
                status: .succeeded,
                startedAt: traceNow.addingTimeInterval(
                    -Double(media.preparationMilliseconds) / 1000
                ),
                endedAt: traceNow,
                metadata: AgentTraceText.jsonObject([
                    "media_mode": media.mode.rawValue,
                    "video_bytes": mediaAttachmentBytes(media.attachments),
                    "frame_count": media.mode == .keyframes ? media.frames.count : 0,
                    "duration_ms": media.preparationMilliseconds
                ])
            )
            let contextSpan = AgentTraceSpan(
                kind: .output,
                title: "上下文投影",
                status: .succeeded,
                startedAt: traceNow.addingTimeInterval(
                    -Double(prepared.preparationMilliseconds) / 1000
                ),
                endedAt: traceNow,
                metadata: AgentTraceText.jsonObject([
                    "history_exchange_count": history.count,
                    "historical_frame_count": historicalFrameCount,
                    "duration_ms": prepared.preparationMilliseconds
                ])
            )
            trace.apply(.span(mediaSpan))
            trace.apply(.span(contextSpan))
            responseMessage.applyAgentEvent(.span(mediaSpan))
            ConversationCompactionProjection.apply(
                compaction,
                at: traceNow,
                trace: trace,
                responseMessage: responseMessage
            )
            responseMessage.applyAgentEvent(.span(contextSpan))
            if media.hasVideo {
                let modeItemID = UUID()
                let notice = media.mode == .directVideo
                    ? "本次使用完整视频分析。\n\n"
                    : "本次使用关键帧分析；未覆盖的动作阶段不会据此推断。\n\n"
                PersistentAgentEventProjection.persistAndProject(
                    .assistantTextDelta(itemID: modeItemID, delta: notice),
                    job: job,
                    responseMessage: responseMessage,
                    trace: trace,
                    in: context.modelContext
                )
                PersistentAgentEventProjection.persistAndProject(
                    .assistantTextCompleted(itemID: modeItemID, at: traceNow),
                    job: job,
                    responseMessage: responseMessage,
                    trace: trace,
                    in: context.modelContext
                )
            }
            try? context.modelContext.save()

            let resumeCheckpoint = resumable ? job.loopCheckpoint : nil
            let firstStepDeadlineEnabled = !job.firstStepDeadlineConsumed
            job.firstStepDeadlineConsumed = true
            try? context.modelContext.save()
            let loopBudget = context.ai.streamDeadlinePolicy.loopTotal(
                hasImages: media.imageCount > 0,
                hasVideo: media.hasVideo
            )
            let elapsed = job.activeLoopDuration(at: .now)
            let remainingLoopBudget = max(0.01, loopBudget - elapsed)
            let outcome = try await AgentLoopDeadline.run(
                seconds: remainingLoopBudget
            ) {
                try await context.ai.runAgent(
                    text: userMessage.text,
                    images: media.frames,
                    videos: directVideos,
                    hasVideo: media.hasVideo,
                    imageAttachmentCount: media.imageCount,
                    videoAttachmentCount: media.videoCount,
                    history: history,
                    context: agentContext,
                    route: route,
                    selectedSkillID: job.selectedSkillID,
                    selectedShortcutID: job.selectedShortcutID,
                    checkpoint: resumeCheckpoint,
                    firstStepDeadlineEnabled: firstStepDeadlineEnabled,
                    onCheckpoint: { checkpoint in
                        job.loopCheckpoint = checkpoint
                        job.responseTextSnapshot = checkpoint.assistantPassages
                            .joined(separator: "\n\n")
                        try? context.modelContext.save()
                    },
                    videoFrameFallback: media.mode == .directVideo ? { [weak self] in
                        guard let self else { return [] }
                        let fallback = await prepareStoredMedia(
                            job.mediaAttachments,
                            frameLimit: Self.maximumAnalysisImageCount
                        )
                        return fallback.frames
                    } : nil,
                    trace: { [weak self] event in
                        self?.applyLiveAgentEvent(event)
                        if case .failed = event,
                           self?.backgroundLeaseExpired == true
                        {
                            trace.apply(event)
                        } else {
                            PersistentAgentEventProjection.persistAndProject(
                                event,
                                job: job,
                                responseMessage: responseMessage,
                                trace: trace,
                                in: context.modelContext
                            )
                        }
                    }
                ) { call in
                    let attributedMedia = AgentToolMediaAttribution.attachments(
                        for: call,
                        current: media.attachments,
                        history: projection
                    )
                    return try await self.executeAgentTool(
                        call,
                        turnID: turnID,
                        userMessage: userMessage,
                        sourceDate: job.stableDefaultOccurredAt,
                        mediaAttachments: attributedMedia,
                        preferredGymID: resolution.gymID,
                        context: context
                    )
                }
            }

            responseMessage.text = outcome.finalAnswer
            performedRecordType = outcome.primaryRecordType ?? performedRecordType
            responseMessage.recordType = performedRecordType
            responseMessage.agentStatus = .succeeded
            job.loopCheckpoint = nil
            job.lastCompletedStep = 0
            if job.state == .running {
                try job.transition(to: .succeeded)
            }
            try context.modelContext.save()
        } catch {
            performedRecordType = job.loopCheckpoint?.observations
                .compactMap(\.recordType)
                .last ?? performedRecordType
            handleAttemptFailure(
                error,
                job: job,
                responseMessage: responseMessage,
                activeTrace: activeTrace,
                performedRecordType: performedRecordType,
                media: media,
                context: context,
                locationService: locationService
            )
            return
        }

        context.session.touch(at: .now)
        try? context.modelContext.save()
    }

    private func executeAgentTool(
        _ call: AgentToolCall,
        turnID: UUID,
        userMessage: CoachMessage,
        sourceDate: Date,
        mediaAttachments: [MediaAttachmentReference],
        preferredGymID: UUID?,
        context: ConversationProcessingContext
    ) async throws -> AgentToolResult {
        if call.name == .submitFeedback {
            return try await AgentMutationStore.executeAsync(
                call,
                turnID: turnID,
                in: context.modelContext
            ) {
                try await AgentFeedbackTool.submit(
                    id: turnID,
                    sourceText: userMessage.text,
                    mediaAttachments: mediaAttachments
                )
            }
        }

        return AgentMutationStore.execute(
            call,
            turnID: turnID,
            in: context.modelContext
        ) {
            ConversationRecorder.executeAgentTool(
                call,
                sourceText: userMessage.text,
                sourceDate: sourceDate,
                sourceSessionID: context.session.id,
                sourceTurnID: turnID,
                mediaKind: mediaAttachments.first?.kind ?? .none,
                mediaPath: mediaAttachments.first?.path,
                mediaAttachments: mediaAttachments,
                preferredGymID: preferredGymID,
                in: context.modelContext
            )
        }
    }
}

extension ConversationProcessingService {
    private func handleAttemptFailure(
        _ error: Error,
        job: AgentJob,
        responseMessage: CoachMessage,
        activeTrace: AgentTrace?,
        performedRecordType: ConversationIntent?,
        media: PreparedConversationMedia,
        context: ConversationProcessingContext,
        locationService: LocationContextService?
    ) {
        let reason = error.localizedDescription
        if backgroundLeaseExpired {
            let pausedText = job.hasResumableCheckpoint
                ? "Soma 已保存进度，回到前台后会从中断处继续。"
                : "Soma 已保存本次任务，回到前台后会继续处理。"
            if !job.responseTextSnapshot.isEmpty {
                responseMessage.text = job.responseTextSnapshot
            } else if responseMessage.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                responseMessage.text = pausedText
            }
            responseMessage.agentStatus = .cancelled
            if job.state == .running {
                try? job.transition(to: .waitingForForeground)
            }
            job.leaseOwner = nil
            job.leaseExpiresAt = nil
            _ = try? AgentJobStore.append(
                kind: .waitingForForeground,
                payload: .init(message: pausedText),
                to: job,
                in: context.modelContext
            )
            try? context.modelContext.save()
            context.session.touch(at: .now)
            return
        }
        switch LLMOutageClassifier.disposition(for: error) {
        case .retryNetwork:
            let retryDelay = min(
                pow(2, Double(job.submissionAttemptCount)) * 2,
                60
            )
            job.submissionAttemptCount += 1
            job.nextRetryAt = Date.now.addingTimeInterval(retryDelay)
            if job.state == .running {
                try? job.transition(
                    to: .waitingForNetwork,
                    error: reason
                )
            }
            let waitingText = "网络暂时不可用，任务已保留，将在网络恢复后继续。"
            responseMessage.presentAutomaticRecovery(waitingText: waitingText)
            _ = try? AgentJobStore.append(
                kind: .waitingForNetwork,
                payload: .init(message: waitingText),
                to: job,
                in: context.modelContext
            )
            try? context.modelContext.save()
            scheduleRetry(
                at: job.nextRetryAt,
                dataSpace: context.dataSpace,
                ai: context.ai,
                modelContext: context.modelContext,
                locationService: locationService
            )
            context.session.touch(at: .now)
            return
        case let .stage(message):
            // ADR 0045：缺配置只等配置变更信号，供应商侧故障才按退避重试。
            let waitsForConfiguration = LLMOutageClassifier
                .signal(for: error)
                .isMissingConfiguration
            job.submissionAttemptCount += 1
            let waitingText = message + "LLM 恢复后会自动继续。"
            responseMessage.presentAutomaticRecovery(waitingText: waitingText)
            if let activeTrace, activeTrace.status == .running {
                activeTrace.apply(.failed(
                    message: reason,
                    cancelled: true,
                    at: .now
                ))
            }
            try? AgentJobStore.stage(
                job,
                message: message,
                retryDelay: waitsForConfiguration
                    ? nil
                    : LLMOutageClassifier.stagingRetryDelay(
                        attemptCount: job.submissionAttemptCount
                    ),
                in: context.modelContext
            )
            scheduleRetry(
                at: job.nextRetryAt,
                dataSpace: context.dataSpace,
                ai: context.ai,
                modelContext: context.modelContext,
                locationService: locationService
            )
            context.session.touch(at: .now)
            return
        case let .waitForUser(message):
            stopAutomaticRetry()
            job.submissionAttemptCount += 1
            responseMessage.text = message
            responseMessage.agentStatus = .failed
            if let activeTrace, activeTrace.status == .running {
                activeTrace.apply(.failed(
                    message: reason,
                    cancelled: false,
                    at: .now
                ))
            }
            try? AgentJobStore.waitForUser(
                job,
                message: message,
                in: context.modelContext
            )
            try? AgentJobStore.stageFollowingJobs(
                after: job,
                message: "前一条消息等待手动重试；本条已按发送顺序暂存。",
                in: context.modelContext
            )
            context.session.touch(at: .now)
            return
        case .fail:
            break
        }
        stopAutomaticRetry()
        let recovery = if performedRecordType != nil {
            "\n\nAgent 已完成的本地记录仍然保留，但生成最终回复时中断。"
        } else if !media.attachments.isEmpty {
            "\n\n附件已保存在本机对话中，但这次没有自动生成统计记录。请检查模型的多模态能力后重试。"
        } else {
            ""
        }
        let failureText = "这次没有处理成功：\(reason)。\(recovery)"
        responseMessage.text = failureText
        responseMessage.agentStatus = .failed
        if let activeTrace, activeTrace.status == .cancelled {
            PersistentAgentEventProjection.persistAndProject(
                .failed(
                    message: reason,
                    cancelled: false,
                    at: .now
                ),
                job: job,
                responseMessage: responseMessage,
                trace: activeTrace,
                in: context.modelContext
            )
        } else if !responseMessage.agentTurnItems.contains(where: { $0.kind == .error }) {
            responseMessage.applyAgentEvent(.failed(
                message: reason,
                cancelled: false,
                at: .now
            ))
        }
        try? AgentJobStore.waitForUser(
            job,
            message: "这一步需要你手动重试。",
            in: context.modelContext
        )
        try? AgentJobStore.stageFollowingJobs(
            after: job,
            message: "前一条消息等待手动重试；本条已按发送顺序暂存。",
            in: context.modelContext
        )
        context.session.touch(at: .now)
        try? context.modelContext.save()
    }

    func composePersistentContext(
        job: AgentJob,
        userMessage: CoachMessage,
        turnID: UUID,
        effectiveGym: GymProfile?,
        resolution: GymContextResolution,
        context: ConversationProcessingContext
    ) -> String {
        let snapshotContext = job.contextSnapshot?.envelope?
            .promptText(at: .now) ?? context.structuredContext
        return [
            snapshotContext,
            turnContext(
                location: userMessage.location,
                gym: effectiveGym,
                source: resolution.source
            )
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    func bindResponseMessage(
        job: AgentJob,
        turnID: UUID,
        resumable: Bool,
        context: ConversationProcessingContext
    ) -> (CoachMessage, Int) {
        if resumable,
           let existingID = job.responseMessageID,
           let existing = allMessages(in: context.modelContext)
           .first(where: { $0.id == existingID })
        {
            let attemptNumber = max(existing.attemptNumber, 1)
            job.activeAttemptNumber = attemptNumber
            prepareResponseMessageForResume(existing, job: job)
            _ = try? AgentJobStore.append(
                kind: .attemptStarted,
                payload: .init(message: "继续处理首个未完成 step。"),
                to: job,
                in: context.modelContext
            )
            return (existing, attemptNumber)
        }
        let attemptNumber = nextAttemptNumber(
            for: turnID,
            in: context.modelContext
        )
        job.activeAttemptNumber = attemptNumber
        let created = CoachMessage(
            sessionID: context.session.id,
            isFromCoach: true,
            text: "",
            agentStatus: .running,
            turnID: turnID,
            attemptNumber: attemptNumber
        )
        context.modelContext.insert(created)
        job.responseMessageID = created.id
        try? context.modelContext.save()
        _ = try? AgentJobStore.append(
            kind: .attemptStarted,
            payload: .init(message: "开始第 \(attemptNumber) 次处理。"),
            to: job,
            in: context.modelContext
        )
        return (created, attemptNumber)
    }

    /// ADR 0048：同气泡续跑时复用 CoachMessage，丢掉未完成 step 的 running 卡片。
    private func prepareResponseMessageForResume(
        _ message: CoachMessage,
        job: AgentJob
    ) {
        let completedItems = ConversationResumeProjection.completedItems(
            from: message.agentTurnItems
        )
        message.replaceAgentTurnItems(completedItems)
        let checkpointText = job.loopCheckpoint?.assistantPassages
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let checkpointText, !checkpointText.isEmpty {
            job.responseTextSnapshot = checkpointText
            message.text = checkpointText
        } else if !job.responseTextSnapshot.isEmpty, job.hasResumableCheckpoint {
            message.text = job.responseTextSnapshot
        } else {
            job.responseTextSnapshot = ""
            message.text = ""
        }
        message.agentStatus = .running
    }

    func nextAttemptNumber(
        for turnID: UUID,
        in context: ModelContext
    ) -> Int {
        let messages = (
            try? context.fetch(FetchDescriptor<CoachMessage>())
        ) ?? []
        return messages
            .filter { $0.isFromCoach && $0.turnID == turnID }
            .map(\.attemptNumber)
            .max()
            .map { $0 + 1 }
            ?? 1
    }

    private func allMessages(in context: ModelContext) -> [CoachMessage] {
        (
            try? context.fetch(
                FetchDescriptor<CoachMessage>(
                    sortBy: [SortDescriptor(\.date)]
                )
            )
        ) ?? []
    }

    private func turnContext(
        location: LocationSnapshot?,
        gym: GymProfile?,
        source: GymContextSource
    ) -> String {
        var parts: [String] = []
        if let location {
            parts.append("本次语义位置：\(location.displayName)。不要向用户或远程服务输出原始坐标。")
        }
        if let gym {
            let note = source == .nearby
                ? "由本地位置唯一匹配，本次使用但不改变全局当前健身房"
                : "本次有效场馆"
            parts.append("\(note)：\(gym.name)。")
        }
        return parts.isEmpty ? "" : "\n本次上下文：\n" + parts.joined(separator: "\n")
    }

    private func finishProcessing() {
        backgroundLease.end()
        backgroundLeaseExpired = false
        liveAssistantText = ""
        liveAgentActivity = nil
        isProcessing = false
        AppRunSentinel.shared.recordActivity(
            sessionID: sessionID,
            turnID: nil,
            activity: "idle"
        )
        dataSpace = nil
        sessionID = nil
        processingTask = nil
    }

    func startNextPendingJob(
        dataSpace: DataSpace,
        ai: AIService,
        modelContext: ModelContext,
        locationService: LocationContextService
    ) {
        guard !isProcessing else { return }
        let now = Date.now
        _ = try? AgentJobStore.promoteFailedResponsesToManualRetry(
            dataSpace: dataSpace,
            in: modelContext
        )
        let jobs = (
            try? modelContext.fetch(
                FetchDescriptor<AgentJob>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        guard let job = jobs.first(where: {
            $0.dataSpace == dataSpace && !$0.state.isTerminal
        }) else {
            return
        }
        // FIFO 只看队头。等待用户、配置或退避时，任何后续消息都不能越过。
        if job.state == .waitingForUser || job.state == .staged {
            return
        }
        if job.executionKind == .react,
           let reason = backendUnavailableReason(job.backend, ai: ai)
        {
            try? AgentJobStore.stage(
                job,
                message: reason,
                retryDelay: nil,
                in: modelContext
            )
            return
        }
        guard job.state.isRunnable else { return }
        guard job.nextRetryAt == nil || job.nextRetryAt! <= now else {
            scheduleRetry(
                at: job.nextRetryAt,
                dataSpace: dataSpace,
                ai: ai,
                modelContext: modelContext,
                locationService: locationService
            )
            return
        }
        let messages = (try? modelContext.fetch(FetchDescriptor<CoachMessage>())) ?? []
        guard let userMessage = messages.first(where: { $0.id == job.userMessageID }),
              var context = ConversationProcessingContextFactory.make(
                  sessionID: job.sessionID,
                  dataSpace: dataSpace,
                  ai: ai,
                  in: modelContext
              )
        else {
            if job.state.canTransition(to: .failed) {
                try? job.transition(
                    to: .failed,
                    error: "无法恢复任务所需的本地 Session 或用户消息。"
                )
                _ = try? AgentJobStore.append(
                    kind: .failed,
                    payload: .init(message: job.lastError),
                    to: job,
                    in: modelContext
                )
            }
            try? modelContext.save()
            startNextPendingJob(
                dataSpace: dataSpace,
                ai: ai,
                modelContext: modelContext,
                locationService: locationService
            )
            return
        }
        if let snapshot = job.contextSnapshot {
            context.structuredContext = snapshot.structuredContext
        }
        start(
            job: job,
            userMessage: userMessage,
            context: context,
            locationService: locationService
        )
    }

    func stopAutomaticRetry() {
        retryTask?.cancel()
        retryTask = nil
    }

    private func scheduleRetry(
        at date: Date?,
        dataSpace: DataSpace,
        ai: AIService,
        modelContext: ModelContext,
        locationService: LocationContextService?
    ) {
        guard let date, let locationService else { return }
        stopAutomaticRetry()
        retryTask = Task { [weak self] in
            let delay = max(0, date.timeIntervalSinceNow)
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            self?.resumePendingJobs(
                dataSpace: dataSpace,
                ai: ai,
                modelContext: modelContext,
                locationService: locationService,
                releaseStaged: true
            )
        }
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        if error is URLError {
            return true
        }
        let value = error as NSError
        return value.domain == NSURLErrorDomain
    }

    private func persistPendingAttachments(
        _ attachments: [PendingAttachment]
    ) throws -> [MediaAttachmentReference] {
        var references: [MediaAttachmentReference] = []
        do {
            for attachment in attachments {
                switch attachment.kind {
                case .none:
                    continue
                case .image:
                    guard let data = attachment.imageData else {
                        throw ConversationMediaPreparationError.attachmentPersistenceFailed
                    }
                    try references.append(MediaAttachmentReference(
                        kind: .image,
                        path: MediaStore.saveImage(data)
                    ))
                case .video:
                    guard let url = attachment.videoURL else {
                        throw ConversationMediaPreparationError.attachmentPersistenceFailed
                    }
                    try references.append(MediaAttachmentReference(
                        kind: .video,
                        path: MediaStore.saveVideo(from: url)
                    ))
                }
            }
            guard references.count == attachments.count(where: { $0.kind != .none }) else {
                throw ConversationMediaPreparationError.attachmentPersistenceFailed
            }
            return references
        } catch {
            for reference in references {
                _ = MediaStore.removeStoredFile(at: reference.path)
            }
            throw error
        }
    }

    private func mediaAttachmentBytes(
        _ attachments: [MediaAttachmentReference]
    ) -> Int {
        attachments.reduce(0) { total, attachment in
            guard attachment.kind == .video,
                  let url = MediaStore.url(at: attachment.path),
                  let attributes = try? FileManager.default.attributesOfItem(
                      atPath: url.path
                  ),
                  let bytes = (attributes[.size] as? NSNumber)?.intValue
            else {
                return total
            }
            return total + bytes
        }
    }

    /// 首个请求发出前的本地准备（上下文投影 + 历史媒体重新抽帧）需要单独计时，
    /// 否则一次「慢」无法区分是供应商排队还是我们自己的准备开销。
    func prepareHistory(
        excludingTurnID turnID: UUID,
        currentFrameCount: Int,
        currentText: String,
        hasCurrentMedia: Bool,
        selectedHistoricalTurnIDs: [UUID]?,
        context: ConversationProcessingContext
    ) async -> PreparedAgentHistory {
        let startedAt = Date.now
        let projection = ConversationContextProjection.make(
            messages: allMessages(in: context.modelContext),
            sessionID: context.session.id,
            excludingTurnID: turnID
        )
        let selectedTurnIDs = Set(
            selectedHistoricalTurnIDs
                ?? HistoricalMediaSelectionPolicy.selectedTurnIDs(
                    currentText: currentText,
                    hasCurrentMedia: hasCurrentMedia,
                    exchanges: projection.exchanges
                )
        )
        let history = await prepareAgentHistory(
            projection.exchanges,
            selectedTurnIDs: selectedTurnIDs,
            frameLimit: max(0, Self.maximumAnalysisImageCount - currentFrameCount)
        )
        return PreparedAgentHistory(
            projection: projection,
            history: history,
            preparationMilliseconds: Int(
                (Date.now.timeIntervalSince(startedAt) * 1000).rounded()
            )
        )
    }

    private func prepareAgentHistory(
        _ exchanges: [ConversationContextProjection.Exchange],
        selectedTurnIDs: Set<UUID>,
        frameLimit: Int
    ) async -> [AgentConversationExchange] {
        var remainingFrameCount = max(0, frameLimit)
        var framesByTurnID: [UUID: [Data]] = [:]

        for exchange in exchanges.reversed()
            where remainingFrameCount > 0 && selectedTurnIDs.contains(exchange.turnID)
        {
            let media = await prepareStoredMedia(
                exchange.mediaAttachments,
                frameLimit: remainingFrameCount
            )
            framesByTurnID[exchange.turnID] = media.frames
            remainingFrameCount -= media.frames.count
        }

        return exchanges.map { exchange in
            AgentConversationExchange(
                userText: exchange.userText,
                assistantText: exchange.assistantText,
                images: framesByTurnID[exchange.turnID] ?? [],
                imageAttachmentCount: exchange.imageAttachmentCount,
                videoAttachmentCount: exchange.videoAttachmentCount
            )
        }
    }

    private func applyLiveAgentEvent(_ event: AgentTraceEvent) {
        #if DEBUG
            // BUG 0024：这里改的是驱动聊天界面的 `@Observable` 状态。
            MainActor.assertIsolated("Agent 实时状态必须在主 actor 更新")
        #endif
        liveEventRevision += 1
        switch event {
        case let .assistantTextDelta(_, delta):
            liveAssistantText += delta
            liveAgentActivity = "正在生成回复…"
        case .assistantTextCompleted:
            liveAgentActivity = nil
        case let .span(span):
            guard span.status == .running else { return }
            switch span.kind {
            case .model:
                liveAgentActivity = span.title == "LLM 推理"
                    ? "模型正在响应…"
                    : span.title
            case .skill:
                liveAgentActivity = "正在加载 Skill：\(span.title)"
            case .tool:
                liveAgentActivity = "正在执行：\(span.title)"
            case .output:
                liveAgentActivity = "正在整理结果…"
            }
        case .completed, .failed:
            liveAgentActivity = nil
        }
    }
}
