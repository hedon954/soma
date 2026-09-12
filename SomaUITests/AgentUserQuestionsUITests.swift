import XCTest

final class AgentUserQuestionsUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testDeterministicChoiceSendsAndHidesInBothThemes() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            let option = app.buttons["question-option-next-save"]
            XCTAssertTrue(option.waitForExistence(timeout: 15))
            keep(app, "questions-\(appearance)")
            option.tap()
            XCTAssertTrue(option.waitForNonExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["帮我记录体重 68 千克"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["已记录身体数据"].waitForExistence(timeout: 10))
            keep(app, "question-recorded-\(appearance)")
            app.terminate()
        }
    }

    func testCustomAnswerAndOrdinaryMessageDismissQuestions() {
        let app = launch(appearance: "light")
        let input = app.textViews["question-input-next"]
        let field = app.textFields["question-input-next"]
        let target = input.waitForExistence(timeout: 3) ? input : field
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        target.typeText("I want to discuss recovery")
        keep(app, "question-keyboard-light")
        app.buttons["question-send-next"].tap()
        XCTAssertTrue(app.buttons["question-option-next-talk"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["I want to discuss recovery"].waitForExistence(timeout: 10))
        app.terminate()

        let other = launch(appearance: "dark")
        let composer = other.textViews["coach-message-input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("A different question")
        other.buttons["发送"].tap()
        // 新模拟器的首次发送会先显示 App 的位置授权提示；虚构场景明确不使用位置。
        if other.buttons["不允许"].waitForExistence(timeout: 2) {
            other.buttons["不允许"].tap()
        }
        XCTAssertTrue(other.buttons["question-option-next-talk"].waitForNonExistence(timeout: 10))
        other.terminate()
    }

    func testLongQuestionSupportsAccessibilityTextSize() {
        let app = launch(appearance: "dark", long: true, accessibility: true)
        let option = app.buttons["question-option-next-talk"]
        XCTAssertTrue(option.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(option.frame.height, option.frame.width < 500 ? 180 : 80, "辅助大字号的长选项必须完整换行，不能裁切在单行高度内")
        XCTAssertLessThanOrEqual(option.frame.width, app.frame.width)
        keep(app, "question-large-text-dark")
        app.terminate()
    }

    func testLongChoicesRemainReadableOnSeparateRows() {
        let app = launch(appearance: "light", long: true)
        let option = app.buttons["question-option-next-talk"]
        XCTAssertTrue(option.waitForExistence(timeout: 15))
        keep(app, "question-long-light")
        let save = app.buttons["question-option-next-save"]
        XCTAssertLessThan(option.frame.maxY, save.frame.minY, "每个按钮必须独占一行")
        XCTAssertEqual(option.frame.minX, save.frame.minX, accuracy: 1)
        XCTAssertEqual(option.frame.maxX, save.frame.maxX, accuracy: 1)
        XCTAssertGreaterThanOrEqual(option.frame.height, option.frame.width < 500 ? 54 : 44)
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(app.staticTexts["已记录身体数据"].waitForExistence(timeout: 10))
        app.terminate()
    }

    private func launch(appearance: String, long: Bool = false, accessibility: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = "agent-stages"
        app.launchEnvironment["SOMA_UI_AGENT_STAGE"] = long ? "questions-long" : "questions"
        app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
        if accessibility {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
