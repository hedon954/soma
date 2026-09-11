@testable import Soma
import SwiftData
import XCTest

@MainActor
final class ConversationSessionHistoryTests: XCTestCase {
    func testPagesFetchOnlyUncachedSessionsAndReopeningDoesNotFetch() throws {
        let context = try makeContext()
        for index in 0 ..< 35 {
            context.insert(ConversationSession(startedAt: Date(timeIntervalSince1970: Double(index / 3))))
        }
        try context.save()
        let history = ConversationSessionHistory()
        history.loadIfNeeded(in: context)
        XCTAssertEqual(history.sessions.count, 14)
        XCTAssertEqual(history.pageFetchCount, 1)
        history.loadIfNeeded(in: context)
        XCTAssertEqual(history.pageFetchCount, 1)
        history.loadNextPage(in: context)
        XCTAssertEqual(history.sessions.count, 28)
        history.loadNextPage(in: context)
        XCTAssertEqual(history.sessions.count, 35)
        XCTAssertEqual(Set(history.sessions.map(\.id)).count, 35)
        XCTAssertFalse(history.hasMore)
        XCTAssertEqual(history.sessions.map(\.updatedAt), history.sessions.map(\.updatedAt).sorted(by: >))
        history.loadNextPage(in: context)
        XCTAssertEqual(history.pageFetchCount, 3)
    }

    func testSavedChangesMergeWithoutRefetchAndDoNotSkipNextPage() throws {
        let context = try makeContext()
        let fixtures = (0 ..< 30).map { ConversationSession(startedAt: Date(timeIntervalSince1970: Double($0))) }
        fixtures.forEach(context.insert)
        try context.save()
        let history = ConversationSessionHistory()
        history.loadIfNeeded(in: context)
        let deleted = try XCTUnwrap(history.sessions.last)
        let deletedID = deleted.persistentModelID
        context.delete(deleted)
        let inserted = ConversationSession(startedAt: Date(timeIntervalSince1970: 100))
        context.insert(inserted)
        fixtures[29].title = "虚构改名"
        fixtures[29].touch(at: Date(timeIntervalSince1970: 200))
        try context.save()
        history.applySave(Notification(name: ModelContext.didSave, object: context, userInfo: [
            ModelContext.NotificationKey.deletedIdentifiers.rawValue: [deletedID],
            ModelContext.NotificationKey.insertedIdentifiers.rawValue: [inserted.persistentModelID],
            ModelContext.NotificationKey.updatedIdentifiers.rawValue: [fixtures[29].persistentModelID]
        ]), in: context)
        XCTAssertEqual(history.pageFetchCount, 1)
        XCTAssertEqual(history.sessions.first?.title, "虚构改名")
        XCTAssertTrue(history.sessions.contains { $0.id == inserted.id })
        history.loadNextPage(in: context)
        history.loadNextPage(in: context)
        XCTAssertEqual(history.sessions.count, 30)
        XCTAssertEqual(Set(history.sessions.map(\.id)), try Set(context.fetch(FetchDescriptor<ConversationSession>()).map(\.id)))
    }

    func testDifferentContextClearsCachedSpaceAndEmptyPageDoesNotReload() throws {
        let first = try makeContext()
        first.insert(ConversationSession(title: "虚构个人会话"))
        try first.save()
        let history = ConversationSessionHistory()
        history.loadIfNeeded(in: first)
        let second = try makeContext()
        history.loadIfNeeded(in: second)
        XCTAssertTrue(history.sessions.isEmpty)
        XCTAssertFalse(history.hasMore)
        history.loadIfNeeded(in: second)
        XCTAssertEqual(history.pageFetchCount, 1)
    }

    func testFetchFailurePreservesPageAndRetryOnlyRequestsUncachedIDs() throws {
        let context = try makeContext()
        for index in 0 ..< 16 {
            context.insert(ConversationSession(startedAt: Date(timeIntervalSince1970: Double(index))))
        }
        try context.save()
        var shouldFail = false
        let history = ConversationSessionHistory { context, descriptor in
            XCTAssertEqual(descriptor.fetchLimit, 14)
            if shouldFail {
                throw CocoaError(.fileReadUnknown)
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

    func testActualSaveNotificationUpdatesLoadedHistory() throws {
        let container = try makeContext().container
        let context = container.mainContext
        let history = ConversationSessionHistory()
        history.loadIfNeeded(in: context)
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: .main) { notification in
            MainActor.assumeIsolated { history.applySave(notification, in: container.mainContext) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let session = ConversationSession(title: "虚构新会话")
        context.insert(session)
        try context.save()
        XCTAssertEqual(history.sessions.map(\.id), [session.id])
        context.delete(session)
        try context.save()
        XCTAssertTrue(history.sessions.isEmpty)
        XCTAssertEqual(history.pageFetchCount, 1)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: ConversationSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
}
