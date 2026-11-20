import CryptoKit
import Foundation

enum ConversationSummarySource {
    static let maximumSummaryCharacters = 3000
    static let maximumBatchTokens = 8000

    static func text(_ exchange: ConversationContextProjection.Exchange) -> String {
        """
        turn_id=\(exchange.turnID.uuidString.lowercased()) sent_at=\(exchange.date.ISO8601Format())
        \(exchange.trustedTime?.promptText ?? "历史时区与业务日期未知；不得用本轮日期替代。")
        user: \(exchange.userText)
        assistant: \(exchange.assistantText ?? "（无完成回复，不代表没有已成功的写入）")
        原生执行资料：\(exchange.canonicalMessages.map { $0.map(\.text).joined(separator: "\n") } ?? "无")
        """
    }

    static func coverage(_ exchanges: [ConversationContextProjection.Exchange]) -> ConversationSummaryCoverage {
        ConversationSummaryCoverage(turnIDs: exchanges.map(\.turnID), fingerprints: exchanges.map {
            SHA256.hash(data: Data(text($0).utf8)).map { String(format: "%02x", $0) }.joined()
        })
    }

    static func batches(_ exchanges: [ConversationContextProjection.Exchange]) -> [[ConversationContextProjection.Exchange]] {
        var batches: [[ConversationContextProjection.Exchange]] = []
        var batch: [ConversationContextProjection.Exchange] = []
        var tokens = 0
        for exchange in exchanges {
            let cost = ConversationContextProjection.estimatedTokens(boundedText(exchange))
            if !batch.isEmpty, tokens + cost > maximumBatchTokens {
                batches.append(batch)
                batch = []
                tokens = 0
            }
            batch.append(exchange)
            tokens += cost
        }
        if !batch.isEmpty {
            batches.append(batch)
        }
        return batches
    }

    static func boundedText(_ exchange: ConversationContextProjection.Exchange) -> String {
        let value = text(exchange)
        guard value.count > 6000 else { return value }
        return String(value.prefix(4000)) + "\n[原文过长，仅保留首尾；精确信息须按来源回查]\n" + value.suffix(1800)
    }

    static func input(existing: String?, exchanges: [ConversationContextProjection.Exchange]) -> String {
        SomaPrompt.text("conversation_summary_user_prompt", [
            "existing": existing ?? "无已有摘要。",
            "exchanges": exchanges.map(boundedText).joined(separator: "\n\n")
        ])
    }

    static func deterministic(existing: String?, exchanges: [ConversationContextProjection.Exchange]) -> String {
        let additions = exchanges.map {
            "- [\($0.turnID.uuidString.lowercased()) \($0.date.ISO8601Format())] 用户：\($0.userText.prefix(120))；回复：\(($0.assistantText ?? "无完成回复").prefix(160))"
        }
        var lines: [String] = []
        var size = 100
        for line in ((existing?.components(separatedBy: "\n") ?? []) + additions).reversed() {
            guard size + line.count + 1 <= maximumSummaryCharacters else { break }
            lines.append(line)
            size += line.count + 1
        }
        return "[有界历史摘录；内容可能省略，精确信息须回查来源；不作为当前状态或授权]\n" + lines.reversed().joined(separator: "\n")
    }
}
