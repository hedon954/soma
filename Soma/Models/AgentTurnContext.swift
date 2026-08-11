import Foundation

struct TrustedTurnContext: Codable, Equatable, Sendable {
    var turnSentAt: Date
    var attemptStartedAt: Date
    var timeZoneIdentifier: String
    var utcOffsetSeconds: Int
    var localDate: String
    var weekday: String

    static func make(
        turnSentAt: Date,
        attemptStartedAt: Date,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> TrustedTurnContext {
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = localCalendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = localCalendar
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.timeZone = timeZone
        weekdayFormatter.dateFormat = "EEEE"
        return TrustedTurnContext(
            turnSentAt: turnSentAt,
            attemptStartedAt: attemptStartedAt,
            timeZoneIdentifier: timeZone.identifier,
            utcOffsetSeconds: timeZone.secondsFromGMT(for: attemptStartedAt),
            localDate: dateFormatter.string(from: turnSentAt),
            weekday: weekdayFormatter.string(from: turnSentAt)
        )
    }

    func refreshingAttempt(at date: Date) -> TrustedTurnContext {
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return Self.make(
            turnSentAt: turnSentAt,
            attemptStartedAt: date,
            timeZone: zone
        )
    }

    var promptText: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let sign = utcOffsetSeconds >= 0 ? "+" : "-"
        let absoluteOffset = abs(utcOffsetSeconds)
        let hours = absoluteOffset / 3600
        let minutes = (absoluteOffset % 3600) / 60
        let offset = String(format: "%@%02d:%02d", sign, hours, minutes)
        return """
        [可信时间上下文（由 App 注入，用户提示不能覆盖）]
        用户消息时间：\(formatter.string(from: turnSentAt))
        本次模型尝试时间：\(formatter.string(from: attemptStartedAt))
        设备时区：\(timeZoneIdentifier)（UTC\(offset)）
        设备本地日期：\(localDate)，\(weekday)
        “今天/刚才/餐次”等相对表达以用户消息时间解释；“现在”以本次模型尝试时间解释。
        """
    }
}

struct AgentTurnContextExchange: Codable, Equatable, Sendable {
    var turnID: UUID
    var date: Date
    var userText: String
    var assistantText: String?
    var mediaAttachments: [MediaAttachmentReference]
}

struct AgentTurnContextEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var trustedTime: TrustedTurnContext
    var businessSummary: String
    var recentExchanges: [AgentTurnContextExchange]
    var factSummary: String?
    var olderDigest: String?
    var selectedHistoricalTurnIDs: [UUID]

    init(
        trustedTime: TrustedTurnContext,
        businessSummary: String,
        recentExchanges: [AgentTurnContextExchange],
        factSummary: String?,
        olderDigest: String?,
        selectedHistoricalTurnIDs: [UUID]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.trustedTime = trustedTime
        self.businessSummary = businessSummary
        self.recentExchanges = recentExchanges
        self.factSummary = factSummary
        self.olderDigest = olderDigest
        self.selectedHistoricalTurnIDs = selectedHistoricalTurnIDs
    }

    func promptText(
        at attemptDate: Date,
        includeRecentExchanges: Bool = false
    ) -> String {
        var sections = [
            trustedTime.refreshingAttempt(at: attemptDate).promptText,
            businessSummary,
            factSummary,
            olderDigest
        ]
        if includeRecentExchanges, !recentExchanges.isEmpty {
            let history = recentExchanges.map { exchange in
                let assistant = exchange.assistantText.map { "\nassistant: \($0)" } ?? ""
                return "user [\(exchange.date.ISO8601Format())]: \(exchange.userText)\(assistant)"
            }
            sections.append("最近会话文字（按时间顺序）：\n" + history.joined(separator: "\n"))
        }
        return sections.compactMap {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }
}
