import Foundation

struct TrustedTurnContext: Codable, Equatable, Sendable {
    var turnSentAt: Date
    var loopStartedAt: Date
    var timeZoneIdentifier: String
    var effectiveBusinessDate: Date
    var defaultOccurredAt: Date

    private enum CodingKeys: String, CodingKey {
        case turnSentAt
        case loopStartedAt
        case attemptStartedAt
        case timeZoneIdentifier
        case effectiveBusinessDate
        case defaultOccurredAt
    }

    init(
        turnSentAt: Date,
        loopStartedAt: Date,
        timeZoneIdentifier: String,
        effectiveBusinessDate: Date? = nil,
        defaultOccurredAt: Date? = nil
    ) {
        self.turnSentAt = turnSentAt
        self.loopStartedAt = loopStartedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let day = effectiveBusinessDate ?? turnSentAt
        self.effectiveBusinessDate = BusinessDateResolver.startOfDay(day, in: zone)
        self.defaultOccurredAt = defaultOccurredAt
            ?? BusinessDateResolver.defaultOccurredAt(
                turnSentAt: turnSentAt,
                businessDate: day,
                timeZone: zone
            )
    }

    static func make(
        turnSentAt: Date,
        attemptStartedAt: Date,
        businessDate: Date? = nil,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> TrustedTurnContext {
        TrustedTurnContext(
            turnSentAt: turnSentAt,
            loopStartedAt: attemptStartedAt,
            timeZoneIdentifier: timeZone.identifier,
            effectiveBusinessDate: businessDate,
            defaultOccurredAt: businessDate.map {
                BusinessDateResolver.defaultOccurredAt(
                    turnSentAt: turnSentAt,
                    businessDate: $0,
                    timeZone: timeZone
                )
            }
        )
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        turnSentAt = try values.decode(Date.self, forKey: .turnSentAt)
        loopStartedAt = try values.decodeIfPresent(Date.self, forKey: .loopStartedAt)
            ?? values.decodeIfPresent(Date.self, forKey: .attemptStartedAt)
            ?? turnSentAt
        timeZoneIdentifier = try values.decodeIfPresent(
            String.self,
            forKey: .timeZoneIdentifier
        ) ?? TimeZone.current.identifier
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        effectiveBusinessDate = try values.decodeIfPresent(
            Date.self,
            forKey: .effectiveBusinessDate
        ) ?? BusinessDateResolver.startOfDay(turnSentAt, in: zone)
        defaultOccurredAt = try values.decodeIfPresent(
            Date.self,
            forKey: .defaultOccurredAt
        ) ?? BusinessDateResolver.defaultOccurredAt(
            turnSentAt: turnSentAt,
            businessDate: effectiveBusinessDate,
            timeZone: zone
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(turnSentAt, forKey: .turnSentAt)
        try values.encode(loopStartedAt, forKey: .loopStartedAt)
        try values.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try values.encode(effectiveBusinessDate, forKey: .effectiveBusinessDate)
        try values.encode(defaultOccurredAt, forKey: .defaultOccurredAt)
    }

    func freezingLoopStart(at date: Date) -> TrustedTurnContext {
        var copy = self
        copy.loopStartedAt = date
        return copy
    }

    var promptText: String {
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = zone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.timeZone = zone
        weekdayFormatter.dateFormat = "EEEE"
        let localDate = dateFormatter.string(from: loopStartedAt)
        let businessDate = dateFormatter.string(from: effectiveBusinessDate)
        let weekday = weekdayFormatter.string(from: loopStartedAt)
        let utcOffsetSeconds = zone.secondsFromGMT(for: loopStartedAt)
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
        当前真实时间：\(formatter.string(from: loopStartedAt))
        设备时区：\(timeZoneIdentifier)（UTC\(offset)）
        当前本地日期：\(localDate)，\(weekday)
        Session 业务日期：\(businessDate)
        省略 occurred_at 时的稳定记录时间：\(formatter.string(from: defaultOccurredAt))
        自然语言日期只覆盖当前 Turn；只有用户操作日期芯片才会修改 Session 业务日期。
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
    static let currentSchemaVersion = 3

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
        at _: Date,
        includeRecentExchanges: Bool = false
    ) -> String {
        var sections = [
            trustedTime.promptText,
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

    func freezingLoopStart(at date: Date) -> AgentTurnContextEnvelope {
        var copy = self
        copy.trustedTime = trustedTime.freezingLoopStart(at: date)
        return copy
    }
}
