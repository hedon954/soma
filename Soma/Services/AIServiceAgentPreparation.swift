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
    var toolSignals: AgentToolExposureSignals?
    var checkpoint: AgentLoopCheckpoint?
}

struct PreparedAgentRun {
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
            hasMedia: !request.images.isEmpty,
            hasVideo: request.hasVideo
        )
        let route = routing.route
        let support = ModelCapability.multimodalSupport(
            provider: route.provider,
            model: route.model
        )
        let historicalImageCount = request.history.reduce(0) { $0 + $1.images.count }
        let hasVisualInput = !request.images.isEmpty
            || !request.videos.isEmpty
            || historicalImageCount > 0
        if hasVisualInput, support == .unsupported {
            throw AIServiceError.multimodalUnsupported(
                provider: route.provider.displayName,
                model: route.model
            )
        }
        let systemPrompt = ReActAgentPrompt.system(defaults: defaults)
        let userPrompt = ReActAgentPrompt.user(
            text: request.text,
            context: request.context,
            imageCount: request.images.count,
            hasVideo: request.hasVideo,
            directVideoCount: request.videos.count,
            imageAttachmentCount: request.imageAttachmentCount,
            videoAttachmentCount: request.videoAttachmentCount
        )
        let historyForPrompt = request.checkpoint == nil
            ? request.history
            : request.history.map(removingImages)
        var exposedGroups = restoredToolGroups(request)
        if exposedGroups.isEmpty {
            exposedGroups = [.core]
        }
        let exposedTools = AgentToolExposurePolicy.tools(for: exposedGroups)
        let maxSteps = ReActAgentPreference.maxSteps(defaults: defaults)
        let modelInput = try AgentModelInputBuilder.build(
            systemPrompt: systemPrompt,
            history: historyForPrompt,
            userPrompt: userPrompt,
            currentImages: request.images,
            currentVideos: request.videos,
            skills: AgentSkill.snapshots(defaults: defaults),
            tools: exposedTools,
            maxSteps: maxSteps,
            deadlinePolicy: streamDeadlinePolicy
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
            exposedGroups: exposedGroups
        )
        let batches = request.checkpoint?.toolBatches ?? []
        restoreCheckpointBatches(batches, state: &toolState)
        return PreparedAgentRun(
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
            exposedGroups: state.exposedGroups.map(\.rawValue).sorted(),
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

    private func restoredToolGroups(
        _ request: AgentRunPreparationRequest
    ) -> Set<AgentToolGroup> {
        if let checkpoint = request.checkpoint, !checkpoint.exposedGroups.isEmpty {
            return Set(checkpoint.exposedGroups.compactMap(AgentToolGroup.init(rawValue:)))
        }
        return AgentToolExposurePolicy.initialGroups(
            signals: request.toolSignals ?? AgentToolExposureSignals(
                text: request.text,
                hasVideo: request.hasVideo,
                hasActiveProgram: false,
                hasActiveGuidedSession: false
            )
        )
    }

    private func removingImages(
        _ exchange: AgentConversationExchange
    ) -> AgentConversationExchange {
        AgentConversationExchange(
            userText: exchange.userText,
            assistantText: exchange.assistantText,
            images: [],
            imageAttachmentCount: exchange.imageAttachmentCount,
            videoAttachmentCount: exchange.videoAttachmentCount
        )
    }
}
