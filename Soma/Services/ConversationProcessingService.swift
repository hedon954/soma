import Foundation
import Observation
import SwiftData

private struct PreparedConversationMedia {
    var attachments: [MediaAttachmentReference]
    var frames: [Data]
    var videos: [AgentVideoInput] = []
    var imageCount: Int
    var videoCount: Int
    var failedVideoCount: Int = 0

    var hasVideo: Bool {
        videoCount > 0
    }

    var primaryKind: MediaKind {
        attachments.first?.kind ?? .none
    }

    var primaryPath: String? {
        attachments.first?.path
    }

    var displaySummary: String {
        let parts = [
            imageCount > 0 ? "\(imageCount) 张图片" : nil,
            videoCount > 0 ? "\(videoCount) 个视频" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "发送了媒体" : "发送了" + parts.joined(separator: "和")
    }
}

private struct PreparedAgentHistory {
    var projection: ConversationContextProjection
    var history: [AgentConversationExchange]
    var preparationMilliseconds: Int
}

private enum ConversationMediaPreparationError: LocalizedError {
    case attachmentPersistenceFailed
    case videoFramesUnavailable

    var errorDescription: String? {
        switch self {
        case .attachmentPersistenceFailed:
            "附件未能完整保存到本机，请检查存储空间后重试"
        case .videoFramesUnavailable:
            "视频已保存在本机，但未能提取任何可供模型分析的画面，请换一个可播放的视频后重试"
        }
    }
}

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
    private static let maximumAnalysisImageCount = 12
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
        forceLocal: Bool = false
    ) -> Bool {
        // ADR 0045：发送不再以 LLM 当前可用为前提，也不因为已有任务在途而拒绝。
        let useRemote = !forceLocal && RemoteAgentPreference.isEnabled()
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
                structuredContext: context.structuredContext,
                includeLocation: includeLocation,
                createdAt: submittedAt
            ),
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

    @discardableResult
    func retry(
        userMessage: CoachMessage,
        context: ConversationProcessingContext,
        locationService: LocationContextService? = nil,
        forceLocal: Bool = false
    ) -> Bool {
        let useRemote = !forceLocal && RemoteAgentPreference.isEnabled()
        guard !userMessage.isFromCoach,
              userMessage.turnID != nil
        else {
            return false
        }

        let submittedAt = Date.now
        let job = AgentJob(
            turnID: userMessage.turnID ?? UUID(),
            sessionID: context.session.id,
            userMessageID: userMessage.id,
            dataSpace: context.dataSpace,
            backend: useRemote ? .remote : .local,
            userText: userMessage.text,
            mediaAttachments: userMessage.mediaAttachments,
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: context.structuredContext,
                includeLocation: userMessage.location != nil,
                createdAt: submittedAt
            ),
            createdAt: submittedAt
        )
        do {
            job.lastEventSequence = 1
            context.modelContext.insert(job)
            context.modelContext.insert(PersistentAgentEvent(
                jobID: job.id,
                turnID: job.turnID,
                sequence: 1,
                attemptNumber: 0,
                kind: .jobQueued,
                createdAt: submittedAt
            ))
            try context.modelContext.save()
        } catch {
            context.modelContext.rollback()
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

    func resumePendingJobs(
        dataSpace: DataSpace,
        ai: AIService,
        modelContext: ModelContext,
        locationService: LocationContextService
    ) {
        guard !isProcessing else { return }
        do {
            _ = try AgentJobStore.recoverExpiredLeases(
                dataSpace: dataSpace,
                in: modelContext
            )
            _ = try AgentJobStore.resumeForegroundJobs(
                dataSpace: dataSpace,
                in: modelContext
            )
            // ADR 0045：LLM 恢复后解除暂存并清掉退避，让补偿消费立即开始。
            _ = try AgentJobStore.releaseStagedJobs(
                dataSpace: dataSpace,
                in: modelContext
            ) { job in
                isBackendAvailable(job.backend, ai: ai)
            }
        } catch {
            return
        }
        startNextPendingJob(
            dataSpace: dataSpace,
            ai: ai,
            modelContext: modelContext,
            locationService: locationService
        )
    }

    /// 落盘成功后决定这条 Job 是立即执行、排队等待，还是进入暂存。
    private func dispatch(
        job: AgentJob,
        userMessage: CoachMessage,
        context: ConversationProcessingContext,
        locationService: LocationContextService?
    ) {
        if let reason = backendUnavailableReason(job.backend, ai: context.ai) {
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
            let media = await prepareStoredMedia(
                job.mediaAttachments,
                frameLimit: Self.maximumAnalysisImageCount
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
                let snapshot = job.contextSnapshot?.structuredContext
                    ?? context.structuredContext
                let submitted = try await client.submit(job: AgentJobSubmission(
                    clientJobID: job.id,
                    turnID: turnID,
                    sessionID: context.session.id,
                    text: userMessage.text,
                    contextSnapshot: snapshot,
                    attachments: job.mediaAttachments,
                    liveActivityEnabled: UserDefaults.standard.bool(
                        forKey: AgentSystemPreference.liveActivitiesKey
                    )
                ))
                guard !job.state.isTerminal else {
                    try? await client.cancel(remoteJobID: submitted.id)
                    return
                }
                job.remoteJobID = submitted.id
                job.remoteEventCursor = 0
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

    private func applyRemoteEvents(
        _ events: [RemoteAgentEvent],
        remoteJobID: String,
        job: AgentJob,
        userMessage: CoachMessage,
        responseMessage: CoachMessage,
        trace: AgentTrace,
        context: ConversationProcessingContext,
        client: RemoteAgentClient
    ) async throws {
        for event in events where event.sequence > job.remoteEventCursor {
            guard !job.state.isTerminal,
                  job.dataSpace == context.dataSpace
            else {
                try? await client.cancel(remoteJobID: remoteJobID)
                return
            }
            try await applyRemoteEvent(
                event,
                remoteJobID: remoteJobID,
                job: job,
                userMessage: userMessage,
                responseMessage: responseMessage,
                trace: trace,
                context: context,
                client: client
            )
            job.remoteEventCursor = event.sequence
            try context.modelContext.save()
        }
    }

    private func applyRemoteEvent(
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
            guard request.schemaVersion == 1,
                  let name = AgentToolName(rawValue: request.name),
                  name.isMutation == request.mutation,
                  job.turnID == userMessage.turnID,
                  job.state == .running || job.state == .remoteRunning
            else {
                throw RemoteAgentError.toolRejected(
                    "后台请求的 Tool 与当前 Turn、空间或 Schema 不匹配。"
                )
            }
            let argumentData = try JSONEncoder().encode(request.arguments)
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
            let result = AgentMutationStore.execute(
                call,
                turnID: job.turnID,
                in: context.modelContext
            ) {
                ConversationRecorder.executeAgentTool(
                    call,
                    sourceText: userMessage.text,
                    sourceDate: userMessage.date,
                    sourceSessionID: context.session.id,
                    sourceTurnID: job.turnID,
                    mediaKind: job.mediaAttachments.first?.kind ?? .none,
                    mediaPath: job.mediaAttachments.first?.path,
                    mediaAttachments: job.mediaAttachments,
                    preferredGymID: currentGymID,
                    in: context.modelContext
                )
            }
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

        if event.kind == "text",
           event.phase == "updated",
           let delta = event.payload["delta"]?.stringValue
        {
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
            projectRemoteSpan(
                AgentTraceSpan(
                    sequence: event.sequence,
                    kind: .model,
                    title: "Soma 后台模型",
                    status: .succeeded,
                    startedAt: event.createdAt,
                    endedAt: event.createdAt,
                    metadata: "后台持续处理"
                ),
                job: job,
                responseMessage: responseMessage,
                trace: trace,
                context: context
            )
        } else if event.kind == "output",
                  event.phase == "completed",
                  let answer = event.payload["answer"]?.stringValue
        {
            job.responseTextSnapshot = answer
            responseMessage.text = answer
            responseMessage.agentStatus = .succeeded
            trace.apply(.completed(answer: answer, at: event.createdAt))
            if job.state == .running || job.state == .remoteRunning {
                try job.transition(to: .succeeded, at: event.createdAt)
            }
            _ = try? AgentJobStore.append(
                kind: .completed,
                payload: .init(text: answer),
                to: job,
                in: context.modelContext,
                at: event.createdAt
            )
            responseMessage.applyAgentEvent(.completed(
                answer: answer,
                at: event.createdAt
            ))
            applyLiveAgentEvent(.completed(
                answer: answer,
                at: event.createdAt
            ))
        } else if event.phase == "cancelled" {
            let message = "后台任务已取消。"
            trace.apply(.failed(
                message: message,
                cancelled: true,
                at: event.createdAt
            ))
            if job.state.canTransition(to: .cancelled) {
                try job.transition(to: .cancelled, at: event.createdAt)
            }
            responseMessage.text = message
            responseMessage.agentStatus = .cancelled
            responseMessage.applyAgentEvent(.failed(
                message: message,
                cancelled: true,
                at: event.createdAt
            ))
            _ = try? AgentJobStore.append(
                kind: .cancelled,
                payload: .init(message: message, cancelled: true),
                to: job,
                in: context.modelContext,
                at: event.createdAt
            )
        } else if event.kind == "error" || event.phase == "failed" {
            let code = event.payload["code"]?.stringValue ?? "remote_failed"
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

    private func projectRemoteSpan(
        _ span: AgentTraceSpan,
        job: AgentJob,
        responseMessage: CoachMessage,
        trace: AgentTrace,
        context: ConversationProcessingContext
    ) {
        trace.apply(.span(span))
        responseMessage.applyAgentEvent(.span(span))
        _ = try? AgentJobStore.append(
            kind: .span,
            payload: .init(span: span),
            to: job,
            in: context.modelContext,
            at: span.endedAt
        )
    }

    private func remoteResponseMessage(
        for job: AgentJob,
        turnID: UUID,
        sessionID: UUID,
        in context: ModelContext
    ) -> CoachMessage {
        let messages = (
            try? context.fetch(FetchDescriptor<CoachMessage>())
        ) ?? []
        if let responseID = job.responseMessageID,
           let existing = messages.first(where: { $0.id == responseID })
        {
            existing.agentStatus = .running
            return existing
        }
        let response = CoachMessage(
            sessionID: sessionID,
            isFromCoach: true,
            text: "",
            agentStatus: .running,
            turnID: turnID,
            attemptNumber: nextAttemptNumber(for: turnID, in: context)
        )
        context.insert(response)
        job.responseMessageID = response.id
        try? context.save()
        return response
    }

    private func remoteTrace(
        for response: CoachMessage,
        turnID: UUID,
        dataSpace: DataSpace,
        endpoint: URL,
        input: String,
        in context: ModelContext
    ) -> AgentTrace {
        let traces = (try? context.fetch(FetchDescriptor<AgentTrace>())) ?? []
        if let traceID = response.agentTraceID,
           let existing = traces.first(where: { $0.id == traceID })
        {
            return existing
        }
        let trace = AgentTrace(
            provider: "Soma Managed",
            model: "managed",
            endpoint: endpoint.absoluteString,
            dataSpaceRaw: dataSpace.rawValue,
            userInput: input,
            contextSnapshot: "由用户启用的后台持续处理；仅发送当前任务最小上下文。",
            mediaKind: .none,
            imageCount: 0,
            imageAttachmentCount: 0,
            videoAttachmentCount: 0,
            turnID: turnID,
            attemptNumber: response.attemptNumber
        )
        context.insert(trace)
        response.agentTraceID = trace.id
        try? context.save()
        return trace
    }

    private func failRemoteJob(
        _ job: AgentJob,
        message: String,
        context: ConversationProcessingContext
    ) {
        if !job.state.isTerminal, job.state.canTransition(to: .failed) {
            try? job.transition(to: .failed, error: message)
            _ = try? AgentJobStore.append(
                kind: .failed,
                payload: .init(message: message),
                to: job,
                in: context.modelContext
            )
        }
        try? context.modelContext.save()
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
            context: context
        )
        let projection = prepared.projection
        let history = prepared.history
        let historicalFrameCount = history.reduce(0) { $0 + $1.images.count }
        let persistentContext = composePersistentContext(
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
        let agentContext = [persistentContext, weatherGuidance]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        var performedRecordType: ConversationIntent?
        var activeTrace: AgentTrace?
        let resumable = job.hasResumableCheckpoint
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
                本地准备耗时 \(prepared.preparationMilliseconds) ms（含历史媒体重新抽帧）。
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
            try? context.modelContext.save()

            let activePrograms = (
                try? context.modelContext.fetch(FetchDescriptor<TrainingProgram>())
            ) ?? []
            let activeSessions = (
                try? context.modelContext.fetch(FetchDescriptor<WorkoutSession>())
            ) ?? []
            let toolSignals = AgentToolExposureSignals(
                text: userMessage.text,
                hasVideo: media.hasVideo,
                hasActiveProgram: activePrograms.contains { $0.status == .active },
                hasActiveGuidedSession: activeSessions.contains {
                    [.draft, .active, .paused].contains($0.status)
                }
            )
            let resumeCheckpoint = resumable ? job.loopCheckpoint : nil
            let outcome = try await context.ai.runAgent(
                text: userMessage.text,
                images: media.frames,
                videos: directVideos,
                hasVideo: media.hasVideo,
                imageAttachmentCount: media.imageCount,
                videoAttachmentCount: media.videoCount,
                history: history,
                context: agentContext,
                route: route,
                toolSignals: toolSignals,
                checkpoint: resumeCheckpoint,
                onCheckpoint: { checkpoint in
                    job.loopCheckpoint = checkpoint
                    try? context.modelContext.save()
                },
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
                let result = AgentMutationStore.execute(
                    call,
                    turnID: turnID,
                    in: context.modelContext
                ) {
                    ConversationRecorder.executeAgentTool(
                        call,
                        sourceText: userMessage.text,
                        sourceDate: userMessage.date,
                        sourceSessionID: context.session.id,
                        sourceTurnID: turnID,
                        mediaKind: media.primaryKind,
                        mediaPath: media.primaryPath,
                        mediaAttachments: attributedMedia,
                        preferredGymID: resolution.gymID,
                        in: context.modelContext
                    )
                }
                if let recordType = result.recordType {
                    performedRecordType = recordType
                }
                return result
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
}

private extension ConversationProcessingService {
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
            responseMessage.text = waitingText
            responseMessage.agentStatus = .cancelled
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
            responseMessage.text = message + "LLM 恢复后会自动继续。"
            responseMessage.agentStatus = .cancelled
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
        case .fail:
            break
        }
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
        if let activeTrace, activeTrace.status == .running {
            activeTrace.apply(.failed(
                message: reason,
                cancelled: false,
                at: .now
            ))
        }
        if !responseMessage.agentTurnItems.contains(where: { $0.kind == .error }) {
            responseMessage.applyAgentEvent(.failed(
                message: reason,
                cancelled: false,
                at: .now
            ))
        }
        if job.state == .running {
            try? job.transition(to: .failed, error: reason)
        }
        context.session.touch(at: .now)
        try? context.modelContext.save()
    }

    private func composePersistentContext(
        userMessage: CoachMessage,
        turnID: UUID,
        effectiveGym: GymProfile?,
        resolution: GymContextResolution,
        context: ConversationProcessingContext
    ) -> String {
        let crossTurnFacts = AgentCrossTurnFactSummary.recentMutationFacts(
            sessionID: context.session.id,
            excludingTurnID: turnID,
            in: context.modelContext
        )
        let olderDigest = AgentCrossTurnFactSummary.olderTurnDigest(
            messages: allMessages(in: context.modelContext),
            sessionID: context.session.id,
            excludingTurnID: turnID
        )
        return [
            context.structuredContext,
            turnContext(
                location: userMessage.location,
                gym: effectiveGym,
                source: resolution.source
            ),
            crossTurnFacts,
            olderDigest
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private func bindResponseMessage(
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
        let completedItems = message.agentTurnItems.filter { item in
            item.status != .running && item.kind != .error
        }
        message.replaceAgentTurnItems(completedItems)
        if !job.responseTextSnapshot.isEmpty {
            message.text = job.responseTextSnapshot
        } else {
            let pausedHints = ["已保存本次任务", "已保存进度", "回到前台"]
            if pausedHints.contains(where: { message.text.contains($0) }) {
                message.text = ""
            }
        }
        message.agentStatus = .running
    }

    private func nextAttemptNumber(
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
        dataSpace = nil
        sessionID = nil
        processingTask = nil
    }

    private func startNextPendingJob(
        dataSpace: DataSpace,
        ai: AIService,
        modelContext: ModelContext,
        locationService: LocationContextService
    ) {
        guard !isProcessing else { return }
        let now = Date.now
        let jobs = (
            try? modelContext.fetch(
                FetchDescriptor<AgentJob>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        let runnable = jobs.filter {
            $0.dataSpace == dataSpace && $0.state.isRunnable
        }
        // ADR 0045：后端不可用的 Job 统一落到暂存，让队列状态与 UI 计数保持一致。
        for job in runnable where job.state != .staged {
            guard let reason = backendUnavailableReason(job.backend, ai: ai) else {
                continue
            }
            try? AgentJobStore.stage(
                job,
                message: reason,
                retryDelay: nil,
                in: modelContext
            )
        }
        let scoped = runnable.filter {
            isBackendAvailable($0.backend, ai: ai)
        }
        let messages = (try? modelContext.fetch(FetchDescriptor<CoachMessage>())) ?? []
        let messageByID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        // 回复已失败的 Job 不应被回前台自动领取，避免「失败气泡又自己跑起来」。
        for job in scoped {
            guard let responseID = job.responseMessageID,
                  messageByID[responseID]?.agentStatus == .failed,
                  job.state.canTransition(to: .failed)
            else {
                continue
            }
            try? job.transition(
                to: .failed,
                error: "上次处理已失败，等待手动重试。"
            )
            job.leaseOwner = nil
            job.leaseExpiresAt = nil
        }
        try? modelContext.save()
        let runnableAfterFailureGate = scoped.filter { job in
            guard job.state.isRunnable else { return false }
            guard let responseID = job.responseMessageID else { return true }
            return messageByID[responseID]?.agentStatus != .failed
        }
        guard let job = runnableAfterFailureGate.first(where: {
            $0.nextRetryAt == nil || $0.nextRetryAt! <= now
        }) else {
            scheduleRetry(
                at: runnableAfterFailureGate.compactMap(\.nextRetryAt).min(),
                dataSpace: dataSpace,
                ai: ai,
                modelContext: modelContext,
                locationService: locationService
            )
            return
        }
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

    private func scheduleRetry(
        at date: Date?,
        dataSpace: DataSpace,
        ai: AIService,
        modelContext: ModelContext,
        locationService: LocationContextService?
    ) {
        guard let date, let locationService else { return }
        retryTask?.cancel()
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
                locationService: locationService
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

    private func mediaDisplaySummary(
        _ attachments: [MediaAttachmentReference]
    ) -> String {
        let imageCount = attachments.count { $0.kind == .image }
        let videoCount = attachments.count { $0.kind == .video }
        let parts = [
            imageCount > 0 ? "\(imageCount) 张图片" : nil,
            videoCount > 0 ? "\(videoCount) 个视频" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "发送了媒体" : "发送了" + parts.joined(separator: "和")
    }

    private func prepareStoredMedia(
        _ attachments: [MediaAttachmentReference],
        frameLimit: Int
    ) async -> PreparedConversationMedia {
        guard frameLimit > 0 else {
            return PreparedConversationMedia(
                attachments: attachments,
                frames: [],
                imageCount: attachments.count { $0.kind == .image },
                videoCount: attachments.count { $0.kind == .video },
                failedVideoCount: 0
            )
        }
        var frameGroups: [[Data]] = []
        var videos: [AgentVideoInput] = []
        var imageCount = 0
        var videoCount = 0
        var failedVideoCount = 0
        for attachment in attachments {
            switch attachment.kind {
            case .none:
                continue
            case .image:
                guard let url = MediaStore.url(at: attachment.path) else {
                    continue
                }
                if let data = try? Data(contentsOf: url) {
                    frameGroups.append([data])
                    imageCount += 1
                }
            case .video:
                videoCount += 1
                guard let url = MediaStore.url(at: attachment.path) else {
                    failedVideoCount += 1
                    continue
                }
                let frames = await VideoFrameCache.frames(for: url)
                frameGroups.append(frames)
                if let data = try? Data(contentsOf: url),
                   data.count <= 24 * 1024 * 1024
                {
                    videos.append(AgentVideoInput(
                        data: data,
                        mimeType: videoMIMEType(for: url)
                    ))
                }
                if frames.isEmpty {
                    failedVideoCount += 1
                }
            }
        }
        return PreparedConversationMedia(
            attachments: attachments,
            frames: Self.balancedFrames(from: frameGroups, limit: frameLimit),
            videos: videos,
            imageCount: imageCount,
            videoCount: videoCount,
            failedVideoCount: failedVideoCount
        )
    }

    /// 首个请求发出前的本地准备（上下文投影 + 历史媒体重新抽帧）需要单独计时，
    /// 否则一次「慢」无法区分是供应商排队还是我们自己的准备开销。
    private func prepareHistory(
        excludingTurnID turnID: UUID,
        currentFrameCount: Int,
        context: ConversationProcessingContext
    ) async -> PreparedAgentHistory {
        let startedAt = Date.now
        let projection = ConversationContextProjection.make(
            messages: allMessages(in: context.modelContext),
            sessionID: context.session.id,
            excludingTurnID: turnID
        )
        let history = await prepareAgentHistory(
            projection.exchanges,
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
        frameLimit: Int
    ) async -> [AgentConversationExchange] {
        var remainingFrameCount = max(0, frameLimit)
        var framesByTurnID: [UUID: [Data]] = [:]

        for exchange in exchanges.reversed() where remainingFrameCount > 0 {
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

    private static func balancedFrames(
        from groups: [[Data]],
        limit: Int
    ) -> [Data] {
        guard limit > 0 else { return [] }
        var result: [Data] = []
        var index = 0
        while result.count < limit {
            var appended = false
            for group in groups where index < group.count {
                result.append(group[index])
                appended = true
                if result.count == limit {
                    return result
                }
            }
            guard appended else { break }
            index += 1
        }
        return result
    }

    private func videoMIMEType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": "video/mp4"
        case "avi": "video/x-msvideo"
        case "webm": "video/webm"
        default: "video/quicktime"
        }
    }

    private func applyLiveAgentEvent(_ event: AgentTraceEvent) {
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
                liveAgentActivity = "模型正在响应…"
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
