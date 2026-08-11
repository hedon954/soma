import Foundation

struct ConversationContextProjection {
    static let defaultMaximumExchangeCount = 10
    static let defaultMaximumEstimatedTokens = 6000

    struct Exchange {
        var turnID: UUID
        var date: Date = .distantPast
        var userText: String
        var assistantText: String?
        var mediaAttachments: [MediaAttachmentReference]

        var imageAttachmentCount: Int {
            mediaAttachments.count { $0.kind == .image }
        }

        var videoAttachmentCount: Int {
            mediaAttachments.count { $0.kind == .video }
        }
    }

    var exchanges: [Exchange]

    static func make(
        messages: [CoachMessage],
        sessionID: UUID,
        excludingTurnID: UUID?,
        maximumExchangeCount: Int = defaultMaximumExchangeCount,
        maximumEstimatedTokens: Int = defaultMaximumEstimatedTokens
    ) -> ConversationContextProjection {
        guard maximumExchangeCount > 0 else {
            return ConversationContextProjection(exchanges: [])
        }

        let sessionMessages = messages
            .filter { $0.sessionID == sessionID }
            .sorted { $0.date < $1.date }
        let candidates = sessionMessages
            .filter { message in
                !message.isFromCoach && message.turnID != excludingTurnID
            }
            .suffix(maximumExchangeCount)

        let exchanges = candidates.map { userMessage in
            let assistantMessage = userMessage.turnID.flatMap { turnID in
                sessionMessages
                    .filter { $0.isFromCoach && $0.turnID == turnID }
                    .max { lhs, rhs in
                        if lhs.attemptNumber == rhs.attemptNumber {
                            return lhs.date < rhs.date
                        }
                        return lhs.attemptNumber < rhs.attemptNumber
                    }
            }
            let assistantText = assistantMessage?.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Exchange(
                turnID: userMessage.turnID ?? userMessage.id,
                date: userMessage.date,
                userText: userMessage.text,
                assistantText: assistantText?.isEmpty == false ? assistantText : nil,
                mediaAttachments: userMessage.mediaAttachments
            )
        }
        var selected: [Exchange] = []
        var tokenCount = 0
        for exchange in exchanges.reversed() {
            let exchangeTokens = estimatedTokens(
                exchange.userText + "\n" + (exchange.assistantText ?? "")
            )
            if !selected.isEmpty,
               tokenCount + exchangeTokens > maximumEstimatedTokens
            {
                break
            }
            selected.append(exchange)
            tokenCount += exchangeTokens
        }
        return ConversationContextProjection(exchanges: Array(selected.reversed()))
    }

    private static func estimatedTokens(_ text: String) -> Int {
        var tokens = 0
        var asciiRun = 0
        func flushASCII() {
            guard asciiRun > 0 else { return }
            tokens += Int(ceil(Double(asciiRun) / 4.0))
            asciiRun = 0
        }
        for scalar in text.unicodeScalars {
            if scalar.isASCII {
                asciiRun += 1
            } else {
                flushASCII()
                tokens += 1
            }
        }
        flushASCII()
        return max(tokens, 1)
    }
}

enum HistoricalMediaSelectionPolicy {
    static func selectedTurnIDs(
        currentText: String,
        hasCurrentMedia: Bool,
        exchanges: [ConversationContextProjection.Exchange]
    ) -> [UUID] {
        guard !hasCurrentMedia else { return [] }
        let mediaTurns = exchanges.filter { !$0.mediaAttachments.isEmpty }
        guard !mediaTurns.isEmpty else { return [] }
        let text = currentText.lowercased()
        let comparison = ["对比", "比较", "两张", "两个视频", "分别看", "compare"]
            .contains { text.contains($0) }
        if comparison {
            return mediaTurns.suffix(2).map(\.turnID)
        }
        let reference = [
            "上一张", "上张", "刚才", "上一条", "那个视频", "上个视频",
            "之前那张", "前一张", "这张图", "that photo", "previous video"
        ].contains { text.contains($0) }
        return reference ? mediaTurns.suffix(1).map(\.turnID) : []
    }
}
