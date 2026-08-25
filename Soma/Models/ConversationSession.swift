import Foundation
import Observation
import SwiftData

enum ConversationTitleSource: String, Codable, Equatable, Sendable {
    case fallback
    case generated
    case manual
}

@Model
final class ConversationSession {
    var id: UUID
    var startedAt: Date
    var updatedAt: Date
    var title: String
    /// 旧库缺字段时按 fallback 解释；manual 永远不被异步生成结果覆盖。
    var titleSourceRaw: String?
    /// 用户在这个 Session 内默认操作的业务日期；旧库由启动迁移按 startedAt 回填。
    var businessDate: Date?
    /// 业务日期对应的 IANA 时区。不能用重试时的当前时区覆盖。
    var businessTimeZoneIdentifier: String?

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        updatedAt: Date? = nil,
        title: String = "新对话",
        titleSource: ConversationTitleSource? = nil,
        businessDate: Date? = nil,
        businessTimeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.startedAt = startedAt
        self.updatedAt = updatedAt ?? startedAt
        self.title = title
        titleSourceRaw = (titleSource ?? .fallback).rawValue
        let zone = TimeZone(identifier: businessTimeZoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        self.businessDate = businessDate ?? calendar.startOfDay(for: startedAt)
        self.businessTimeZoneIdentifier = zone.identifier
    }

    var effectiveBusinessDate: Date {
        businessDate ?? startedAt
    }

    var titleSource: ConversationTitleSource {
        get { ConversationTitleSource(rawValue: titleSourceRaw ?? "") ?? .fallback }
        set { titleSourceRaw = newValue.rawValue }
    }

    var canGenerateTitle: Bool {
        titleSource == .fallback
    }

    var businessTimeZone: TimeZone {
        businessTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    func setBusinessDate(_ date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        businessDate = calendar.startOfDay(for: date)
        businessTimeZoneIdentifier = timeZone.identifier
        touch(at: .now)
    }

    func recordUserMessage(_ text: String, at date: Date) {
        if titleSource == .fallback, title == Self.defaultTitle {
            title = Self.fallbackTitle(from: text)
        }
        updatedAt = max(updatedAt, date)
    }

    @discardableResult
    func setManualTitle(_ value: String) -> Bool {
        guard let normalized = Self.normalizedTitle(
            value,
            maximumLength: Self.maximumManualTitleLength
        ) else {
            return false
        }
        title = normalized
        titleSource = .manual
        return true
    }

    func restoreAutomaticTitle(from text: String?) {
        title = text.map(Self.fallbackTitle(from:)) ?? Self.defaultTitle
        titleSource = .fallback
    }

    @discardableResult
    func applyGeneratedTitle(_ value: String) -> Bool {
        guard canGenerateTitle,
              let normalized = Self.normalizedTitle(
                  value,
                  maximumLength: Self.maximumGeneratedTitleLength
              )
        else {
            return false
        }
        title = normalized
        titleSource = .generated
        return true
    }

    func touch(at date: Date) {
        updatedAt = max(updatedAt, date)
    }

    static let defaultTitle = "新对话"
    static let maximumGeneratedTitleLength = 28
    static let maximumManualTitleLength = 40

    static func fallbackTitle(from text: String) -> String {
        guard let normalized = normalizedTitle(
            text,
            maximumLength: maximumGeneratedTitleLength
        ) else {
            return "媒体对话"
        }
        return normalized
    }

    static func normalizedTitle(
        _ value: String,
        maximumLength: Int
    ) -> String? {
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(maximumLength))
    }
}

@MainActor
enum ConversationSessionStore {
    static func resolveForEntry(
        messages: [CoachMessage],
        sessions: [ConversationSession],
        preferredSessionID: UUID? = nil,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) -> ConversationSession {
        var availableSessions = sessions
        migrateLegacyMessages(
            messages,
            sessions: &availableSessions,
            calendar: calendar,
            in: context
        )

        let latestUserMessage = messages
            .filter { !$0.isFromCoach }
            .max { $0.date < $1.date }
        if let latestUserMessage,
           calendar.isDate(latestUserMessage.date, inSameDayAs: now),
           let sessionID = latestUserMessage.sessionID
        {
            if let existing = availableSessions.first(where: { $0.id == sessionID }) {
                try? context.save()
                return existing
            }

            let relatedMessages = messages.filter { $0.sessionID == sessionID }
            let recovered = makeSession(
                id: sessionID,
                messages: relatedMessages,
                fallbackDate: latestUserMessage.date
            )
            context.insert(recovered)
            try? context.save()
            return recovered
        }

        let sessionIDsWithMessages = Set(messages.compactMap(\.sessionID))
        let emptyToday = availableSessions.filter {
            calendar.isDate($0.startedAt, inSameDayAs: now)
                && !sessionIDsWithMessages.contains($0.id)
        }
        if !emptyToday.isEmpty {
            let reusableEmpty = preferredSessionID.flatMap { preferredID in
                emptyToday.first { $0.id == preferredID }
            } ?? emptyToday.min { $0.startedAt < $1.startedAt }!
            for duplicate in emptyToday where duplicate.id != reusableEmpty.id {
                context.delete(duplicate)
            }
            try? context.save()
            return reusableEmpty
        }

        let session = ConversationSession(startedAt: now)
        context.insert(session)
        try? context.save()
        return session
    }

