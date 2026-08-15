import Foundation
import SwiftData

struct PreparedRemoteAgentSubmission {
    var modelInput: PreparedAgentModelInput
    var mediaMode: AgentMediaMode
    var historyExchangeCount: Int
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
        let activePrograms = (
            try? context.modelContext.fetch(FetchDescriptor<TrainingProgram>())
        ) ?? []
        let activeSessions = (
            try? context.modelContext.fetch(FetchDescriptor<WorkoutSession>())
        ) ?? []
        let groups = AgentToolExposurePolicy.initialGroups(signals: .init(
            text: userMessage.text,
            hasVideo: media.hasVideo,
            hasActiveProgram: activePrograms.contains { $0.status == .active },
            hasActiveGuidedSession: activeSessions.contains {
                [.draft, .active, .paused].contains($0.status)
            }
        ))
        let userPrompt = ReActAgentPrompt.user(
            text: userMessage.text,
            context: agentContext,
            imageCount: media.frames.count,
            hasVideo: media.hasVideo,
            directVideoCount: media.videos.count,
            imageAttachmentCount: media.imageCount,
            videoAttachmentCount: media.videoCount
        )
        let modelInput = try AgentModelInputBuilder.build(
            systemPrompt: ReActAgentPrompt.system(defaults: context.ai.defaults),
            history: preparedHistory.history,
            userPrompt: userPrompt,
            currentImages: media.frames,
            currentVideos: media.videos,
            skills: AgentSkill.snapshots(defaults: context.ai.defaults),
            tools: AgentToolExposurePolicy.tools(for: groups),
            maxSteps: ReActAgentPreference.maxSteps(defaults: context.ai.defaults),
            deadlinePolicy: context.ai.streamDeadlinePolicy
        )
        return PreparedRemoteAgentSubmission(
            modelInput: modelInput,
            mediaMode: media.mode,
            historyExchangeCount: preparedHistory.history.count
        )
    }
}
