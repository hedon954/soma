import Foundation
import SwiftOpenAI

struct AgentRunPreparationRequest {
    var text: String
    var images: [Data]
    var videos: [AgentVideoInput]
    var hasVideo: Bool
    var imageAttachmentCount: Int?
    var videoAttachmentCount: Int?
    var history: [AgentConversationExchange]
    var context: String
    var requestedRoute: AIModelRoute?
    var selectedSkillID: String?
    var selectedShortcutID: String?
    var checkpoint: AgentLoopCheckpoint?
}

struct PreparedAgentRun {
    var videos: [AgentVideoInput]
    var selectedRoute: AIModelRoute
    var apiKey: String
    var support: MultimodalSupport
    var historicalImageCount: Int
    var hasVisualInput: Bool
    var userPrompt: String
    var traceInput: String
    var currentModelStep: Int
    var modelInput: AgentModelInputEnvelope
    var toolState: AgentToolLoopState
    var assistantPassages: [String]
    var checkpointBatches: [AgentCheckpointToolBatch]
    var completedOperationCount: Int
    var clearedHistoryFrames: Bool
    var maxSteps: Int
}

extension AIService {
    func prepareAgentRun(
        _ request: AgentRunPreparationRequest
    ) throws -> PreparedAgentRun {
        let routing = try resolvedRoute(
            requested: request.requestedRoute,
            text: request.text,
            hasMedia: !request.images.isEmpty || request.history.contains { !$0.images.isEmpty || !$0.videos.isEmpty },
            hasVideo: request.hasVideo || request.history.contains { !$0.videos.isEmpty }
        )
        let route = routing.route
        let assessment = modelMultimodalAssessment(
            provider: route.provider,
            baseURL: route.baseURL,
            model: route.model
        )
        if (!request.videos.isEmpty || request.history.contains { !$0.videos.isEmpty }),
           assessment.directVideoSupport == false
        {
            throw ConversationMediaPreparationError.fullVideoUnavailable
        }
        let support = assessment.support
        let historicalImageCount = request.history.reduce(0) { $0 + $1.images.count }
        if request.history.contains(where: \.videoPreparationFailed) {
            throw ConversationMediaPreparationError.fullVideoUnavailable
        }
        let historicalVideoCount = request.history.reduce(0) { $0 + $1.videos.count }
        let hasVisualInput = historicalVideoCount > 0 || !request.images.isEmpty
            || !request.videos.isEmpty
            || historicalImageCount > 0
        if hasVisualInput, support == .unsupported {
            throw AIServiceError.multimodalUnsupported(
                provider: route.provider.displayName,
                model: route.model
            )
        }
        let systemPrompt = ReActAgentPrompt.system(
            defaults: defaults,
            selectedSkillID: request.selectedSkillID
        )
        let selectedSkill = request.selectedSkillID
            .flatMap { AgentSkillRegistry.descriptor(id: $0, defaults: defaults) }
        let userPrompt = ReActAgentPrompt.user(
            text: request.text,
            context: request.context,
            imageCount: request.images.count,
            hasVideo: request.hasVideo,
            directVideoCount: request.videos.count,
            imageAttachmentCount: request.imageAttachmentCount,
            videoAttachmentCount: request.videoAttachmentCount,
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
        let historyForPrompt = request.checkpoint == nil
            ? request.history
            : request.history.map(removingImages)
        let exposedTools = exposedTools(request)
        let maxSteps = ReActAgentPreference.maxSteps(defaults: defaults)
        let deadlinePolicy = ReActAgentPreference.deadlinePolicy(
            streamDeadlinePolicy,
            defaults: defaults
        )
        let modelInput = try AgentModelInputBuilder.build(
            systemPrompt: systemPrompt,
            history: historyForPrompt,
            userPrompt: userPrompt,
            currentImages: request.images,
            currentVideos: request.videos,
            skills: AgentSkill.snapshots(
                defaults: defaults,
                selectedSkillID: selectedSkill?.id
            ),
            tools: exposedTools,
            selectedSkillID: selectedSkill?.id,
            maxSteps: maxSteps,
            deadlinePolicy: deadlinePolicy
        )
        var messages = chatMessages(from: modelInput)
        let isLegacyCheckpoint = request.checkpoint != nil
            && request.checkpoint?.toolBatches == nil
        if let checkpoint = request.checkpoint,
           isLegacyCheckpoint,
           !checkpoint.observations.isEmpty
        {
            messages.append(ChatCompletionParameters.Message(
                role: .user,
                content: .text(compactedCheckpointPrompt(checkpoint))
            ))
        }
        var toolState = AgentToolLoopState(
            messages: messages,
            tools: exposedTools.map(\.chatTool),
            exposedToolNames: exposedTools.map(\.rawValue)
        )
        let batches = request.checkpoint?.toolBatches ?? []
        restoreCheckpointBatches(batches, state: &toolState)
        let videosByID = Dictionary(uniqueKeysWithValues: modelInput.media.compactMap { payload -> (String, AgentVideoInput)? in
            guard case let .video(id, input) = payload else { return nil }
            return (id, input)
        })
        let indexedVideos = modelInput.envelope.messages.enumerated().flatMap { index, message in
            message.mediaIDs.compactMap { id -> AgentVideoInput? in
                guard var video = videosByID[id] else { return nil }
                video.messageIndex = index
                return video
            }
        }
        return PreparedAgentRun(
            videos: indexedVideos,
            selectedRoute: route,
            apiKey: routing.apiKey,
            support: support,
            historicalImageCount: historicalImageCount,
            hasVisualInput: hasVisualInput,
            userPrompt: userPrompt,
            traceInput: AgentTraceText.modelInput(
                systemPrompt: systemPrompt,
                history: historyForPrompt,
                userPrompt: userPrompt
            ),
            currentModelStep: request.checkpoint?.nextModelStep
                ?? max(1, (request.checkpoint?.lastCompletedStep ?? 0) + 1),
            modelInput: modelInput.envelope,
            toolState: toolState,
            assistantPassages: request.checkpoint?.assistantPassages ?? [],
            checkpointBatches: batches,
            completedOperationCount: request.checkpoint?.lastCompletedStep ?? 0,
            clearedHistoryFrames: request.checkpoint != nil,
            maxSteps: maxSteps
        )
    }

    func makeAgentCheckpoint(
        completedOperationCount: Int,
        assistantPassages: [String],
        state: AgentToolLoopState,
        nextModelStep: Int,
        batches: [AgentCheckpointToolBatch]
    ) -> AgentLoopCheckpoint {
        AgentLoopCheckpoint(
            lastCompletedStep: completedOperationCount,
            assistantPassages: assistantPassages,
            observations: state.observations.map {
                AgentCheckpointObservation(
                    step: $0.step,
                    action: $0.action,
                    result: $0.result
                )
            },
            exposedToolNames: state.exposedToolNames,
            nextModelStep: nextModelStep,
            toolBatches: batches
        )
    }

    func completeAgentRun(
        passage: String,
        assistantPassages: [String],
        observations: [AgentObservation],
        trace: ((AgentTraceEvent) -> Void)?
    ) throws -> AgentOutcome {
        let trimmedPassage = passage.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = trimmedPassage.isEmpty
            ? assistantPassages.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            : trimmedPassage
        guard !answer.isEmpty else { throw ReActAgentError.emptyResponse }
        let completedAt = Date()
        trace?(.span(AgentTraceSpan(
            kind: .output,
            title: "最终回复",
            status: .succeeded,
            startedAt: completedAt,
            endedAt: completedAt,
            output: answer
        )))
        trace?(.completed(answer: answer, at: completedAt))
        return AgentOutcome(finalAnswer: answer, observations: observations)
    }

    /// ADR 0082：恢复优先沿用 checkpoint 的曝光集合；首轮按选中的快捷按钮收窄，
    /// 未选快捷按钮时全量曝光。
    private func exposedTools(
        _ request: AgentRunPreparationRequest
    ) -> [AgentToolName] {
        let restored = request.checkpoint?.restoredToolNames ?? []
        if !restored.isEmpty {
            return AgentToolExposurePolicy.tools(names: restored)
        }
        let shortcut = request.selectedShortcutID.flatMap {
            AgentInputShortcutStore.shortcut(id: $0, defaults: defaults)
        }
        return AgentToolExposurePolicy.tools(selectedShortcut: shortcut)
    }

    private func removingImages(
        _ exchange: AgentConversationExchange
    ) -> AgentConversationExchange {
        AgentConversationExchange(
            userText: exchange.userText,
            assistantText: exchange.assistantText,
            images: [],
            videos: exchange.videos,
            videoPreparationFailed: exchange.videoPreparationFailed,
            imageAttachmentCount: exchange.imageAttachmentCount,
            videoAttachmentCount: exchange.videoAttachmentCount
        )
    }
}
