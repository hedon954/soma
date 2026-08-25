@testable import Soma
import SwiftData
import XCTest

final class ConversationSessionFromSomaTests: XCTestCase {
    @MainActor
    func testConversationSessionCreatesTodayAfterLatestConversationIsOlder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 9))
        )
        let yesterday = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -1, to: today)
        )
        let container = try ModelContainer(
            for: ConversationSession.self,
            CoachMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let legacyMessage = CoachMessage(
            date: yesterday,
            isFromCoach: false,
            text: "昨天的深蹲记录"
        )
        context.insert(legacyMessage)
        try context.save()

        let current = ConversationSessionStore.resolveForEntry(
            messages: [legacyMessage],
            sessions: [],
            now: today,
            calendar: calendar,
            in: context
        )

        XCTAssertNotNil(legacyMessage.sessionID)
        XCTAssertNotEqual(legacyMessage.sessionID, current.id)
        XCTAssertTrue(calendar.isDate(current.startedAt, inSameDayAs: today))
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationSession>()).count,
            2
        )

        let resolvedAgain = try ConversationSessionStore.resolveForEntry(
            messages: [legacyMessage],
            sessions: context.fetch(FetchDescriptor<ConversationSession>()),
            now: today,
            calendar: calendar,
            in: context
        )

        XCTAssertEqual(resolvedAgain.id, current.id)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationSession>()).count,
            2
        )
    }

    @MainActor
    func testConversationSessionUsesTodaysLatestMessageInsteadOfOldPreference() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 9))
        )
        let container = try ModelContainer(
            for: ConversationSession.self,
            CoachMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let preferred = ConversationSession(
            startedAt: today.addingTimeInterval(-86400)
        )
        let latest = ConversationSession(startedAt: today)
        let message = CoachMessage(
            date: today,
            sessionID: latest.id,
            isFromCoach: false,
            text: "今天继续训练"
        )
        context.insert(preferred)
        context.insert(latest)
        context.insert(message)
        try context.save()

        let resolved = ConversationSessionStore.resolveForEntry(
            messages: [message],
            sessions: [preferred, latest],
            preferredSessionID: preferred.id,
            now: today.addingTimeInterval(3600),
            calendar: calendar,
            in: context
        )

        XCTAssertEqual(resolved.id, latest.id)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationSession>()).count,
            2
        )
    }

    @MainActor
    func testConversationSessionControllerReusesEmptyAndPersistsNewSession() throws {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let container = try ModelContainer(
            for: ConversationSession.self,
            CoachMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let controller = ConversationSessionController(defaults: defaults)

        let initial = controller.resolveForEntry(
            dataSpace: .personal,
            in: context
        )
        XCTAssertEqual(
            controller.createSession(dataSpace: .personal, in: context).id,
            initial.id
        )

        context.insert(CoachMessage(
            sessionID: initial.id,
            isFromCoach: false,
            text: "第一段对话",
            turnID: UUID()
        ))
        try context.save()
        let created = controller.createSession(
            dataSpace: .personal,
            in: context
        )
        XCTAssertNotEqual(created.id, initial.id)

        let restoredController = ConversationSessionController(defaults: defaults)
        let restored = restoredController.resolveForEntry(
            dataSpace: .personal,
            in: context
        )
        XCTAssertEqual(restored.id, initial.id)
        XCTAssertNotEqual(restored.id, created.id)
    }
}