    private static func migrateLegacyMessages(
        _ messages: [CoachMessage],
        sessions: inout [ConversationSession],
        calendar: Calendar,
        in context: ModelContext
    ) {
        let legacyMessages = messages.filter { $0.sessionID == nil }
        guard !legacyMessages.isEmpty else { return }

        let grouped = Dictionary(grouping: legacyMessages) {
            calendar.startOfDay(for: $0.date)
        }

        for day in grouped.keys.sorted() {
            guard let dayMessages = grouped[day]?.sorted(by: { $0.date < $1.date }) else {
                continue
            }
            let session: ConversationSession
            if let existing = sessions
                .filter({ calendar.isDate($0.startedAt, inSameDayAs: day) })
                .min(by: { $0.startedAt < $1.startedAt })
            {
                session = existing
            } else {
                session = makeSession(
                    messages: dayMessages,
                    fallbackDate: day
                )
                context.insert(session)
                sessions.append(session)
            }

            for message in dayMessages {
                message.sessionID = session.id
            }
            update(session, from: dayMessages)
        }
    }

    private static func makeSession(
        id: UUID = UUID(),
        messages: [CoachMessage],
        fallbackDate: Date
    ) -> ConversationSession {
        let sorted = messages.sorted { $0.date < $1.date }
        let startedAt = sorted.first?.date ?? fallbackDate
        let updatedAt = sorted.last?.date ?? fallbackDate
        let session = ConversationSession(
            id: id,
            startedAt: startedAt,
            updatedAt: updatedAt
        )
        update(session, from: sorted)
        return session
    }

    private static func update(
        _ session: ConversationSession,
        from messages: [CoachMessage]
    ) {
        guard !messages.isEmpty else { return }
        if let firstUserMessage = messages.first(where: { !$0.isFromCoach }) {
            session.recordUserMessage(
                displayText(for: firstUserMessage),
                at: firstUserMessage.date
            )
        }
        if let lastDate = messages.map(\.date).max() {
            session.touch(at: lastDate)
        }
    }

    private static func displayText(for message: CoachMessage) -> String {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty else { return text }

        let imageCount = message.mediaAttachments.count { $0.kind == .image }
        let videoCount = message.mediaAttachments.count { $0.kind == .video }
        let parts = [
            imageCount > 0 ? "\(imageCount) 张图片" : nil,
            videoCount > 0 ? "\(videoCount) 个视频" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "媒体对话" : parts.joined(separator: "和")
    }
}

@MainActor
@Observable
final class ConversationSessionController {
    @ObservationIgnored
    private let defaults: UserDefaults

