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
        ai: AIService,
        in context: ModelContext
    ) async -> ConversationCompactionResult {
        let messages = (try? context.fetch(
            FetchDescriptor<CoachMessage>(
                predicate: #Predicate { $0.sessionID == sessionID },
                sortBy: [SortDescriptor(\.date)]
            )
        )) ?? []
        let pairs = completedPairs(messages: messages, excludingTurnID: excludingTurnID)
        let evicted = Array(pairs.dropLast(min(10, pairs.count)))
        var summaryDescriptor = FetchDescriptor<ConversationCompactionSummary>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        summaryDescriptor.fetchLimit = 1
        let stored = try? context.fetch(summaryDescriptor).first
        guard !evicted.isEmpty else {
            return ConversationCompactionResult(
                summary: stored?.summary,
                didUpdate: false,
                strategy: stored?.strategy
            )
        }

        let covered = Set(stored?.coveredTurnIDs ?? [])
        let newPairs = evicted.filter { !covered.contains($0.turnID) }
        guard !newPairs.isEmpty else {
            return ConversationCompactionResult(
                summary: stored?.summary,
                didUpdate: false,
                strategy: stored?.strategy
            )
        }

        let input = compactionInput(existing: stored?.summary, pairs: newPairs)
        let generated: (String, ConversationCompactionStrategy) = if let small = try? await ai.compactConversation(input, tier: .small),
                                                                     valid(small)
        {
            (small, .smallModel)
        } else if let standard = try? await ai.compactConversation(input, tier: .standard),
                  valid(standard)
        {
            (standard, .standardModel)
        } else {
            (deterministic(existing: stored?.summary, pairs: newPairs), .deterministic)
        }

        let allCovered = evicted.map(\.turnID)
        if let stored {
            stored.summary = generated.0
            stored.coveredTurnIDs = allCovered
            stored.strategy = generated.1
            stored.updatedAt = .now
        } else {
            context.insert(ConversationCompactionSummary(
                sessionID: sessionID,
                summary: generated.0,
                coveredTurnIDs: allCovered,
                strategy: generated.1
            ))
        }
        try? context.save()
        return ConversationCompactionResult(
            summary: generated.0,
            didUpdate: true,
            strategy: generated.1
        )
    }

    private struct Pair {
        var turnID: UUID
        var user: String
        var assistant: String
    }

    private static func completedPairs(
        messages: [CoachMessage],
        excludingTurnID: UUID
    ) -> [Pair] {
        messages.filter {
            !$0.isFromCoach && $0.turnID != excludingTurnID
        }.compactMap { user in
            let assistant = messages
                .filter {
                    $0.isFromCoach
                        && $0.turnID == user.turnID
                        && $0.agentStatus == .succeeded
                }
                .max { $0.attemptNumber < $1.attemptNumber }
            guard let assistant, let turnID = user.turnID else { return nil }
            return Pair(turnID: turnID, user: user.text, assistant: assistant.text)
        }
    }

    private static func compactionInput(existing: String?, pairs: [Pair]) -> String {
        let history = pairs.map {
            "turn_id=\($0.turnID.uuidString.lowercased())\nuser: \($0.user)\nassistant: \($0.assistant)"
        }.joined(separator: "\n\n")
        return """
        已有摘要（可能为空）：
        \(existing ?? "")

        本次移出完整窗口的对话：
        \(history)

        生成一份完全替代旧摘要的中文 Markdown。只保留用户明确目标、事实、限制、已作决定、
        未解决问题和稳定记录引用；不得补充推断。每条保留来源 turn_id。控制在 1200 字以内。
        """
    }

    private static func valid(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty && normalized.count <= 3000
    }

    private static func deterministic(existing: String?, pairs: [Pair]) -> String {
        var lines = existing.map { [$0] } ?? []
        lines.append(contentsOf: pairs.map {
            let user = $0.user.trimmingCharacters(in: .whitespacesAndNewlines)
            let assistant = $0.assistant.trimmingCharacters(in: .whitespacesAndNewlines)
            return "- [\($0.turnID.uuidString.lowercased())] 用户：\(String(user.prefix(120)))；回复：\(String(assistant.prefix(160)))"
        })
        return lines.joined(separator: "\n")
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
