import XCTest

final class DailyActivityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testDailyActivityIsOneWorkoutWithThreeMetricsInBothThemes() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            app.descendants(matching: .any)["进展"].firstMatch.tap()
            let row = app.descendants(matching: .any)["daily-activity-record"].firstMatch
            reveal(row, in: app)
            XCTAssertTrue(row.label.contains("640"))
            XCTAssertTrue(row.label.contains("6.1"))
            XCTAssertTrue(row.label.contains("486"))
            XCTAssertFalse(app.descendants(matching: .any)["daily-activity-card"].firstMatch.exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "最近读取")).firstMatch.exists)
            keep(app, "daily-record-\(appearance)")
            row.tap()
            XCTAssertTrue(app.navigationBars["日常活动"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["daily-metric-steps"].firstMatch.exists)
            XCTAssertTrue(app.descendants(matching: .any)["daily-metric-activeEnergy"].firstMatch.exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "多来源")).firstMatch.exists)
            keep(app, "daily-record-detail-\(appearance)")
            app.terminate()
        }
    }

    func testDailyRecordAndSettingsWithLargeType() {
        let app = launch("dark", large: true)
        app.descendants(matching: .any)["进展"].firstMatch.tap()
        let row = app.descendants(matching: .any)["daily-activity-record"].firstMatch
        reveal(row, in: app)
        keep(app, "daily-record-large")
        row.tap()
        XCTAssertTrue(app.navigationBars["日常活动"].waitForExistence(timeout: 5))
        let energy = app.descendants(matching: .any)["daily-metric-activeEnergy"].firstMatch
        reveal(energy, in: app)
        XCTAssertTrue(energy.label.contains("486"))
        keep(app, "daily-record-detail-large")
        app.descendants(matching: .any)["设置"].firstMatch.tap()
        app.buttons["settings-apple-health"].tap()
        XCTAssertTrue(app.navigationBars["Apple 健康"].waitForExistence(timeout: 5))
        keep(app, "daily-record-settings-large")
    }

    private func launch(_ appearance: String, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["SOMA_UI_TEST_PROCESS": "1", "SOMA_UI_TEST_APPEARANCE": appearance, "SOMA_UI_PROGRESS_FIXTURE": "1", "SOMA_UI_DAILY_ACTIVITY_FIXTURE": "1"]
        app.launchArguments = ["-data.activeSpace", "demo"]
        if large {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["进展"].firstMatch.waitForExistence(timeout: 20))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 24 {
            let tab = app.tabBars.firstMatch
            let bottom = tab.exists && tab.frame.minY > app.frame.midY ? tab.frame.minY : app.frame.maxY
            let top = app.navigationBars.firstMatch.frame.maxY
            if element.exists, element.isHittable {
                if element.frame.minY >= top, element.frame.maxY < bottom {
                    return
                }
                let down = element.frame.minY < top
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.4 : 0.6))
                    .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.6 : 0.4)))
            } else {
                app.swipeUp()
            }
        }
        XCTFail("记录或指标没有完整进入可视区域")
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
