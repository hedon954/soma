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

    func testTailScrollOnlyRunsAfterOverflowIsMeasured() {
        XCTAssertFalse(CoachTailScrollPolicy.shouldScroll(contentFitsViewport: nil))
        XCTAssertFalse(CoachTailScrollPolicy.shouldScroll(contentFitsViewport: true))
        XCTAssertTrue(CoachTailScrollPolicy.shouldScroll(contentFitsViewport: false))
    }

    func testLiveTailFollowStopsAfterUserInteractionUntilExplicitlyResumed() {
        var state = CoachTailFollowState()

        XCTAssertTrue(state.isFollowing)

        state.userDidInteract()
        XCTAssertFalse(state.isFollowing)

        // 流式内容增长不写 follow state，也不能覆盖用户的阅读选择。
        XCTAssertFalse(state.isFollowing)

        state.resumeExplicitly()
        XCTAssertTrue(state.isFollowing)
    }

    @MainActor
    func testTailCoordinatorKeepsOnlyLatestPendingAppend() {
        let coordinator = CoachTailScrollCoordinator()
        let first = UUID()
        let second = UUID()

        coordinator.enqueueMessage(first)
        coordinator.enqueueMessage(second)

        XCTAssertEqual(coordinator.consumePendingMessageID(), second)
        XCTAssertNil(coordinator.consumePendingMessageID())
    }

    @MainActor
    func testTailCoordinatorCancelsOlderGeneration() throws {
        let coordinator = CoachTailScrollCoordinator()
        let first = try XCTUnwrap(
            coordinator.startRequest(replacingExisting: false)
        )
        let second = try XCTUnwrap(
            coordinator.startRequest(replacingExisting: true)
        )

        XCTAssertFalse(coordinator.owns(first))
        XCTAssertTrue(coordinator.owns(second))
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

    @MainActor
    func testMemoryPressureRetentionKeepsRecentDTOsAcrossSessions() {
        CoachMessageRenderPayloadCache.removeAll()
        defer { CoachMessageRenderPayloadCache.removeAll() }
        let currentSessionID = UUID()
        for index in 0 ..< 12 {
            _ = CoachMessageRenderPayloadCache.payload(for: CoachMessage(
                sessionID: currentSessionID,
                isFromCoach: true,
                text: "当前 \(index)"
            ))
        }
        _ = CoachMessageRenderPayloadCache.payload(for: CoachMessage(
            sessionID: UUID(),
            isFromCoach: true,
            text: "其他会话"
        ))

        CoachMessageRenderPayloadCache.retainCurrentSession(
            currentSessionID,
            maxCount: 8
        )

        XCTAssertEqual(CoachMessageRenderPayloadCache.cachedCount, 8)
    }

    @MainActor
    func testMemoryPressureRetentionHonorsCostLimit() {
        CoachMessageRenderPayloadCache.removeAll()
        defer { CoachMessageRenderPayloadCache.removeAll() }
        let sessionID = UUID()
        _ = CoachMessageRenderPayloadCache.payload(for: CoachMessage(
            sessionID: sessionID,
            isFromCoach: true,
            text: String(repeating: "很", count: 64)
        ))

        CoachMessageRenderPayloadCache.retainCurrentSession(
            sessionID,
            maxCount: 10,
            maxCost: 1
        )

        XCTAssertEqual(CoachMessageRenderPayloadCache.cachedCount, 0)
    }
}
