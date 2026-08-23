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
        let supportsDirectVideo = if job.remoteRequestAttempt == 1, hasVideo {
            try await client.supportsDirectVideo()
        } else {
            false
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
                code: "video_frames_unavailable",
                message: "视频未能产生可供模型分析的完整视频或关键帧。"
            )
        }
        let videoFallbackFrames: [Data] = if media.mode == .directVideo {
            await prepareStoredMedia(
                job.mediaAttachments.filter { $0.kind == .video },
                frameLimit: Self.maximumAnalysisImageCount
            ).frames
        } else {
            []
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
            currentVideoFrames: videoFallbackFrames,
            skills: AgentSkill.snapshots(defaults: context.ai.defaults),
            tools: AgentToolExposurePolicy.tools(selectedShortcut: selectedShortcut),
            selectedSkillID: selectedSkill?.id,
            maxSteps: ReActAgentPreference.maxSteps(defaults: context.ai.defaults),
            deadlinePolicy: context.ai.streamDeadlinePolicy
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
