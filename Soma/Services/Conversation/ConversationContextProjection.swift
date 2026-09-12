import Foundation

struct ConversationContextProjection {
    static let defaultMaximumExchangeCount = 30
    static let defaultMaximumEstimatedTokens = 30000

    struct Exchange {
        var turnID: UUID
        var date: Date = .distantPast
        var trustedTime: TrustedTurnContext?
        var canonicalMessages: [AgentModelMessage]?
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
    var evictedExchanges: [Exchange] = []
    var estimatedHistoryTokens: Int = 0
    var isOverBudget = false

    static func make(
        messages: [CoachMessage],
        sessionID: UUID,
        excludingTurnID: UUID?,
        turnContexts: [UUID: TrustedTurnContext] = [:],
        canonicalTurns: [UUID: AgentCanonicalTurn] = [:],
        maximumExchangeCount: Int = defaultMaximumExchangeCount,
        maximumEstimatedTokens: Int = defaultMaximumEstimatedTokens
    ) -> ConversationContextProjection {
        let sessionMessages = messages
            .filter { $0.sessionID == sessionID }
            .sorted { $0.date < $1.date }
        let currentDate = sessionMessages.first { !$0.isFromCoach && $0.turnID == excludingTurnID }?.date
        let candidates = sessionMessages
            .filter { message in
                !message.isFromCoach && message.turnID != excludingTurnID
                    && (currentDate == nil || message.date < currentDate!)
            }
        let assistantsByTurnID = sessionMessages.reduce(
            into: [UUID: CoachMessage]()
        ) { result, message in
            guard message.isFromCoach, let turnID = message.turnID else { return }
            guard let current = result[turnID] else {
                result[turnID] = message
                return
            }
            if message.attemptNumber > current.attemptNumber
                || (message.attemptNumber == current.attemptNumber
                    && message.date > current.date)
            {
                result[turnID] = message
            }
        }

        let exchanges = candidates.map { userMessage in
            let assistantMessage = userMessage.turnID.flatMap {
                assistantsByTurnID[$0]
            }
            let assistantText = [
                assistantMessage?.text,
                assistantMessage?.manualCorrectionSummary.map {
                    "[用户在回复卡片中的最新修订]\n\($0)"
                }
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            let saved = userMessage.turnID.flatMap { canonicalTurns[$0] }
            let revision = AgentCanonicalTurn.fingerprint(
                user: userMessage.text, assistant: assistantMessage?.text,
                correction: assistantMessage?.manualCorrectionSummary
            )
            return Exchange(
                turnID: userMessage.turnID ?? userMessage.id,
                date: userMessage.date,
                trustedTime: userMessage.turnID.flatMap { turnContexts[$0] },
                canonicalMessages: saved?.sourceFingerprint == revision ? saved?.messages : nil,
                userText: userMessage.text,
                assistantText: assistantText.isEmpty ? nil : assistantText,
                mediaAttachments: userMessage.mediaAttachments
            )
        }
        var selected: [Exchange] = []
        var tokenCount = 0
        for exchange in exchanges.reversed() {
            guard selected.count < max(0, maximumExchangeCount) else { break }
            let actualText = exchange.canonicalMessages.map {
                $0.map { frame in
                    frame.text + (frame.toolCalls ?? []).map { $0.name + $0.arguments }.joined()
                }.joined(separator: "\n")
            } ?? (exchange.userText + "\n" + (exchange.assistantText ?? ""))
            let exchangeTokens = estimatedTokens(actualText)
            if !selected.isEmpty,
               tokenCount + exchangeTokens > maximumEstimatedTokens
            {
                break
            }
            selected.append(exchange)
            tokenCount += exchangeTokens
        }
        return ConversationContextProjection(
            exchanges: Array(selected.reversed()),
            evictedExchanges: Array(exchanges.dropLast(selected.count)),
            estimatedHistoryTokens: tokenCount,
            isOverBudget: tokenCount > maximumEstimatedTokens
        )
    }

    static func estimatedTokens(_ text: String) -> Int {
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
