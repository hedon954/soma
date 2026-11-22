import XCTest

final class FeedbackComposerUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testReplyFeedbackStaysAboveShortcutsWhenEditing() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance, seedsReply: true)
            let feedback = app.buttons["反馈这条 AI 回复"].firstMatch
            XCTAssertTrue(feedback.waitForExistence(timeout: 15))
            feedback.tap()
            let editor = app.descendants(matching: .any)["反馈内容"].firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            editor.tap()
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

            let send = app.buttons["feedback-send"]
            let shortcut = app.buttons["快捷按钮：记录饮食"]
            assertAboveShortcut(send, shortcut: shortcut)
            let initialHeight = editor.frame.height
            editor.typeText("First\nSecond\nThird\nFourth\nFifth\nSixth\nSeventh\nEighth\nNinth")
            XCTAssertGreaterThan(editor.frame.height, initialHeight)
            XCTAssertTrue(keyboard.exists)
            assertAboveShortcut(send, shortcut: shortcut)
            XCTAssertTrue(send.isHittable)
            keepScreenshot("reply-feedback-keyboard-\(appearance)")

            send.tap()
            XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
            app.terminate()
        }
    }

    func testSettingsFeedbackCanSendTwiceWithoutLeavingSettings() {
        let app = launch(appearance: "dark")
        app.tabBars.buttons["设置"].tap()
        let editor = app.descendants(matching: .any)["反馈内容"].firstMatch
        for _ in 0 ..< 5 where !editor.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(editor.isHittable)

        let sent = app.descendants(matching: .any)["feedback-success-acknowledgement"].firstMatch
        let send = app.buttons["feedback-send"]
        for text in ["First test feedback", "Second test feedback"] {
            editor.tap()
            editor.typeText(text)
            XCTAssertTrue(send.isEnabled)
            send.tap()
            XCTAssertTrue(sent.exists || sent.waitForExistence(timeout: 2))
            XCTAssertTrue(sent.waitForNonExistence(timeout: 5))
            XCTAssertTrue(editor.isHittable)
            XCTAssertFalse(send.isEnabled, "The next feedback should start with an empty draft")
        }
        keepScreenshot("settings-feedback-ready-for-next-draft")
    }

    private func assertAboveShortcut(
        _ send: XCUIElement,
        shortcut: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let visible = NSPredicate { _, _ in
            send.exists && shortcut.exists && send.frame.maxY <= shortcut.frame.minY
        }
        let expectation = XCTNSPredicateExpectation(predicate: visible, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(appearance: String, seedsReply: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
        app.launchEnvironment["SOMA_UI_FEEDBACK_SUCCESS"] = "1"
        if seedsReply {
            app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = "record-optimizations"
        }
        app.launch()
        return app
    }
}
