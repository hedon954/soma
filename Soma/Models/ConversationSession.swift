import Foundation
import Observation
import SwiftData

@Model
final class ConversationSession {
    var id: UUID
    var startedAt: Date
    var updatedAt: Date
    var title: String

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        updatedAt: Date? = nil,
        title: String = "新对话"
    ) {
        self.id = id
        self.startedAt = startedAt
        self.updatedAt = updatedAt ?? startedAt
        self.title = title
    }

    func recordUserMessage(_ text: String, at date: Date) {
        if title == "新对话" {
            title = Self.title(from: text)
        }
        updatedAt = max(updatedAt, date)
    }

    func touch(at date: Date) {
        updatedAt = max(updatedAt, date)
    }

    private static func title(from text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return "媒体对话" }
        return String(normalized.prefix(28))
    }
}

@MainActor
enum ConversationSessionStore {
    static func resolveForEntry(
        messages: [CoachMessage],
        sessions: [ConversationSession],
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

        let startOfToday = calendar.startOfDay(for: now)
        let latestMessage = messages.max { $0.date < $1.date }

        if let latestMessage,
           latestMessage.date >= startOfToday,
           let sessionID = latestMessage.sessionID
        {
            if let existing = availableSessions.first(where: { $0.id == sessionID }) {
                try? context.save()
                return existing
            }

            let relatedMessages = messages.filter { $0.sessionID == sessionID }
            let recovered = makeSession(
                id: sessionID,
                messages: relatedMessages,
                fallbackDate: latestMessage.date
            )
            context.insert(recovered)
            try? context.save()
            return recovered
        }

        let sessionsStartedToday = availableSessions.filter { session in
            calendar.isDate(session.startedAt, inSameDayAs: now)
        }
        if let existingToday = sessionsStartedToday.max(by: {
            $0.updatedAt < $1.updatedAt
        }) {
            try? context.save()
            return existingToday
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
    private(set) var activeSessionID: UUID?
    private(set) var dataSpace: DataSpace?

    @discardableResult
    func resolveForEntry(
        dataSpace: DataSpace,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) -> ConversationSession {
        let messages = (
            try? context.fetch(
                FetchDescriptor<CoachMessage>(
                    sortBy: [SortDescriptor(\.date)]
                )
            )
        ) ?? []
        let sessions = (
            try? context.fetch(
                FetchDescriptor<ConversationSession>(
                    sortBy: [SortDescriptor(\.startedAt)]
                )
            )
        ) ?? []
        let session = ConversationSessionStore.resolveForEntry(
            messages: messages,
            sessions: sessions,
            now: now,
            calendar: calendar,
            in: context
        )
        activeSessionID = session.id
        self.dataSpace = dataSpace
        return session
    }

    func activeSession(in context: ModelContext) -> ConversationSession? {
        guard let activeSessionID else { return nil }
        let sessions = (
            try? context.fetch(FetchDescriptor<ConversationSession>())
        ) ?? []
        return sessions.first { $0.id == activeSessionID }
    }

    @discardableResult
    func ensureActiveSession(
        dataSpace: DataSpace,
        in context: ModelContext
    ) -> ConversationSession {
        if self.dataSpace == dataSpace,
           let activeSession = activeSession(in: context)
        {
            return activeSession
        }
        return resolveForEntry(dataSpace: dataSpace, in: context)
    }
}
