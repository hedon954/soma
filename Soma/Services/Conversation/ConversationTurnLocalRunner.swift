import Foundation
import Observation
import SwiftData

@MainActor
extension ConversationProcessingService {
    func runAttempt(
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
            projection: projection,
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
        let agentContext = [persistentContext, weatherGuidance]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        var performedRecordType: ConversationIntent?
        var activeTrace: AgentTrace?
        // 同一 Job 无论失败发生在第几个 step，都复用原回复气泡。
        let resumable = job.responseMessageID != nil
        let (responseMessage, attemptNumber) = ConversationTurnPersistence.bindResponseMessage(
            job: job,
            turnID: turnID,
            resumable: resumable,
            context: context
        )
        try? context.modelContext.save()

        do {
            let route = context.ai.route(
                text: userMessage.text,
                hasMedia: !media.attachments.isEmpty || history.contains { !$0.images.isEmpty || !$0.videos.isEmpty },
                hasVideo: media.hasVideo || history.contains { !$0.videos.isEmpty }
            )
            let directVideos = media.videos
            if media.failedVideoCount > 0 || history.contains(where: \.videoPreparationFailed) {
                throw ConversationMediaPreparationError.fullVideoUnavailable
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
                媒体模式：\(media.mode.rawValue)；视频字节 \(media.videos.reduce(0) { $0 + $1.data.count })；图片 \(media.frames.count)。
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
                    "video_bytes": ConversationMediaMetrics.videoBytes(media.attachments),
                    "image_count": media.frames.count,
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
            try? context.modelContext.save()

            let resumeCheckpoint = resumable ? job.loopCheckpoint : nil
            let firstStepDeadlineEnabled = !job.firstStepDeadlineConsumed
            job.firstStepDeadlineConsumed = true
            try? context.modelContext.save()
            let deadlinePolicy = ReActAgentPreference.deadlinePolicy(
                context.ai.streamDeadlinePolicy,
                defaults: context.ai.defaults
            )
            let loopBudget = deadlinePolicy.loopTotal(
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
                    configuration: job.contextSnapshot?.configuration,
                    turnID: turnID,
                    historySummary: compaction.summary,
                    firstStepDeadlineEnabled: firstStepDeadlineEnabled,
                    onCheckpoint: { checkpoint in
                        job.loopCheckpoint = checkpoint
                        job.responseTextSnapshot = checkpoint.assistantPassages
                            .joined(separator: "\n\n")
                        try? context.modelContext.save()
                    },
                    trace: { [weak self] event in
                        let liveText = self?.pendingLiveTextSnapshot(for: event)
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
                                liveText: liveText,
                                in: context.modelContext
                            )
                        }
                        self?.applyLiveAgentEvent(event)
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
            if let checkpoint = job.loopCheckpoint {
                var snapshot = job.contextSnapshot
                snapshot?.canonicalTurn = AgentCanonicalTurn.make(
                    checkpoint: checkpoint, user: userMessage.text, answer: outcome.finalAnswer
                )
                job.contextSnapshot = snapshot
                var completed = checkpoint
                completed.initialInput = nil
                job.loopCheckpoint = completed
            }
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
                context: context
            )
            return
        }

        context.session.touch(at: .now)
        try? context.modelContext.save()
    }

