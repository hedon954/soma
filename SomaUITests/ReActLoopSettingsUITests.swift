import XCTest

final class ReActLoopSettingsUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testRuntimeTimeoutLivesBesideStepLimitAndCanReturnToAutomatic() {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15), "根 Tab Bar 未出现")
        tabBar.buttons["设置"].tap()

        let advancedSettings = app.buttons["高级设置"].firstMatch
        let settingsList = app.collectionViews.firstMatch
        for _ in 0 ..< 8 where !advancedSettings.exists {
            settingsList.swipeUp()
        }
        XCTAssertTrue(advancedSettings.waitForExistence(timeout: 3), "高级设置入口未出现")
        advancedSettings.tap()

        XCTAssertTrue(
            app.navigationBars["高级设置"].waitForExistence(timeout: 5),
            "高级设置页面未出现"
        )
        XCTAssertTrue(app.staticTexts["ReAct 步骤上限"].exists)
        XCTAssertTrue(app.staticTexts["运行超时上限"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ReAct 循环设置"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let runtimeStepper = app.steppers.matching(
            NSPredicate(format: "label CONTAINS %@", "运行超时上限")
        ).firstMatch
        XCTAssertTrue(runtimeStepper.waitForExistence(timeout: 3), "运行超时 Stepper 未出现")

        let restoreDefaults = app.buttons["恢复默认 ReAct 设置"]
        if restoreDefaults.isEnabled {
            restoreDefaults.tap()
        }
        XCTAssertEqual(runtimeStepper.value as? String, "自动（3/5/10 分钟）")

        runtimeStepper.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        XCTAssertEqual(runtimeStepper.value as? String, "3 分钟")

        XCTAssertTrue(restoreDefaults.isEnabled)
        restoreDefaults.tap()
        XCTAssertEqual(runtimeStepper.value as? String, "自动（3/5/10 分钟）")
    }
}
