import XCTest

final class BodyMassHistoryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testBodyHistoryShowsSourcesAndTrendInLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            openBodyHistory(app)
            XCTAssertTrue(app.descendants(matching: .any)["body-history-trend-section"].firstMatch.waitForExistence(timeout: 8))
            XCTAssertTrue(app.descendants(matching: .any)["body-history-health-row"].firstMatch.exists)
            XCTAssertTrue(app.descendants(matching: .any)["body-history-manual-row"].firstMatch.exists)
            let keep = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Keep")).firstMatch
            XCTAssertTrue(keep.waitForExistence(timeout: 5))
            let unknown = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Acme Scale")).firstMatch
            XCTAssertTrue(unknown.exists)
            XCTAssertFalse(app.staticTexts["Keep·自备识别标"].exists)

            XCTAssertTrue(app.buttons["体重"].exists)
            XCTAssertTrue(app.buttons["体脂率"].exists)
            XCTAssertFalse(app.buttons["腰围"].exists)
            XCTAssertFalse(keep.label.contains("腰围"))
            keepScreenshot(app, "body-history-\(appearance)")
            app.buttons["体脂率"].tap()
            keepScreenshot(app, "body-history-fat-\(appearance)")
            app.terminate()
        }
    }

    func testKeepAndManualRowsShareVisibleIconContainersInLight() {
        let app = launch("light")
        openBodyHistory(app)

        let keep = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "body-history-health-row", "Keep"))
            .firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 8))

        let manual = app.descendants(matching: .any)["body-history-manual-row"].firstMatch
        XCTAssertTrue(manual.waitForExistence(timeout: 5))

        // 同屏：Keep 夹具在今日午间，手动行在今日/昨日，打开页即可同见。
        let tabTop = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
        XCTAssertLessThan(keep.frame.minY, tabTop)
        XCTAssertLessThan(manual.frame.minY, tabTop)
        XCTAssertGreaterThan(keep.frame.maxY, 0)
        XCTAssertGreaterThan(manual.frame.maxY, 0)

        let keepIcon = keep.images["body-history-row-leading-icon"].firstMatch
        let manualIcon = manual.images["body-history-row-leading-icon"].firstMatch
        if keepIcon.exists, manualIcon.exists {
            XCTAssertEqual(keepIcon.frame.width, manualIcon.frame.width, accuracy: 2)
            XCTAssertEqual(keepIcon.frame.height, manualIcon.frame.height, accuracy: 2)
            XCTAssertGreaterThanOrEqual(keepIcon.frame.width, 50)
            XCTAssertLessThanOrEqual(keepIcon.frame.width, 66)
        } else {
            XCTAssertEqual(keep.frame.height, manual.frame.height, accuracy: 16)
        }

        XCTAssertFalse(keep.label.contains("腰围"))
        XCTAssertFalse(manual.label.contains("腰围"))
        keepScreenshot(app, "body-history-keep-manual-unified-light")
    }

    func testBodyHistoryLargeTypeTrend() {
        let app = launch("dark", large: true)
        openBodyHistory(app)
        XCTAssertTrue(
            app.descendants(matching: .any)["body-history-trend-chart"].firstMatch.waitForExistence(timeout: 8)
                || app.descendants(matching: .any)["body-history-trend-section"].firstMatch.exists
        )
        XCTAssertFalse(app.buttons["腰围"].exists)
        keepScreenshot(app, "body-history-large")
    }

    func testHealthSettingsMentionsWeightScope() {
        let app = launch("light")
        app.descendants(matching: .any)["设置"].firstMatch.tap()
        let health = app.buttons["settings-apple-health"]
        reveal(health, in: app)
        health.tap()
        XCTAssertTrue(app.navigationBars["Apple 健康"].waitForExistence(timeout: 5))
        let copy = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "体重")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        keepScreenshot(app, "health-settings-weight-scope")
    }

    private func openBodyHistory(_ app: XCUIApplication) {
        app.descendants(matching: .any)["进展"].firstMatch.tap()
        XCTAssertTrue(app.segmentedControls["progress-period-picker"].waitForExistence(timeout: 10))
        let link = app.buttons["身体记录"].firstMatch
        reveal(link, in: app)
        link.tap()
        XCTAssertTrue(app.navigationBars["体重记录"].waitForExistence(timeout: 8))
    }

    private func launch(_ appearance: String, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "SOMA_UI_TEST_PROCESS": "1",
            "SOMA_UI_TEST_APPEARANCE": appearance,
            "SOMA_UI_PROGRESS_FIXTURE": "1",
            "SOMA_UI_BODY_MASS_FIXTURE": "1"
        ]
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
            if element.exists, element.isHittable {
                return
            }
            app.swipeUp()
        }
        XCTFail("目标入口未进入可视区域")
    }

    private func keepScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
