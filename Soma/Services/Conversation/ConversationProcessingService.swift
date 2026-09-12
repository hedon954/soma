import Foundation
import Observation
import SwiftData

/// 对话写入路径编排器：用户消息 → Job/Event → 本地/远程 Attempt → 投影。
/// 持久化经 `ConversationTurnPersistence`；工具写入经 `ConversationRecorder`。
@MainActor
@Observable
final class ConversationProcessingService {
    static let maximumAnalysisImageCount = 12
    /// 配合 step 检查点分段续跑；到期前会落盘检查点。
    static let executionLeaseDuration: TimeInterval = 45
    let runnerOwner = UUID().uuidString.lowercased()

    var isProcessing = false
    var dataSpace: DataSpace?
    var sessionID: UUID?

    @ObservationIgnored
    var liveAssistantItemID: UUID?

    @ObservationIgnored
    var liveAssistantTextBuffer = LiveAgentTextBuffer()

    @ObservationIgnored
    var liveReasoningItemID: UUID?

    @ObservationIgnored
    var liveReasoningTextBuffer = LiveAgentTextBuffer()

    var liveEventRevision = 0

    /// 仅供显式性能夹具把跨层完成阶段暴露给 UI 自动化；普通运行始终为 nil。
    var performanceFixturePhase: String?

    @ObservationIgnored
    var remoteTextCoalescer = AgentTextDeltaCoalescer()

    @ObservationIgnored
    var remoteTextItemID: UUID?

    @ObservationIgnored
    var remoteModelReceivedFirstDelta = false

    @ObservationIgnored
    var remoteProjectionJobID: UUID?

    @ObservationIgnored
    var remoteProjectionCursor = 0

    @ObservationIgnored
    var processingTask: Task<Void, Never>?

    @ObservationIgnored
    var activeJobID: UUID?

    @ObservationIgnored
    var performanceFixtureTask: Task<Void, Never>?

    @ObservationIgnored
    let backgroundLease: BackgroundExecutionLease

