import Foundation
import SwiftData

struct PreparedRemoteAgentSubmission {
    var modelInput: PreparedAgentModelInput
    var mediaMode: AgentMediaMode
    var historyExchangeCount: Int
    var compactionSummary: String?
    var compactionStrategy: ConversationCompactionStrategy?
}

@MainActor
extension ConversationProcessingService {
    func prepareRemoteSubmission(
        job: AgentJob,
        userMessage: CoachMessage,
        turnID: UUID,
        context: ConversationProcessingContext,
        client: RemoteAgentClient
    ) async throws -> PreparedRemoteAgentSubmission {
        let hasVideo = job.mediaAttachments.contains { $0.kind == .video }
        var capabilities = hasVideo ? try await client.capabilities() : nil
        var supportsDirectVideo = capabilities?.directVideo == true
        var supportsFrameFallback = capabilities?.videoFrameFallback == true
        if hasVideo, !supportsDirectVideo, !supportsFrameFallback {
            throw RemoteAgentError.server(code: "direct_video_unsupported", message: "远程服务暂不支持视频分析。请更新远程服务，或关闭远程执行后使用本机的模型配置重试。")
        }
        let media = await prepareStoredMedia(
            job.mediaAttachments,
            frameLimit: Self.maximumAnalysisImageCount,
            directVideoCapability: supportsDirectVideo || supportsFrameFallback
                ? DirectVideoCapability(
                    maximumRawBytes: 7 * 1024 * 1024,
                    preferredMIMEType: "video/mp4"
                )
                : nil
        )
        if media.failedVideoCount > 0,
           media.videos.count != media.videoCount
        {
            throw RemoteAgentError.server(
                code: "full_video_unavailable",
                message: "完整视频准备失败，请使用体积更小的可播放视频后重试。"
            )
        }
        let resolution = GymLocationResolver.resolve(
            text: userMessage.text,
            snapshot: userMessage.location,
            gyms: context.gyms
        )
        userMessage.effectiveGymID = resolution.gymID
        let effectiveGym = resolution.gymID.flatMap { id in
            context.gyms.first { $0.id == id }
        }
        let preparedHistory = await prepareHistory(
            excludingTurnID: turnID,
            currentFrameCount: media.frames.count,
            currentText: userMessage.text,
            hasCurrentMedia: !media.attachments.isEmpty,
            selectedHistoricalTurnIDs: job.contextSnapshot?.envelope?
                .selectedHistoricalTurnIDs,
            context: context
        )
        if preparedHistory.history.contains(where: \.videoPreparationFailed) {
            throw ConversationMediaPreparationError.fullVideoUnavailable
        }
        if preparedHistory.history.contains(where: { !$0.videos.isEmpty }), capabilities == nil {
            capabilities = try await client.capabilities()
            supportsDirectVideo = capabilities?.directVideo == true
            supportsFrameFallback = capabilities?.videoFrameFallback == true
        }
        if preparedHistory.history.contains(where: { !$0.videos.isEmpty }),
           !supportsDirectVideo, !supportsFrameFallback
        {
            throw RemoteAgentError.server(code: "direct_video_unsupported", message: "远程模型未开启完整视频输入。")
        }
        let compaction = await ConversationCompactionMiddleware.prepare(
            sessionID: job.sessionID,
            excludingTurnID: turnID,
            projection: preparedHistory.projection,
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
        let configuration = try job.contextSnapshot?.configuration ?? AgentPromptConfiguration.capture(
            defaults: context.ai.defaults, selectedSkillID: job.selectedSkillID,
            selectedShortcutID: job.selectedShortcutID
        )
        let selectedSkill = configuration.skills.first { $0.id == configuration.selectedSkillID }
        let userPrompt = ReActAgentPrompt.user(
            text: userMessage.text,
            context: agentContext,
            imageCount: media.frames.count,
            hasVideo: media.hasVideo,
            directVideoCount: media.videos.count,
            imageAttachmentCount: media.imageCount,
            videoAttachmentCount: media.videoCount,
            selectedSkill: selectedSkill
        )
        var modelInput = try AgentModelInputBuilder.build(
            systemPrompt: configuration.systemPrompt,
            currentTurnID: turnID,
            historySummary: compaction.summary,
            history: preparedHistory.history,
            userPrompt: userPrompt,
            currentImages: media.frames,
            currentVideos: media.videos,
            skills: configuration.skills,
            tools: configuration.tools.map(\.name),
            selectedSkillID: selectedSkill?.id,
            maxSteps: ReActAgentPreference.maxSteps(defaults: context.ai.defaults),
            deadlinePolicy: ReActAgentPreference.deadlinePolicy(
                context.ai.streamDeadlinePolicy,
                defaults: context.ai.defaults
            )
        )
        modelInput.envelope.tools = configuration.tools
        if supportsFrameFallback {
            do {
                modelInput = try await AgentModelVideoFallbackPreparation.adding(to: modelInput)
            } catch {
                try Task.checkCancellation()
                if !supportsDirectVideo {
                    throw error
                }
            }
        }
        let usesFrames = !supportsDirectVideo && modelInput.envelope.videoFallbacks?.isEmpty == false
        if job.contextSnapshot?.remoteCanonicalFrames == nil,
           let currentFrame = modelInput.envelope.messages.last,
           currentFrame.role == .user
        {
            var snapshot = job.contextSnapshot
            snapshot?.remoteCanonicalFrames = [currentFrame]
            job.contextSnapshot = snapshot
            try? context.modelContext.save()
        }
        return PreparedRemoteAgentSubmission(
            modelInput: modelInput,
            mediaMode: usesFrames ? .keyframes : media.mode,
            historyExchangeCount: preparedHistory.history.count,
            compactionSummary: compaction.didUpdate ? compaction.summary : nil,
            compactionStrategy: compaction.strategy
        )
    }
}
