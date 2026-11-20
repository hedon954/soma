import Foundation
import SwiftOpenAI

extension AIService {
    func completeTextPrompt(
        system: String,
        user: String,
        reason: String,
        tier: AIModelTier,
        recoverFinalAnswer: Bool = false
    ) async throws -> String {
        let provider = provider(for: tier)
        let requested = AIModelRoute(
            tier: tier,
            provider: provider,
            baseURL: baseURL(for: provider, tier: tier),
            model: model(for: provider, tier: tier),
            reason: reason
        )
        let resolved = try resolvedRoute(requested: requested, text: user, hasMedia: false, hasVideo: false)
        var messages = [
            ChatCompletionParameters.Message(
                role: .system,
                content: .text(system)
            ),
            ChatCompletionParameters.Message(role: .user, content: .text(user))
        ]
        var request = AgentStreamStepRequest(
            tools: [],
            model: resolved.route.model,
            provider: resolved.route.provider,
            images: [],
            videos: [],
            hasVideo: false,
            step: 0,
            route: resolved.route,
            apiKey: resolved.apiKey,
            userPrompt: user,
            textItemID: UUID()
        )
        let retryCount = recoverFinalAnswer ? AgentStepRetryPolicy.maximumRetryCount : 0
        var outcome = try await consumeAgentStepWithRetry(
            messages: &messages, request: request, maximumRetryCount: retryCount, trace: nil
        )
        if recoverFinalAnswer, outcome.passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !outcome.reasoning.isEmpty, outcome.toolCalls.isEmpty
        {
            request.assistantReasoningByMessageIndex[messages.count] = outcome.reasoning
            messages.append(ChatCompletionParameters.Message(role: .assistant, content: .text("")))
            messages.append(ChatCompletionParameters.Message(role: .user, content: .text(AgentFinalAnswerRecoveryPrompt.text)))
            request.step += 1
            outcome = try await consumeAgentStepWithRetry(
                messages: &messages, request: request, maximumRetryCount: retryCount, trace: nil
            )
        }
        let text = outcome.passage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ReActAgentError.emptyResponse }
        return text
    }
}
