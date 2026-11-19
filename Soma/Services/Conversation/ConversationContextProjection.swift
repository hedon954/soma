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

        var manualReceipts: [UUID: [String]] = [:]
        var standaloneReceipts: [Exchange] = []
        var precedingUser: UUID?
        for message in sessionMessages {
            if let currentDate, message.date >= currentDate {
                break
            }
            if !message.isFromCoach {
                precedingUser = message.id
            } else if message.isManualCorrectionReceipt, let summary = message.manualCorrectionSummary {
                if let precedingUser {
                    manualReceipts[precedingUser, default: []].append(summary)
                } else {
                    standaloneReceipts.append(Exchange(
                        turnID: message.id, date: message.date, userText: "[来自设备上的手动记录编辑]",
                        assistantText: summary, mediaAttachments: []
                    ))
                }
            }
        }
        let exchanges = standaloneReceipts + candidates.map { userMessage -> Exchange in
            let assistantMessage = userMessage.turnID.flatMap {
                assistantsByTurnID[$0]
            }
            var summaries: [String] = []
            if let correction = assistantMessage?.manualCorrectionSummary {
                summaries.append(correction)
            }
            summaries.append(contentsOf: manualReceipts[userMessage.id] ?? [])
            let corrections = summaries.isEmpty ? nil : summaries.joined(separator: "\n")
            let assistantText = [
                assistantMessage?.text,
                corrections.map { "[用户在回复卡片中的最新修订]\n\($0)" }
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            let saved = userMessage.turnID.flatMap { canonicalTurns[$0] }
            let revision = AgentCanonicalTurn.fingerprint(
                user: userMessage.text, assistant: assistantMessage?.text,
                correction: corrections
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
    static func mediaKind(for text: String) -> MediaKind? {
        let lower = text.lowercased()
        let image = ["张", "照片", "图片", "这张图", "photo", "image"].contains { lower.contains($0) }
        let video = ["视频", "录像", "video"].contains { lower.contains($0) }
        if image == video {
            return nil
        }
        return image ? .image : .video
    }

    static func imageOrdinal(in text: String, hasCurrentMedia: Bool = false) -> Int? {
        if hasCurrentMedia {
            let historicalOrdinal = #/(?:上次|上轮|上一轮|之前|前面|刚才|上一条)(?:发过的|发的|里的|的)?\s*第\s*(?:[0-9]+|[一二三四五六七八九十]{1,2})\s*张/#
            guard text.contains(historicalOrdinal) else { return nil }
        }
        let matches = text.matches(of: #/第\s*([0-9]+|[一二三四五六七八九十]{1,2})\s*张/#)
        guard matches.count == 1, let ordinal = matches.first?.1 else { return nil }
        if let number = Int(ordinal), number > 0 {
            return number
        }
        return ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二"]
            .firstIndex(of: String(ordinal)).map { $0 + 1 }
    }

    static func selectedTurnIDs(
        currentText: String,
        hasCurrentMedia: Bool,
        exchanges: [ConversationContextProjection.Exchange],
        archived: [ConversationContextProjection.Exchange] = []
    ) -> [UUID] {
        let text = currentText.lowercased()
        let kind = mediaKind(for: text)
        let refersToEarlierMedia = [
            "上一张", "上张", "刚才", "上一条", "那个视频", "上个视频", "刚发",
            "之前那张", "前一张", "that photo", "previous video", "上次发的", "前面发的"
        ].contains { text.contains($0) }
            || (kind != nil && ["之前的", "以前的", "上轮", "历史"].contains { text.contains($0) })
        let comparison = ["对比", "比较", "这两张", "那两个视频", "分别看", "compare"]
            .contains { text.contains($0) }
        guard !hasCurrentMedia || refersToEarlierMedia else { return [] }
        let mediaTurns = (archived + exchanges).filter { exchange in
            exchange.mediaAttachments.contains { kind == nil || $0.kind == kind }
        }
        guard !mediaTurns.isEmpty else { return [] }
        if let ordinal = imageOrdinal(in: text, hasCurrentMedia: hasCurrentMedia), !comparison || hasCurrentMedia,
           let exchange = mediaTurns.last(where: { $0.imageAttachmentCount >= ordinal })
        {
            return [exchange.turnID]
        }
        if comparison, kind != nil || refersToEarlierMedia {
            return mediaTurns.suffix(hasCurrentMedia ? 1 : 2).map(\.turnID)
        }
        let imageReference = text.contains("这张图") || imageOrdinal(in: text) != nil
        if refersToEarlierMedia || imageReference {
            return mediaTurns.suffix(1).map(\.turnID)
        }
        let correctsLatest = ["不是", "这不是", "不对", "应该是", "应该读", "你看错", "你认错", "单位错", "识别错", "重新识别", "更正"]
            .contains { text.hasPrefix($0) }
        if correctsLatest, let previous = exchanges.last, mediaTurns.last?.turnID == previous.turnID {
            return [previous.turnID]
        }
        return []
    }
}
