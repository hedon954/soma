@testable import Soma
import SwiftData
import XCTest

@MainActor
final class TrainingSessionHistoryTests: XCTestCase {
    func testPagesEndedSessionsAndSkipsInProgress() throws {
        let context = try makeContext()
        for index in 0 ..< 16 {
            try context.insert(WorkoutSession(
                id: XCTUnwrap(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))),
                startedAt: Date(timeIntervalSince1970: Double(index)),
                status: index == 15 ? .active : .completed
            ))
        }
        try context.save()
        let history = TrainingSessionHistory()
        history.loadIfNeeded(in: context)
        XCTAssertEqual(history.sessions.count, 14)
        XCTAssertTrue(history.hasMore)
        XCTAssertEqual(history.pageFetchCount, 1)
        XCTAssertFalse(history.sessions.contains { $0.status == .active })
        history.loadIfNeeded(in: context)
        XCTAssertEqual(history.pageFetchCount, 1)
        history.loadNextPage(in: context)
        XCTAssertEqual(history.sessions.count, 15)
        XCTAssertFalse(history.hasMore)
        XCTAssertEqual(history.sessions.map(\.startedAt), history.sessions.map(\.startedAt).sorted(by: >))
    }

    func testSameStartOrdersByIdentityDescending() throws {
        let context = try makeContext()
        let startedAt = Date(timeIntervalSince1970: 20)
        let first = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let second = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        context.insert(WorkoutSession(id: first, startedAt: startedAt, status: .completed))
        context.insert(WorkoutSession(id: second, startedAt: startedAt, status: .abandoned))
        try context.save()
        let history = TrainingSessionHistory()
        history.loadIfNeeded(in: context)
        XCTAssertEqual(history.sessions.map(\.id), [second, first])
        XCTAssertFalse(history.hasMore)
    }

    func testNewCompletionStaysAheadWithoutRefetchingThePrefix() throws {
        let context = try makeContext()
        for index in 0 ..< 14 {
            context.insert(WorkoutSession(
                startedAt: Date(timeIntervalSince1970: Double(index)),
                status: .completed
            ))
        }
        try context.save()
        let history = TrainingSessionHistory()
        history.loadIfNeeded(in: context)
        let inserted = WorkoutSession(
            startedAt: Date(timeIntervalSince1970: 100),
            status: .completed
        )
        context.insert(inserted)
        try context.save()
        history.applySave(Notification(
            name: ModelContext.didSave,
            object: context,
            userInfo: [
                ModelContext.NotificationKey.insertedIdentifiers.rawValue: [inserted.persistentModelID]
            ]
        ), in: context)
        XCTAssertEqual(history.pageFetchCount, 1)
        XCTAssertEqual(history.sessions.first?.id, inserted.id)
        history.loadNextPage(in: context)
        XCTAssertEqual(history.sessions.filter { $0.id == inserted.id }.count, 1)
    }

    func testFetchFailureKeepsTheLoadedPage() throws {
        let context = try makeContext()
        for index in 0 ..< 16 {
            context.insert(WorkoutSession(
                startedAt: Date(timeIntervalSince1970: Double(index)),
                status: .completed
            ))
        }
        try context.save()
        var shouldFail = false
        let history = TrainingSessionHistory { context, descriptor in
            if shouldFail {
                throw CocoaError(.fileReadCorruptFile)
            }
            return try context.fetch(descriptor)
        }
        history.loadIfNeeded(in: context)
        let firstPage = history.sessions.map(\.id)
        shouldFail = true
        history.loadNextPage(in: context)
        XCTAssertEqual(history.sessions.map(\.id), firstPage)
        XCTAssertNotNil(history.errorMessage)
        shouldFail = false
        history.loadNextPage(in: context)
        XCTAssertEqual(history.sessions.count, 16)
        XCTAssertNil(history.errorMessage)
    }

    func testAnotherContextStartsEmpty() throws {
        let first = try makeContext()
        first.insert(WorkoutSession(status: .completed))
        try first.save()
        let history = TrainingSessionHistory()
        history.loadIfNeeded(in: first)
        XCTAssertEqual(history.sessions.count, 1)
        let second = try makeContext()
        history.loadIfNeeded(in: second)
        XCTAssertTrue(history.sessions.isEmpty)
        XCTAssertFalse(history.hasMore)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(SomaDataSchema.models)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