    func handleAttemptFailure(
        _ error: Error,
        job: AgentJob,
        responseMessage: CoachMessage,
        activeTrace: AgentTrace?,
        performedRecordType: ConversationIntent?,
        media: PreparedConversationMedia,
        context: ConversationProcessingContext
    ) {
        // 主动中断已经同步投影到同一气泡并进入人工屏障；Task cancellation
        // 只负责停止底层执行，不能再覆盖成另一条通用错误。
        if job.state == .waitingForUser,
           responseMessage.agentStatus == .cancelled
        {
            context.session.touch(at: .now)
            try? context.modelContext.save()
            return
        }
        let reason = AppErrorMessage.message(for: error, operation: .model)
        if backgroundLeaseExpired {
            let pausedText = job.hasResumableCheckpoint
                ? "Soma 已保存进度，回到前台后会从中断处继续。"
                : "Soma 已保存本次任务，回到前台后会继续处理。"
            if !job.responseTextSnapshot.isEmpty {
                responseMessage.text = job.responseTextSnapshot
            } else {
                responseMessage.text = ""
            }
            responseMessage.setAgentActivity(
                phase: .queued,
                message: pausedText
            )
            responseMessage.agentStatus = .cancelled
            if job.state == .running {
                try? job.transition(to: .waitingForForeground)
            }
            job.leaseOwner = nil
            job.leaseExpiresAt = nil
            _ = try? ConversationTurnPersistence.append(
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
        case let .waitForUser(message):
            job.submissionAttemptCount += 1
            responseMessage.text = ""
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
                    message: message,
                    cancelled: false,
                    at: .now
                ))
            }
            try? ConversationTurnPersistence.waitForUser(
                job,
                message: message,
                in: context.modelContext
            )
            try? ConversationTurnPersistence.stageFollowingJobs(
                after: job,
                message: "前一条消息等待手动重试；本条已按发送顺序暂存。",
                in: context.modelContext
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
        responseMessage.text = ""
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
                message: failureText,
                cancelled: false,
                at: .now
            ))
        }
        try? ConversationTurnPersistence.waitForUser(
            job,
            message: "这一步需要你手动重试。",
            in: context.modelContext
        )
        try? ConversationTurnPersistence.stageFollowingJobs(
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
        if let existing = job.contextSnapshot?.executionContext {
            return existing
        }
        let observedAt = Date.now
        let time = job.contextSnapshot?.envelope?.trustedTime.promptText
            ?? "发送时间：\(userMessage.date.ISO8601Format())；历史时区信息未知。"
        let businessDate = job.effectiveBusinessDate ?? context.session.effectiveBusinessDate
        let snapshotContext = [
            "[TURN \(turnID.uuidString.lowercased())]",
            time,
            "[执行前本机业务快照 observed_at=\(observedAt.ISO8601Format())]",
            context.structuredContext(for: businessDate, selectedSkillID: job.selectedSkillID),
            AgentCrossTurnFactSummary.recentMutationFacts(
                sessionID: job.sessionID, excludingTurnID: turnID, in: context.modelContext
            ),
            turnContext(location: userMessage.location, gym: effectiveGym, source: resolution.source)
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
        var snapshot = job.contextSnapshot ?? AgentJobContextSnapshot(
            structuredContext: context.structuredContext, includeLocation: false
        )
        snapshot.executionContext = snapshotContext
        snapshot.executionObservedAt = observedAt
        job.contextSnapshot = snapshot
        try? context.modelContext.save()
        return snapshotContext
    }

    func turnContext(
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
            messages: ConversationContextHistory.messages(
                sessionID: context.session.id,
                in: context.modelContext
            ),
            sessionID: context.session.id,
            excludingTurnID: turnID,
            turnContexts: ConversationContextHistory.trustedTimes(
                sessionID: context.session.id, in: context.modelContext
            ),
            canonicalTurns: ConversationContextHistory.canonicalTurns(sessionID: context.session.id, in: context.modelContext)
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

    func prepareAgentHistory(
        _ exchanges: [ConversationContextProjection.Exchange],
        selectedTurnIDs: Set<UUID>,
        frameLimit: Int
    ) async -> [AgentConversationExchange] {
        var remainingFrameCount = max(0, frameLimit)
        var mediaByTurnID: [UUID: PreparedConversationMedia] = [:]

        for exchange in exchanges.reversed()
            where selectedTurnIDs.contains(exchange.turnID)
        {
            let media = await prepareStoredMedia(
                exchange.mediaAttachments,
                frameLimit: remainingFrameCount
            )
            mediaByTurnID[exchange.turnID] = media
            remainingFrameCount -= media.frames.count
        }

        return exchanges.map { exchange in
            AgentConversationExchange(
                turnID: exchange.turnID,
                sentAt: exchange.date,
                trustedTime: exchange.trustedTime,
                canonicalMessages: exchange.canonicalMessages,
                userText: exchange.userText,
                assistantText: exchange.assistantText,
                images: mediaByTurnID[exchange.turnID]?.frames ?? [],
                videos: mediaByTurnID[exchange.turnID]?.videos ?? [],
                videoPreparationFailed: (mediaByTurnID[exchange.turnID]?.failedVideoCount ?? 0) > 0,
                imageAttachmentCount: exchange.imageAttachmentCount,
                videoAttachmentCount: exchange.videoAttachmentCount
            )
        }
    }
}
