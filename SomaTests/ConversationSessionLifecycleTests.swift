@testable import Soma
import SwiftData
import XCTest

final class ConversationSessionLifecycleTests: XCTestCase {
    @MainActor
    func testCrossDayEntryCreatesOnceAndReusesUniqueEmptySession() throws {
        let (calendar, today, yesterday) = try dates()
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let old = ConversationSession(startedAt: yesterday)
        context.insert(old)
        context.insert(CoachMessage(
            date: yesterday,
            sessionID: old.id,
            isFromCoach: false,
            text: "昨天的对话"
        ))
        try context.save()

        let controller = ConversationSessionController(defaults: defaults)
        let created = controller.resolveForEntry(
            dataSpace: .personal,
            now: today,
            calendar: calendar,
            in: context
        )
        let reused = controller.resolveForEntry(
            dataSpace: .personal,
            now: today.addingTimeInterval(60),
            calendar: calendar,
            in: context
        )

        XCTAssertNotEqual(created.id, old.id)
        XCTAssertEqual(reused.id, created.id)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationSession>()).count,
            2
        )
    }

    @MainActor
    func testLatestUserMessageFromTodayWinsOverEmptySession() throws {
        let (calendar, today, _) = try dates()
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let used = ConversationSession(startedAt: today.addingTimeInterval(-120))
        let empty = ConversationSession(startedAt: today.addingTimeInterval(-60))
        context.insert(used)
        context.insert(empty)
        context.insert(CoachMessage(
            date: today.addingTimeInterval(-30),
            sessionID: used.id,
            isFromCoach: false,
            text: "今天的消息"
        ))
        try context.save()

        let resolved = ConversationSessionController(defaults: defaults)
            .resolveForEntry(
                dataSpace: .personal,
                now: today,
                calendar: calendar,
                in: context
            )

        XCTAssertEqual(resolved.id, used.id)
    }

    @MainActor
    func testDuplicateEmptySessionsAreConsolidated() throws {
        let (calendar, today, _) = try dates()
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        context.insert(ConversationSession(startedAt: today.addingTimeInterval(-20)))
        context.insert(ConversationSession(startedAt: today.addingTimeInterval(-10)))
        try context.save()

        _ = ConversationSessionController(defaults: defaults).resolveForEntry(
            dataSpace: .personal,
            now: today,
            calendar: calendar,
            in: context
        )

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationSession>()).count,
            1
        )
    }

    @MainActor
    func testPreSendResolutionHandlesMidnightAndKeepsDataSpacesIndependent() throws {
        let (calendar, today, yesterday) = try dates()
        let (personal, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (demo, _, demoSuiteName) = try makeContext(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: demoSuiteName) }
        let controller = ConversationSessionController(defaults: defaults)

        let personalOld = controller.resolveForEntry(
            dataSpace: .personal,
            now: yesterday,
            calendar: calendar,
            in: personal
        )
        personal.insert(CoachMessage(
            date: yesterday,
            sessionID: personalOld.id,
            isFromCoach: false,
            text: "午夜前"
        ))
        try personal.save()
        let personalToday = controller.ensureActiveSession(
            dataSpace: .personal,
            now: today,
            calendar: calendar,
            in: personal
        )
        let demoToday = controller.resolveForEntry(
            dataSpace: .demo,
            now: today,
            calendar: calendar,
            in: demo
        )

        XCTAssertNotEqual(personalToday.id, personalOld.id)
        XCTAssertNotEqual(demoToday.id, personalToday.id)
        XCTAssertEqual(
            try personal.fetch(FetchDescriptor<ConversationSession>()).count,
            2
        )
        XCTAssertEqual(
            try demo.fetch(FetchDescriptor<ConversationSession>()).count,
            1
        )
    }

    @MainActor
    func testManualSelectionSurvivesSubmissionCheckUntilNextEntry() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 9))
        )
        let yesterday = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -1, to: today)
        )
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let container = try ModelContainer(
            for: ConversationSession.self,
            CoachMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let old = ConversationSession(startedAt: yesterday)
        context.insert(old)
        context.insert(CoachMessage(
            date: yesterday,
            sessionID: old.id,
            isFromCoach: false,
            text: "昨天的对话"
        ))
        try context.save()

        let controller = ConversationSessionController(defaults: defaults)
        let todaySession = controller.resolveForEntry(
            dataSpace: .personal,
            now: today,
            calendar: calendar,
            in: context
        )
        controller.select(old, dataSpace: .personal)

        XCTAssertEqual(
            controller.ensureActiveSession(
                dataSpace: .personal,
                now: today,
                calendar: calendar,
                in: context
            ).id,
            old.id
        )
        XCTAssertEqual(
            controller.resolveForEntry(
                dataSpace: .personal,
                now: today,
                calendar: calendar,
                in: context
            ).id,
            todaySession.id
        )
    }

    private func dates() throws -> (Calendar, Date, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 9))
        )
        let yesterday = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -1, to: today)
        )
        return (calendar, today, yesterday)
    }

    @MainActor
    private func makeContext(
        defaults existingDefaults: UserDefaults? = nil
    ) throws -> (ModelContext, UserDefaults, String) {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults: UserDefaults = if let existingDefaults {
            existingDefaults
        } else {
            try XCTUnwrap(UserDefaults(suiteName: suiteName))
        }
        let container = try ModelContainer(
            for: ConversationSession.self,
            CoachMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (ModelContext(container), defaults, suiteName)
    }
}
