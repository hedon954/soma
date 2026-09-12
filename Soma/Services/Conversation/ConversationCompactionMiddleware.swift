import Foundation
import SwiftData
import SwiftOpenAI

struct ConversationCompactionResult: Sendable {
    var summary: String?
    var didUpdate: Bool
    var strategy: ConversationCompactionStrategy?
}

@MainActor
enum ConversationCompactionMiddleware {
    static func prepare(
        sessionID: UUID,
        excludingTurnID: UUID,
        projection: ConversationContextProjection? = nil,
        ai: AIService,
        in context: ModelContext
    ) async -> ConversationCompactionResult {
        let plan = projection ?? ConversationContextProjection.make(
            messages: ConversationContextHistory.messages(sessionID: sessionID, in: context),
            sessionID: sessionID,
            excludingTurnID: excludingTurnID,
            turnContexts: ConversationContextHistory.trustedTimes(sessionID: sessionID, in: context),
            canonicalTurns: ConversationContextHistory.canonicalTurns(sessionID: sessionID, in: context)
        )
        let evicted = plan.evictedExchanges
        var descriptor = FetchDescriptor<ConversationCompactionSummary>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        descriptor.fetchLimit = 1
        let stored = try? context.fetch(descriptor).first
        guard !evicted.isEmpty else {
            if let stored {
                context.delete(stored); try? context.save()
            }
            return ConversationCompactionResult(summary: nil, didUpdate: stored != nil, strategy: nil)
        }
        let coverage = ConversationSummarySource.coverage(evicted)
        if stored?.coverage == coverage {
            return ConversationCompactionResult(summary: stored?.summary, didUpdate: false, strategy: stored?.strategy)
        }
        // Only extend a summary whose source prefix is still identical. Legacy coverage,
        // edits, deletions and a larger raw window require rebuilding from original messages.
        let old = stored?.coverage
        let oldCount = old?.turnIDs.count ?? 0
        let canExtend = old != nil && oldCount <= evicted.count
            && old?.turnIDs == Array(coverage.turnIDs.prefix(oldCount))
            && old?.fingerprints == Array(coverage.fingerprints.prefix(oldCount))
        let sources = canExtend ? Array(evicted.dropFirst(oldCount)) : evicted
        var summary = canExtend ? stored?.summary : nil
        var strategy = ConversationCompactionStrategy.deterministic
        for batch in ConversationSummarySource.batches(sources) {
            let input = ConversationSummarySource.input(existing: summary, exchanges: batch)
            if let small = try? await ai.compactConversation(input, tier: .small), valid(small) {
                summary = small
                strategy = .smallModel
            } else if let standard = try? await ai.compactConversation(input, tier: .standard), valid(standard) {
                summary = standard
                strategy = .standardModel
            } else {
                summary = ConversationSummarySource.deterministic(existing: summary, exchanges: batch)
                strategy = .deterministic
            }
            if Task.isCancelled {
                return ConversationCompactionResult(summary: nil, didUpdate: false, strategy: nil)
            }
        }
        guard let summary else {
            return ConversationCompactionResult(summary: nil, didUpdate: false, strategy: nil)
        }
        let value = stored ?? ConversationCompactionSummary(
            sessionID: sessionID, summary: summary, coveredTurnIDs: [], strategy: strategy
        )
        value.summary = summary
        value.coverage = coverage
        value.strategy = strategy
        value.updatedAt = .now
        if stored == nil {
            context.insert(value)
        }
        try? context.save()
        return ConversationCompactionResult(summary: summary, didUpdate: true, strategy: strategy)
    }

    private static func valid(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.count <= ConversationSummarySource.maximumSummaryCharacters
    }
}

extension AIService {
    func compactConversation(
        _ input: String,
        tier: AIModelTier
    ) async throws -> String {
        let provider = provider(for: tier)
        let route = AIModelRoute(
            tier: tier,
            provider: provider,
            baseURL: baseURL(for: provider, tier: tier),
            model: model(for: provider, tier: tier),
            reason: "Session 滚动压缩"
        )
        let resolved = try resolvedRoute(
            requested: route,
            text: input,
            hasMedia: false,
            hasVideo: false
        )
        var messages = [
            ChatCompletionParameters.Message(
                role: .system,
                content: .text("你是 Soma 的对话压缩器。只压缩输入，不回答用户，也不创造事实。")
            ),
            ChatCompletionParameters.Message(role: .user, content: .text(input))
        ]
        let outcome = try await consumeAgentStepWithRetry(
            messages: &messages,
            request: AgentStreamStepRequest(
                tools: [],
                model: resolved.route.model,
                provider: resolved.route.provider,
                images: [],
                videos: [],
                hasVideo: false,
                step: 0,
                route: resolved.route,
                apiKey: resolved.apiKey,
                userPrompt: input,
                textItemID: UUID()
            ),
            trace: nil
        )
        let text = outcome.passage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ReActAgentError.emptyResponse }
        return text
    }
}
