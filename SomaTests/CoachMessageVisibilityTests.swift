@testable import Soma
import XCTest

final class CoachMessageVisibilityTests: XCTestCase {
    func testPreparedPageKeepsAssistantMessagesWhenCacheIsCold() {
        let user = CoachMessage(sessionID: UUID(), isFromCoach: false, text: "虚构早餐")
        let assistant = CoachMessage(
            sessionID: user.sessionID,
            isFromCoach: true,
            text: "已记下",
            agentStatus: .succeeded
        )
        let visible = CoachMessageVisibility.displayed(
            messages: [user, assistant],
            didPreparePage: true,
            processingHere: false
        )
        XCTAssertEqual(visible.map(\.id), [user.id, assistant.id])
    }

    func testUnpreparedPageStillShowsAssistantMessages() {
        let user = CoachMessage(sessionID: UUID(), isFromCoach: false, text: "虚构早餐")
        let assistant = CoachMessage(
            sessionID: user.sessionID,
            isFromCoach: true,
            text: "已记下",
            agentStatus: .succeeded
        )
        let visible = CoachMessageVisibility.displayed(
            messages: [user, assistant],
            didPreparePage: false,
            processingHere: false
        )
        XCTAssertEqual(visible.map(\.id), [user.id, assistant.id])
    }
}