    @ObservationIgnored
    var backgroundLeaseExpired = false

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
        let persistedAttachments: [MediaAttachmentReference]
        do {
            persistedAttachments = try persistPendingAttachments(attachments)
        } catch {
            return false
        }
        return submitPersisted(
            text: text,
            attachments: persistedAttachments,
            context: context,
            includeLocation: includeLocation,
            locationService: locationService,
            selectedShortcutID: selectedShortcutID,
            forceLocal: forceLocal
        )
    }

    @discardableResult
    func submitAsync(
        text: String,
        attachments: [PendingAttachment],
        context: ConversationProcessingContext,
        includeLocation: Bool,
        locationService: LocationContextService,
        selectedShortcutID: String? = nil,
        forceLocal: Bool = false
    ) async -> Bool {
        let persistedAttachments: [MediaAttachmentReference]
        do {
            persistedAttachments = try await persistPendingAttachmentsAsync(attachments)
        } catch {
            return false
        }
        return submitPersisted(
            text: text,
            attachments: persistedAttachments,
            context: context,
            includeLocation: includeLocation,
            locationService: locationService,
            selectedShortcutID: selectedShortcutID,
            forceLocal: forceLocal
        )
    }

    func submitPersisted(
        text: String,
        attachments persistedAttachments: [MediaAttachmentReference],
        context: ConversationProcessingContext,
        includeLocation: Bool,
        locationService: LocationContextService,
        selectedShortcutID: String?,
        forceLocal: Bool,
        questionAction: AgentQuestionAction? = nil
    ) -> Bool {
        // ADR 0045：发送不再以 LLM 当前可用为前提，也不因为已有任务在途而拒绝。
        let useRemote = questionAction == nil && !forceLocal && RemoteAgentPreference.isEnabled()
        let selectedShortcut = selectedShortcutID.flatMap {
            AgentInputShortcutStore.shortcut(id: $0)
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
            businessSummary: context.structuredContext(
                for: businessDate,
                selectedSkillID: selectedShortcut?.skillID
            ),
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

        var frozenContext = job.contextSnapshot
        frozenContext?.configuration = try? AgentPromptConfiguration.capture(
            defaults: context.ai.defaults,
            selectedSkillID: job.selectedSkillID,
            selectedShortcutID: job.selectedShortcutID
        )
        job.contextSnapshot = frozenContext

        if let questionAction {
            job.executionKind = .deterministicQuestion
            job.deterministicQuestionAction = questionAction
        }
        do {
            context.session.recordUserMessage(displayText, at: submittedAt)
            try ConversationTurnPersistence.enqueue(
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
        let dataSpaceRaw = context.dataSpace.rawValue
        let jobID = job.id
        let jobCreatedAt = job.createdAt
        let waitingForUser = AgentJobState.waitingForUser.rawValue
        var blockingDescriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate {
                $0.dataSpaceRaw == dataSpaceRaw
                    && $0.id != jobID
                    && $0.createdAt <= jobCreatedAt
                    && $0.stateRaw == waitingForUser
            }
        )
        blockingDescriptor.fetchLimit = 1
        if ((try? context.modelContext.fetchCount(blockingDescriptor)) ?? 0) > 0 {
            try? ConversationTurnPersistence.stage(
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
            try? ConversationTurnPersistence.stage(
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
        job.executionKind != .react
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
        liveAssistantItemID = nil
        liveAssistantTextBuffer.reset()
        liveReasoningItemID = nil
        liveReasoningTextBuffer.reset()
        remoteTextCoalescer = AgentTextDeltaCoalescer()
        remoteTextItemID = nil
        remoteModelReceivedFirstDelta = false
        remoteProjectionJobID = nil
        remoteProjectionCursor = 0
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
            try ConversationTurnPersistence.claim(
                job,
                owner: runnerOwner,
                leaseDuration: Self.executionLeaseDuration,
                in: context.modelContext
            )
        } catch {
            finishProcessing()
            return
        }
        activeJobID = job.id
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
                _ = try? ConversationTurnPersistence.append(
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
                userMessage.location = await locationService.requestSnapshot()
                try? context.modelContext.save()
            }
            if job.executionKind == .deterministicQuestion {
                await runDeterministicQuestionAttempt(job: job, userMessage: userMessage, context: context)
                finishProcessing()
                if let locationService {
                    startNextPendingJob(dataSpace: context.dataSpace, ai: context.ai, modelContext: context.modelContext, locationService: locationService)
                }
                return
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

    func finishProcessing() {
        backgroundLease.end()
        backgroundLeaseExpired = false
        liveAssistantItemID = nil
        liveAssistantTextBuffer.reset()
        liveReasoningItemID = nil
        liveReasoningTextBuffer.reset()
        remoteTextCoalescer = AgentTextDeltaCoalescer()
        remoteTextItemID = nil
        remoteModelReceivedFirstDelta = false
        remoteProjectionJobID = nil
        remoteProjectionCursor = 0
        isProcessing = false
        AppRunSentinel.shared.recordActivity(
            sessionID: sessionID,
            turnID: nil,
            activity: "idle"
        )
        dataSpace = nil
        sessionID = nil
        activeJobID = nil
        processingTask = nil
    }

    func startNextPendingJob(
        dataSpace: DataSpace,
        ai: AIService,
        modelContext: ModelContext,
        locationService: LocationContextService
    ) {
        guard !isProcessing else { return }
        _ = try? ConversationTurnPersistence.promoteFailedResponsesToManualRetry(
            dataSpace: dataSpace,
            in: modelContext
        )
        let dataSpaceRaw = dataSpace.rawValue
        let succeeded = AgentJobState.succeeded.rawValue
        let failed = AgentJobState.failed.rawValue
        let cancelled = AgentJobState.cancelled.rawValue
        var jobDescriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate {
                $0.dataSpaceRaw == dataSpaceRaw
                    && $0.stateRaw != succeeded
                    && $0.stateRaw != failed
                    && $0.stateRaw != cancelled
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        jobDescriptor.fetchLimit = 1
        guard let job = try? modelContext.fetch(jobDescriptor).first else {
            return
        }
        // FIFO 只看队头。失败一旦可见，就只能由用户显式释放。
        if job.state == .waitingForUser
            || job.state == .waitingForNetwork
            || job.state == .staged
        {
            return
        }
        if job.executionKind == .react,
           let reason = backendUnavailableReason(job.backend, ai: ai)
        {
            try? ConversationTurnPersistence.stage(
                job,
                message: reason,
                retryDelay: nil,
                in: modelContext
            )
            return
        }
        guard job.state.isRunnable else { return }
        guard job.nextRetryAt == nil else { return }
        guard let userMessage = ConversationTurnPersistence.message(id: job.userMessageID, in: modelContext),
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
                _ = try? ConversationTurnPersistence.append(
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

    func persistPendingAttachments(
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

    func persistPendingAttachmentsAsync(
        _ attachments: [PendingAttachment]
    ) async throws -> [MediaAttachmentReference] {
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
                    let path = try await MediaStore.saveImageAsync(data)
                    references.append(.init(kind: .image, path: path))
                case .video:
                    guard let url = attachment.videoURL else {
                        throw ConversationMediaPreparationError.attachmentPersistenceFailed
                    }
                    let path = try await MediaStore.saveVideoAsync(from: url)
                    references.append(.init(kind: .video, path: path))
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
}