    private(set) var activeSessionID: UUID?
    private(set) var dataSpace: DataSpace?
    private(set) var hasManualSessionOverride = false
    private(set) var activeSessionReference: ConversationSession?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    @discardableResult
    func resolveForEntry(
        dataSpace: DataSpace,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) -> ConversationSession {
        if self.dataSpace == dataSpace,
           !hasManualSessionOverride,
           let activeSessionReference,
           calendar.isDate(activeSessionReference.startedAt, inSameDayAs: now)
        {
            return activeSessionReference
        }
        hasManualSessionOverride = false

        var latestMessageDescriptor = FetchDescriptor<CoachMessage>(
            predicate: #Predicate {
                !$0.isFromCoach && $0.sessionID != nil
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        latestMessageDescriptor.fetchLimit = 1
        if let latest = try? context.fetch(latestMessageDescriptor).first,
           calendar.isDate(latest.date, inSameDayAs: now),
           let sessionID = latest.sessionID,
           let existing = session(id: sessionID, in: context)
        {
            activate(existing, dataSpace: dataSpace)
            return existing
        }

        let dayStart = calendar.startOfDay(for: now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? now.addingTimeInterval(86400)
        var todayDescriptor = FetchDescriptor<ConversationSession>(
            predicate: #Predicate {
                $0.startedAt >= dayStart && $0.startedAt < nextDay
            },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        todayDescriptor.fetchLimit = 100
        let todaySessions = (try? context.fetch(todayDescriptor)) ?? []
        let emptySessions = todaySessions.filter { candidate in
            let candidateID = candidate.id
            var messageDescriptor = FetchDescriptor<CoachMessage>(
                predicate: #Predicate { $0.sessionID == candidateID }
            )
            messageDescriptor.fetchLimit = 1
            return (try? context.fetch(messageDescriptor).isEmpty) != false
        }

        let preferredID = storedSessionID(for: dataSpace)
        if let reusable = preferredID.flatMap({ preferredID in
            emptySessions.first { $0.id == preferredID }
        }) ?? emptySessions.first {
            for duplicate in emptySessions where duplicate.id != reusable.id {
                context.delete(duplicate)
            }
            try? context.save()
            activate(reusable, dataSpace: dataSpace)
            return reusable
        }

        let session = ConversationSession(startedAt: now)
        context.insert(session)
        try? context.save()
        activate(session, dataSpace: dataSpace)
        return session
    }

    private func session(
        id: UUID,
        in context: ModelContext
    ) -> ConversationSession? {
        var descriptor = FetchDescriptor<ConversationSession>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func activeSession(in context: ModelContext) -> ConversationSession? {
        guard let activeSessionID else { return nil }
        if activeSessionReference?.id == activeSessionID {
            return activeSessionReference
        }
        var descriptor = FetchDescriptor<ConversationSession>(
            predicate: #Predicate { session in
                session.id == activeSessionID
            }
        )
        descriptor.fetchLimit = 1
        activeSessionReference = try? context.fetch(descriptor).first
        return activeSessionReference
    }

    @discardableResult
    func ensureActiveSession(
        dataSpace: DataSpace,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) -> ConversationSession {
        if self.dataSpace == dataSpace,
           hasManualSessionOverride,
           let activeSession = activeSession(in: context)
        {
            return activeSession
        }
        return resolveForEntry(
            dataSpace: dataSpace,
            now: now,
            calendar: calendar,
            in: context
        )
    }

    @discardableResult
    func createSession(
        dataSpace: DataSpace,
        in context: ModelContext
    ) -> ConversationSession {
        if self.dataSpace == dataSpace,
           let active = activeSession(in: context)
        {
            let activeID = active.id
            var messageDescriptor = FetchDescriptor<CoachMessage>(
                predicate: #Predicate { message in
                    message.sessionID == activeID
                }
            )
            messageDescriptor.fetchLimit = 1
            if (try? context.fetch(messageDescriptor).isEmpty) == true {
                return active
            }
        }

        let session = ConversationSession()
        context.insert(session)
        try? context.save()
        activate(session, dataSpace: dataSpace)
        hasManualSessionOverride = true
        return session
    }

    func select(
        _ session: ConversationSession,
        dataSpace: DataSpace
    ) {
        activate(session, dataSpace: dataSpace)
        hasManualSessionOverride = true
    }

    func activateFallbackAfterDeletion(
        dataSpace: DataSpace,
        in context: ModelContext
    ) {
        activeSessionID = nil
        activeSessionReference = nil
        self.dataSpace = dataSpace
        defaults.removeObject(forKey: Self.activeSessionDefaultsKey(for: dataSpace))

        var descriptor = FetchDescriptor<ConversationSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let remaining = (try? context.fetch(descriptor)) ?? []
        if let newest = remaining.first {
            activate(newest, dataSpace: dataSpace)
            hasManualSessionOverride = true
            return
        }
        _ = createSession(dataSpace: dataSpace, in: context)
    }

    private func activate(
        _ session: ConversationSession,
        dataSpace: DataSpace
    ) {
        activeSessionID = session.id
        activeSessionReference = session
        self.dataSpace = dataSpace
        defaults.set(
            session.id.uuidString,
            forKey: Self.activeSessionDefaultsKey(for: dataSpace)
        )
    }

    private func storedSessionID(for dataSpace: DataSpace) -> UUID? {
        defaults.string(
            forKey: Self.activeSessionDefaultsKey(for: dataSpace)
        ).flatMap(UUID.init(uuidString:))
    }

    private static func activeSessionDefaultsKey(for dataSpace: DataSpace) -> String {
        "conversation.activeSessionID.\(dataSpace.rawValue)"
    }
}
