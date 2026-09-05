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
        let supportsDirectVideo = if hasVideo {
            try await client.supportsDirectVideo()
        } else {
            false
        }
        if hasVideo, !supportsDirectVideo {
            throw RemoteAgentError.server(code: "direct_video_unsupported", message: "远程模型未开启完整视频输入，请切换支持视频的模型后重试。")
        }
        let media = await prepareStoredMedia(
            job.mediaAttachments,
            frameLimit: Self.maximumAnalysisImageCount,
            directVideoCapability: supportsDirectVideo
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
        if preparedHistory.history.contains(where: { !$0.videos.isEmpty }),
           try await !(client.supportsDirectVideo())
        {
            throw RemoteAgentError.server(code: "direct_video_unsupported", message: "远程模型未开启完整视频输入。")
        }
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
        let compactionContext = compaction.summary.map {
            "更早对话的可审查滚动摘要：\n\($0)"
        }
        let agentContext = [persistentContext, compactionContext, weatherGuidance]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let selectedSkill = job.selectedSkillID.flatMap {
            AgentSkillRegistry.descriptor(id: $0, defaults: context.ai.defaults)
        }
        // ADR 0082：远程执行仍由设备决定曝光边界，服务器只收到已经收窄的工具清单。
        let selectedShortcut = job.selectedShortcutID.flatMap {
            AgentInputShortcutStore.shortcut(id: $0, defaults: context.ai.defaults)
        }
        let userPrompt = ReActAgentPrompt.user(
            text: userMessage.text,
            context: agentContext,
            imageCount: media.frames.count,
            hasVideo: media.hasVideo,
            directVideoCount: media.videos.count,
            imageAttachmentCount: media.imageCount,
            videoAttachmentCount: media.videoCount,
            selectedSkill: selectedSkill.map {
                AgentModelSkillSnapshot(
                    id: $0.id,
                    name: $0.title,
                    description: $0.summary,
                    whenToUse: $0.whenToUse,
                    content: $0.markdown
                )
            }
        )
        let modelInput = try AgentModelInputBuilder.build(
            systemPrompt: ReActAgentPrompt.system(defaults: context.ai.defaults),
            history: preparedHistory.history,
            userPrompt: userPrompt,
            currentImages: media.frames,
            currentVideos: media.videos,
            skills: AgentSkill.snapshots(defaults: context.ai.defaults),
            tools: AgentToolExposurePolicy.tools(selectedShortcut: selectedShortcut),
            selectedSkillID: selectedSkill?.id,
            maxSteps: ReActAgentPreference.maxSteps(defaults: context.ai.defaults),
            deadlinePolicy: ReActAgentPreference.deadlinePolicy(
                context.ai.streamDeadlinePolicy,
                defaults: context.ai.defaults
            )
        )
        return PreparedRemoteAgentSubmission(
            modelInput: modelInput,
            mediaMode: media.mode,
            historyExchangeCount: preparedHistory.history.count,
            compactionSummary: compaction.didUpdate ? compaction.summary : nil,
            compactionStrategy: compaction.strategy
        )
    }
}
