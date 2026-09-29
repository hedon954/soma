@testable import Soma
import XCTest

final class CoachTimelineTests: XCTestCase {
    func testOrdersMessagesAndExternalRecordsByOccurrence() {
        let morning = Date(timeIntervalSince1970: 1000)
        let noon = Date(timeIntervalSince1970: 2000)
        let evening = Date(timeIntervalSince1970: 3000)
        let message = UUID()
        let items = CoachTimelineBuilder.build(
            messages: [
                CoachTimelineMessage(id: message, date: evening)
            ],
            records: [
                record(id: 2, type: "meal", at: noon),
                record(id: 1, type: "body", at: morning)
            ],
            hasEarlierMessages: false
        )
        XCTAssertEqual(items.map(\.id), [
            "body:1",
            "meal:2",
            "message:\(message.uuidString)"
        ])
    }

    func testChatSourcedRecordsStayInsideTheirMessage() {
        let turn = UUID()
        let items = CoachTimelineBuilder.build(
            messages: [CoachTimelineMessage(id: UUID(), date: .distantPast)],
            records: [
                record(id: 9, type: "workout", at: .distantFuture, sourceTurnID: turn)
            ],
            hasEarlierMessages: false
        )
        XCTAssertEqual(items.count, 1)
        guard case .message = items[0].payload else {
            return XCTFail("expected the message only")
        }
    }

    func testGuidedSessionCollapsesToOneEvent() {
        let session = UUID()
        let early = Date(timeIntervalSince1970: 10)
        let later = Date(timeIntervalSince1970: 20)
        let items = CoachTimelineBuilder.build(
            messages: [],
            records: [
                record(id: 2, type: "workout", at: later, sessionID: session),
                record(id: 1, type: "workout", at: early, sessionID: session)
            ],
            hasEarlierMessages: false
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "workout-session:\(session.uuidString)")
        XCTAssertEqual(items[0].occurredAt, early)
        XCTAssertEqual(items[0].scrollID, session)
        guard case let .records(references) = items[0].payload else {
            return XCTFail("expected record cards")
        }
        XCTAssertEqual(references.map(\.recordID), [1, 2])
    }

    func testEarlierPageHidesRecordsBeforeTheLoadedWindow() {
        let oldest = Date(timeIntervalSince1970: 500)
        let items = CoachTimelineBuilder.build(
            messages: [CoachTimelineMessage(id: UUID(), date: oldest)],
            records: [
                record(id: 1, type: "meal", at: Date(timeIntervalSince1970: 100)),
                record(id: 2, type: "meal", at: Date(timeIntervalSince1970: 800))
            ],
            hasEarlierMessages: true
        )
        XCTAssertEqual(items.compactMap(recordIDs).flatMap { $0 }, [2])
    }

    private func recordIDs(_ item: CoachTimelineItem) -> [Int64]? {
        guard case let .records(references) = item.payload else { return nil }
        return references.map(\.recordID)
    }

    private func record(
        id: Int64,
        type: String,
        at date: Date,
        sourceTurnID: UUID? = nil,
        sessionID: UUID? = nil
    ) -> CoachTimelineRecord {
        CoachTimelineRecord(
            businessID: id,
            recordType: type,
            occurredAt: date,
            sourceTurnID: sourceTurnID,
            sourceWorkoutSessionID: sessionID
        )
    }
}
