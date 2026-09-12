@testable import Soma
import XCTest

@MainActor
final class AgentContextWindowTests: XCTestCase {
    func testTokenEvictionAndCompactionCoverageShareOneBoundary() throws {
        let session = UUID()
        let turns = (0 ..< 3).map { index in
            CoachMessage(date: Date(timeIntervalSince1970: Double(index)), sessionID: session,
                         isFromCoach: false, text: String(repeating: "中", count: 15000), turnID: UUID())
        }
        let plan = ConversationContextProjection.make(messages: turns, sessionID: session, excludingTurnID: nil)
        XCTAssertEqual(plan.exchanges.map(\.turnID), try [XCTUnwrap(turns[2].turnID)])
        XCTAssertEqual(plan.evictedExchanges.map(\.turnID), turns.prefix(2).map { $0.turnID! })
    }

    func testExactBudgetKeepsWholeLatestTurnAndOversizeIsExplicit() {
        let session = UUID()
        let turn = CoachMessage(sessionID: session, isFromCoach: false,
                                text: String(repeating: "中", count: 29999), turnID: UUID())
        let exact = ConversationContextProjection.make(messages: [turn], sessionID: session, excludingTurnID: nil)
        XCTAssertEqual(exact.estimatedHistoryTokens, 30000)
        XCTAssertTrue(exact.evictedExchanges.isEmpty)
        XCTAssertFalse(exact.isOverBudget)
        turn.text += "中"
        let over = ConversationContextProjection.make(messages: [turn], sessionID: session, excludingTurnID: nil)
        XCTAssertEqual(over.exchanges.count, 1)
        XCTAssertTrue(over.isOverBudget)
    }

    func testQueuedFutureTurnsAreNotContextForCurrentTurn() throws {
        let session = UUID()
        let turns = (0 ..< 3).map { index in
            CoachMessage(date: Date(timeIntervalSince1970: Double(index)), sessionID: session,
                         isFromCoach: false, text: "消息 \(index)", turnID: UUID())
        }
        let plan = ConversationContextProjection.make(messages: turns, sessionID: session,
                                                      excludingTurnID: turns[1].turnID)
        XCTAssertEqual(plan.exchanges.map(\.turnID), try [XCTUnwrap(turns[0].turnID)])
    }
}
