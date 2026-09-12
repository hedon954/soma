import CryptoKit
import Foundation

struct AgentCanonicalTurn: Codable, Equatable, Sendable {
    var sourceFingerprint: String
    var messages: [AgentModelMessage]

    static func fingerprint(user: String, assistant: String?, correction: String?) -> String {
        let data = (try? JSONEncoder().encode([user, assistant ?? "", correction ?? ""])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func make(checkpoint: AgentLoopCheckpoint, user: String, answer: String) -> Self? {
        guard let current = checkpoint.initialInput?.messages.last, current.role == .user else { return nil }
        var frames = [current]
        for batch in checkpoint.toolBatches ?? [] {
            guard batch.isComplete else { return nil }
            if batch.calls.isEmpty {
                // Recovery frames have no private reasoning text.
                frames.append(AgentModelMessage(role: .assistant, text: batch.passage))
                frames.append(AgentModelMessage(role: .user, text: AgentFinalAnswerRecoveryPrompt.text))
                continue
            }
            frames.append(AgentModelMessage(role: .assistant, text: batch.passage, toolCalls: batch.calls.map {
                AgentModelToolCall(id: $0.id, name: $0.action.name.rawValue, arguments: $0.argumentsJSON)
            }))
            frames.append(contentsOf: batch.completedResults.map {
                AgentModelMessage(role: .tool, text: AgentTraceText.json($0.result), toolCallID: $0.call.id)
            })
        }
        frames.append(AgentModelMessage(role: .assistant, text: answer))
        return Self(sourceFingerprint: fingerprint(user: user, assistant: answer, correction: nil), messages: frames)
    }

    static func hasCompleteToolBatches(_ frames: [AgentModelMessage]) -> Bool {
        var pending = Set<String>()
        for frame in frames {
            if let calls = frame.toolCalls {
                guard frame.role == .assistant else { return false }
                for call in calls where !pending.insert(call.id).inserted {
                    return false
                }
            }
            if frame.role == .tool {
                guard let id = frame.toolCallID, pending.remove(id) != nil else { return false }
            } else if !pending.isEmpty {
                return false
            }
        }
        return pending.isEmpty
    }
}
