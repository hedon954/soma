import XCTest

final class ProgressHistoryUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testDayShowsEstimatedCalorieDeficitInBothThemes() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            let picker = app.segmentedControls["progress-period-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 15))
            picker.buttons["日"].tap()
            XCTAssertTrue(app.staticTexts["445 kcal"].waitForExistence(timeout: 5), "缺口应为预估消耗 2345 减去已记录摄入 1900")
            XCTAssertTrue(app.staticTexts["预估热量缺口"].exists)
            XCTAssertFalse(app.staticTexts["与预估的差值"].exists)
            keep(app, "progress-calorie-deficit-\(appearance)")
            app.terminate()
        }
    }

    func testFourPeriodsDarkAndHistoricalNavigation() {
        let app = launch("dark")
        let picker = app.segmentedControls["progress-period-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["日均预估总消耗"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["下一周"].isEnabled)
        keep(app, "progress-week-dark")
        picker.buttons["月"].tap()
        XCTAssertTrue(app.buttons["上一月"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["下一月"].isEnabled)
        keep(app, "progress-month-dark")
        picker.buttons["年"].tap()
        XCTAssertTrue(app.buttons["上一年"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["下一年"].isEnabled)
        keep(app, "progress-year-dark")
        picker.buttons["日"].tap()
        XCTAssertTrue(app.staticTexts["蛋白质"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["下一日"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["progress-training-mini-chart"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["progress-body-mini-chart"].exists)
        keep(app, "progress-day-dark")
        app.buttons["上一日"].tap()
        XCTAssertTrue(app.buttons["下一日"].isEnabled)
        let selected = app.staticTexts["progress-date-range"].label
        app.tabBars.buttons["教练"].tap()
        app.tabBars.buttons["进展"].tap()
        XCTAssertEqual(app.staticTexts["progress-date-range"].label, selected)
        XCTAssertTrue(app.buttons["回到今天"].exists)
        app.buttons["回到今天"].tap()
        XCTAssertNotEqual(app.staticTexts["progress-date-range"].label, selected)
    }

    func testLightThemeCalendarAndDrillDownPreserveWindow() {
        let app = launch("light")
        let picker = app.segmentedControls["progress-period-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        let original = app.staticTexts["progress-date-range"].label
        let drill = app.buttons["progress-selected-period"]
        XCTAssertTrue(drill.waitForExistence(timeout: 10))
        for _ in 0 ..< 3 where !drill.isHittable {
            app.swipeUp()
        }
        drill.tap()
        XCTAssertTrue(app.staticTexts["蛋白质"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.staticTexts["progress-date-range"].label, original)
        app.buttons["选择日期"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["已记录摄入"].waitForExistence(timeout: 5))
        keep(app, "progress-day-light")
        XCTAssertFalse(app.staticTexts["月内可继续选择任意一天"].exists)
    }

    func testTrainingAndBodyDetailMetricsAndRecordNavigation() {
        let app = launch("light")
        let training = app.buttons["progress-training-summary"]
        reveal(training, in: app)
        training.tap()
        let metrics = app.segmentedControls["progress-detail-metric"]
        XCTAssertTrue(metrics.waitForExistence(timeout: 10))
        metrics.buttons["容量"].tap()
        keep(app, "progress-training-detail-light")
        metrics.buttons["训练天数"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let body = app.buttons["progress-body-summary"]
        reveal(body, in: app)
        body.tap()
        XCTAssertTrue(metrics.waitForExistence(timeout: 10))
        metrics.buttons["体脂率"].tap()
        metrics.buttons["腰围"].tap()
        keep(app, "progress-body-detail-light")
        metrics.buttons["体重"].tap()
    }

    func testChartTapSelectsDayWithoutChangingPeriod() {
        let app = launch("light")
        XCTAssertTrue(app.buttons["progress-selected-period"].waitForExistence(timeout: 10))
        let window = app.staticTexts["progress-date-range"].label
        let before = app.buttons["progress-selected-period"].label
        let chart = app.descendants(matching: .any)["progress-energy-chart"].firstMatch
        XCTAssertTrue(chart.exists)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: app.buttons["progress-selected-period"])
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.staticTexts["progress-date-range"].label, window)
    }

    func testEnergyHeaderWholeRowOpensSourcesAfterPeriodChange() {
        let app = launch("dark")
        let picker = app.segmentedControls["progress-period-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        picker.buttons["日"].tap()
        XCTAssertTrue(app.staticTexts["蛋白质"].waitForExistence(timeout: 10))
        let header = app.buttons["饮食与能量，查看估算依据"]
        XCTAssertGreaterThanOrEqual(header.frame.height, 44)
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["能量依据"].waitForExistence(timeout: 5))
        keep(app, "progress-energy-sources-dark")
    }

    func testDayTrainingShareReusesTheWorkoutPoster() {
        let app = launch("light")
        let picker = app.segmentedControls["progress-period-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        picker.buttons["日"].tap()
        let share = app.buttons["分享当天训练"]
        reveal(share, in: app)
        XCTAssertGreaterThanOrEqual(share.frame.height, 44)
        share.tap()
        XCTAssertTrue(app.navigationBars["分享训练"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["训练分享海报"].waitForExistence(timeout: 10))
        keep(app, "progress-day-training-share-light")
    }

    func testAccessibilityTypeKeepsDatesAndMetricsReachable() {
        let app = launch("dark", largeType: true)
        XCTAssertTrue(app.segmentedControls["progress-period-picker"].waitForExistence(timeout: 10))
        app.segmentedControls["progress-period-picker"].buttons["日"].tap()
        XCTAssertTrue(app.staticTexts["蛋白质"].waitForExistence(timeout: 10))
        keep(app, "progress-day-accessibility-dark")
        let training = app.buttons["progress-training-summary"]
        reveal(training, in: app)
        XCTAssertTrue(training.isHittable)
        XCTAssertGreaterThanOrEqual(training.frame.height, 44)
        training.tap()
        XCTAssertTrue(app.segmentedControls["progress-detail-metric"].waitForExistence(timeout: 10))
    }

    private func launch(_ appearance: String, largeType: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PROGRESS_FIXTURE"] = "1"
        app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
        if largeType {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["进展"].tap()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 8 {
            if element.exists, element.isHittable {
                return
            }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
