@testable import Soma
import XCTest

final class CoachMessageAutoScrollGateTests: XCTestCase {
    func testUnchangedLastMessageDoesNotScrollAgainAfterTabReentry() {
        var gate = CoachMessageAutoScrollGate()
        let messageID = UUID()

        XCTAssertTrue(gate.shouldScroll(to: messageID))
        XCTAssertFalse(gate.shouldScroll(to: messageID))
        XCTAssertEqual(gate.lastMessageID, messageID)
    }

    func testNewMessageRequestsOneNewScroll() {
        var gate = CoachMessageAutoScrollGate()
        let first = UUID()
        let second = UUID()

        XCTAssertTrue(gate.shouldScroll(to: first))
        XCTAssertTrue(gate.shouldScroll(to: second))
        XCTAssertFalse(gate.shouldScroll(to: second))
    }

    func testEmptyConversationDoesNotRequestScroll() {
        var gate = CoachMessageAutoScrollGate()

        XCTAssertFalse(gate.shouldScroll(to: nil))
        XCTAssertNil(gate.lastMessageID)
    }

    func testInitialPageUsesLazyStackForCompoundMessageRows() {
        XCTAssertFalse(CoachMessageStackPolicy.usesLazyStack(messageCount: 9))
        XCTAssertTrue(CoachMessageStackPolicy.usesLazyStack(messageCount: 10))
    }

    func testMessagePaginationStartsAtTenAndAdvancesByTen() {
        XCTAssertEqual(CoachMessagePagePolicy.pageSize, 10)
        XCTAssertEqual(CoachMessagePagePolicy.nextLimit(after: 10), 20)
        XCTAssertEqual(CoachMessagePagePolicy.nextLimit(after: 20), 30)
    }

    @MainActor
    func testRenderPayloadCacheInvalidatesWhenTurnItemsChange() {
        CoachMessageRenderPayloadCache.removeAll()
        defer { CoachMessageRenderPayloadCache.removeAll() }
        let message = CoachMessage(isFromCoach: true, text: "完成")
        XCTAssertTrue(
            CoachMessageRenderPayloadCache.payload(for: message).turnItems.isEmpty
        )

        message.replaceAgentTurnItems([
            AgentTurnItem(
                kind: .text,
                status: .succeeded,
                text: "新的完成内容"
            )
        ])

        let payload = CoachMessageRenderPayloadCache.payload(for: message)
        XCTAssertEqual(payload.turnItems.map(\.text), ["新的完成内容"])
        XCTAssertEqual(payload.transcriptSegments.count, 1)
    }

    @MainActor
    func testRenderPayloadCacheOnlyContainsMessagesActuallyRequestedByVisibleBubbles() {
        CoachMessageRenderPayloadCache.removeAll()
        defer { CoachMessageRenderPayloadCache.removeAll() }
        let viewed = CoachMessage(isFromCoach: true, text: "已查看")
        _ = CoachMessage(isFromCoach: true, text: "未查看")

        XCTAssertEqual(CoachMessageRenderPayloadCache.cachedCount, 0)
        _ = CoachMessageRenderPayloadCache.payload(for: viewed)
        XCTAssertEqual(CoachMessageRenderPayloadCache.cachedCount, 1)
    }
}
