import XCTest

final class RecordOptimizationUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testWorkoutCardUsesExerciseDefinitionInLightTheme() {
        let app = launchRecordFixture(appearance: "light")
        assertWorkoutCard(in: app)
        keepScreenshot(of: app, named: "record-optimizations-light")
    }

    func testWorkoutCardUsesExerciseDefinitionInDarkTheme() {
        let app = launchRecordFixture(appearance: "dark")
        assertWorkoutCard(in: app)
        keepScreenshot(of: app, named: "record-optimizations-dark")
    }

    func testSettingsAreFlattenedAndBirthDateHasNoToggle() {
        let app = launchEmptyApp(appearance: "light")
        let settings = app.tabBars.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["更多"].exists)
        XCTAssertTrue(app.staticTexts["任务进度与通知"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["后台持续处理"].exists)
        XCTAssertTrue(app.staticTexts["数据与备份"].exists)

        app.buttons["身体信息"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["身体信息"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["填写出生日期"].exists)
        XCTAssertTrue(app.staticTexts["称呼"].exists)
        XCTAssertTrue(app.staticTexts["出生日期"].exists)
        keepScreenshot(of: app, named: "body-info-without-birth-toggle")

        let nameField = app.textFields["可选"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(nameField.isHittable)
        XCTAssertLessThan(nameField.frame.maxY, keyboard.frame.minY)
        keepScreenScreenshot(named: "body-info-keyboard-safe-area")
    }

    private func launchRecordFixture(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = "record-optimizations"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FAST_STREAM"] = "1"
        app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        return app
    }

    private func launchEmptyApp(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        return app
    }

    private func assertWorkoutCard(in app: XCUIApplication) {
        let list = app.scrollViews["coach-message-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        let title = app.staticTexts["单杠悬吊"]
        for _ in 0 ..< 5 where !title.exists {
            list.swipeDown()
        }
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["时长"].exists)
        XCTAssertTrue(app.staticTexts["全身"].exists)
        XCTAssertTrue(app.staticTexts["20 秒"].exists)
        XCTAssertTrue(app.staticTexts["自重"].exists)
        XCTAssertTrue(
            app.buttons["查看这条回复的执行日志"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["反馈这条 AI 回复"].exists)
    }

    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func keepScreenScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
