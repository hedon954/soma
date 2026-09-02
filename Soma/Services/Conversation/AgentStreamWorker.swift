import Foundation
import SwiftOpenAI

/// 原始 SSE chunk、长字符串和 Tool Call 参数都在通用执行器上累积；只有已经合批的
/// 可见文字回到 MainActor。这样模型流得越久，也不会持续占用触摸与 SwiftUI 提交队列。
enum AgentStreamWorker {
    static func consume(
        stream: AsyncThrowingStream<ChatCompletionChunkObject, Error>,
        mediaMode: AgentMediaMode,
        policy: AgentStreamDeadlinePolicy,
        enforceFirstDelta: Bool,
        textItemID: UUID,
        reasoningItemID: UUID,
        project: @escaping @MainActor (AgentTraceEvent) -> Void
    ) async throws -> AgentStreamOutcome {
        var outcome = AgentStreamOutcome()
        var toolCallDeltas: [Int: AgentStreamingToolCall] = [:]
        let projectionPump = AgentTextProjectionPump { text in
            project(.assistantTextDelta(itemID: textItemID, delta: text))
        }
        let reasoningProjectionPump = AgentTextProjectionPump { text in
            project(.reasoningDelta(itemID: reasoningItemID, delta: text))
        }

        do {
            try await AgentStreamDeadline.consume(
                stream: stream,
                mode: mediaMode,
                policy: policy,
                enforceFirstDelta: enforceFirstDelta
            ) { chunk in
                if let chunkUsage = chunk.usage {
                    outcome.usage = chunkUsage
                }
                var meaningful = false
                for choice in chunk.choices ?? [] where (choice.index ?? 0) == 0 {
                    guard let delta = choice.delta else { continue }
                    if outcome.firstDeltaAt == nil,
                       delta.content?.isEmpty == false
                       || delta.reasoningContent?.isEmpty == false
                       || delta.toolCalls?.isEmpty == false
                    {
                        outcome.firstDeltaAt = Date()
                        meaningful = true
                    }
                    if let content = delta.content, !content.isEmpty {
                        outcome.passage += content
                        await projectionPump.append(content)
                    }
                    if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
                        outcome.reasoning += reasoning
                        await reasoningProjectionPump.append(reasoning)
                    }
                    for (position, toolDelta) in (delta.toolCalls ?? []).enumerated() {
                        let index = toolDelta.index ?? position
                        var accumulator = toolCallDeltas[index]
                            ?? AgentStreamingToolCall()
                        accumulator.append(toolDelta)
                        toolCallDeltas[index] = accumulator
                    }
                }
                return meaningful
            }
        } catch {
            outcome.projectionSeconds = await projectionPump.finish()
            _ = await reasoningProjectionPump.finish()
            throw StreamingFailure.interrupted(
                error,
                passage: outcome.passage,
                reasoning: outcome.reasoning,
                receivedMeaningfulDelta: outcome.firstDeltaAt != nil
            )
        }
        outcome.projectionSeconds = await projectionPump.finish()
        outcome.projectionSeconds += await reasoningProjectionPump.finish()
        outcome.toolCalls = toolCallDeltas.keys.sorted().compactMap {
            toolCallDeltas[$0]
        }
        outcome.ttftBudgetMilliseconds = Int(
            (policy.ttft(for: mediaMode) * 1000).rounded()
        )
        return outcome
    }
}
