import XCTest

final class DailyTargetDeficitUITests: XCTestCase {
    func testFatLossPreferenceSavesAndReopens() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PROGRESS_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["设置"].tap()
        app.buttons["身体信息"].tap()
        XCTAssertTrue(app.navigationBars["身体信息"].waitForExistence(timeout: 5))
        app.buttons["健身目标"].tap()
        app.buttons["减脂"].tap()
        let field = app.textFields["dailyTargetDeficitField"]
        for _ in 0 ..< 4 where !field.isHittable { app.swipeUp() }
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "400")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "600")
        app.navigationBars["身体信息"].buttons["保存"].tap()
        XCTAssertFalse(app.navigationBars["身体信息"].buttons["保存"].exists)
        app.navigationBars["身体信息"].buttons.element(boundBy: 0).tap()
        app.buttons["身体信息"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "600")
    }
}
