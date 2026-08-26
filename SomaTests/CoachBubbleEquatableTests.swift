@testable import Soma
import SwiftData
import XCTest

/// 气泡以 `.equatable()` 挂载后，父层每次 body 重算是否重排历史消息完全由
/// `CoachBubble.==` 决定。这里固定等价策略：闭包不参与比较，消息对象身份与
/// 渲染 flags 共同决定是否跳过 diff。
final class CoachBubbleEquatableTests: XCTestCase {
    @MainActor
    private func makeMessage(text: String) throws -> CoachMessage {
        let container = try ModelContainer(
            for: CoachMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let message = CoachMessage(isFromCoach: true, text: text)
        ModelContext(container).insert(message)
        return message
    }

    @MainActor
    func testFreshClosuresDoNotInvalidateAnUnchangedRow() throws {
        let message = try makeMessage(text: "同一条回复")
        let lhs = CoachBubble(
            message: message,
            isLatestAssistantMessage: true,
            onRetry: {},
            onLiveRevision: {}
        )
        let rhs = CoachBubble(
            message: message,
            isLatestAssistantMessage: true,
            onRetry: {},
            onLiveRevision: {}
        )
        XCTAssertEqual(lhs, rhs)
    }

    @MainActor
    func testRenderFlagsParticipateInRowInvalidation() throws {
        let message = try makeMessage(text: "同一条回复")
        let base = CoachBubble(message: message)
        XCTAssertNotEqual(base, CoachBubble(message: message, isLatestAssistantMessage: true))
        XCTAssertNotEqual(base, CoachBubble(message: message, isLive: true))
        XCTAssertNotEqual(base, CoachBubble(message: message, isStaged: true))
        XCTAssertNotEqual(base, CoachBubble(message: message, canRetry: true))
    }

    @MainActor
    func testDiscardAvailabilityParticipatesInRowInvalidation() throws {
        let message = try makeMessage(text: "已暂存的消息")
        XCTAssertNotEqual(
            CoachBubble(message: message, onDiscardPending: nil),
            CoachBubble(message: message, onDiscardPending: {})
        )
    }

    @MainActor
    func testDifferentMessageObjectsInvalidateTheRow() throws {
        let container = try ModelContainer(
            for: CoachMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let first = CoachMessage(isFromCoach: true, text: "第一条")
        let second = CoachMessage(isFromCoach: true, text: "第二条")
        context.insert(first)
        context.insert(second)
        XCTAssertNotEqual(
            CoachBubble(message: first),
            CoachBubble(message: second)
        )
    }
}
