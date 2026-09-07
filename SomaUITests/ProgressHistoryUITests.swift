import XCTest

final class ProgressHistoryUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testDefaultDayShowsEstimatedCalorieDeficitInBothThemes() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            let picker = app.segmentedControls["progress-period-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 15))
            XCTAssertTrue(picker.buttons["日"].isSelected, "首次进入应默认显示今天")
            XCTAssertTrue(app.otherElements["progress-nutrition-rings"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["progress-training-summary"].exists)
            XCTAssertFalse(app.buttons["progress-body-summary"].exists)
            XCTAssertFalse(app.staticTexts["预估热量缺口"].exists)
            XCTAssertFalse(app.staticTexts["与预估的差值"].exists)
            keep(app, "progress-calorie-deficit-\(appearance)")
            picker.buttons["周"].tap()
            XCTAssertFalse(app.otherElements["progress-nutrition-rings"].exists)
            XCTAssertFalse(app.buttons["progress-selected-period"].exists)
            app.tabBars.buttons["教练"].tap()
            app.tabBars.buttons["进展"].tap()
            XCTAssertTrue(picker.buttons["周"].isSelected, "返回页面应保留手动选择的周期")
            app.terminate()
        }
    }

    func testEnergyNumbersOpenSeparateCompactBreakdowns() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance, noBaseline: true)
            let picker = app.segmentedControls["progress-period-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 15))
            picker.buttons["日"].tap()
            let intake = app.buttons["progress-intake-breakdown"]
            XCTAssertTrue(intake.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(intake.frame.height, 44)
            intake.tap()
            let popover = app.scrollViews["progress-energy-breakdown-list"]
            XCTAssertTrue(popover.waitForExistence(timeout: 5))
            XCTAssertTrue(popover.staticTexts["午餐 · 进展夹具餐食 0"].exists)
            XCTAssertFalse(app.navigationBars["能量依据"].exists)
            keep(app, "energy-intake-breakdown-\(appearance)")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.25)).tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: popover)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            let expenditure = app.buttons["progress-expenditure-breakdown"]
            XCTAssertTrue(expenditure.waitForExistence(timeout: 5))
            XCTAssertTrue(expenditure.isHittable)
            expenditure.tap()
            XCTAssertTrue(popover.waitForExistence(timeout: 5))
            XCTAssertTrue(popover.staticTexts["静息消耗"].exists)
            XCTAssertTrue(popover.staticTexts["活动等消耗"].exists)
            XCTAssertFalse(popover.staticTexts["个人静息公式"].exists)
            XCTAssertFalse(popover.staticTexts["默认参考"].exists)
            XCTAssertFalse(popover.staticTexts["个人设置"].exists)
            XCTAssertLessThanOrEqual(popover.frame.height, 160, "三行组成不应留下空行")
            XCTAssertFalse(popover.staticTexts["已记录摄入"].exists)
            keep(app, "energy-expenditure-breakdown-\(appearance)")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.25)).tap()
            let expenditureDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: popover)
            XCTAssertEqual(XCTWaiter.wait(for: [expenditureDismissed], timeout: 5), .completed)
            let protein = app.buttons["progress-protein-ring-breakdown"]
            reveal(protein, in: app)
            protein.tap()
            XCTAssertTrue(popover.waitForExistence(timeout: 5))
            XCTAssertTrue(popover.staticTexts["午餐 · 进展夹具餐食 0"].exists)
            XCTAssertTrue(popover.staticTexts["110 g"].exists)
            XCTAssertFalse(popover.staticTexts["已记录蛋白质"].exists)
            XCTAssertFalse(popover.staticTexts["已记录摄入"].exists)
            XCTAssertFalse(app.buttons["progress-calorie-remaining"].exists)
            keep(app, "energy-protein-breakdown-\(appearance)")
            app.terminate()
        }
    }

    func testRestingOnlyEstimateAndCompactDetails() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance, noBaseline: true)
            let picker = app.segmentedControls["progress-period-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 15))
            picker.buttons["日"].tap()
            XCTAssertTrue(app.otherElements["progress-nutrition-rings"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["待估算"].exists)
            app.buttons["饮食与能量，查看估算依据"].tap()
            XCTAssertTrue(app.navigationBars["能量依据"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["静息消耗"].exists)
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "1.40 · 默认参考")).firstMatch.exists)
            XCTAssertFalse(app.staticTexts["统计范围"].exists)
            XCTAssertFalse(app.staticTexts["摄入有记录日"].exists)
            XCTAssertFalse(app.staticTexts["个人静息公式"].exists)
            keep(app, "energy-compact-details-\(appearance)")
            app.terminate()
        }
    }

    func testCompactEnergyDetailsRemainAccessibleAtLargeType() {
        let app = launch("dark", largeType: true, noBaseline: true)
        let picker = app.segmentedControls["progress-period-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        picker.buttons["日"].tap()
        app.buttons["饮食与能量，查看估算依据"].tap()
        XCTAssertTrue(app.staticTexts["静息消耗"].waitForExistence(timeout: 5))
        let details = app.buttons["计算明细"]
        reveal(details, in: app)
        details.tap()
        let body = app.buttons["身体资料"]
        reveal(body, in: app)
        keep(app, "energy-compact-details-accessibility")
    }

    func testEnergyBreakdownAtLargeTypeRemainsScrollable() {
        let app = launch("dark", largeType: true, noBaseline: true)
        let picker = app.segmentedControls["progress-period-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        picker.buttons["日"].tap()
        let expenditure = app.buttons["progress-expenditure-breakdown"]
        reveal(expenditure, in: app)
        expenditure.tap()
        let list = app.scrollViews["progress-energy-breakdown-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(list.frame.height, 300, "大字号不能挤在锚点下方的窄缝里")
        let factor = list.staticTexts["1.40"]
        for _ in 0 ..< 4 where !factor.isHittable {
            list.swipeUp()
        }
        XCTAssertTrue(factor.isHittable)
        keep(app, "energy-breakdown-accessibility")
    }

    func testFourPeriodsDarkAndHistoricalNavigation() {
        let app = launch("dark")
        let picker = app.segmentedControls["progress-period-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        picker.buttons["周"].tap()
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
        picker.buttons["周"].tap()
        XCTAssertFalse(app.buttons["progress-selected-period"].exists)
        XCTAssertFalse(app.otherElements["progress-nutrition-rings"].exists)
        picker.buttons["年"].tap()
        XCTAssertFalse(app.buttons["progress-selected-period"].exists)
        XCTAssertFalse(app.otherElements["progress-nutrition-rings"].exists)
        app.buttons["选择日期"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["已记录摄入"].waitForExistence(timeout: 5))
        keep(app, "progress-day-light")
        XCTAssertFalse(app.staticTexts["月内可继续选择任意一天"].exists)
    }

    func testTrainingAndBodyDetailMetricsAndRecordNavigation() {
        let app = launch("light")
        selectPeriod("周", in: app)
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

    func testChartTapDoesNotSwitchPeriod() {
        let app = launch("light")
        let picker = app.segmentedControls["progress-period-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        picker.buttons["周"].tap()
        XCTAssertFalse(app.buttons["progress-selected-period"].exists)
        let window = app.staticTexts["progress-date-range"].label
        let chart = app.descendants(matching: .any)["progress-energy-chart"].firstMatch
        XCTAssertTrue(chart.exists)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(picker.buttons["周"].isSelected)
        XCTAssertFalse(app.buttons["progress-selected-period"].exists)
        XCTAssertEqual(app.staticTexts["progress-date-range"].label, window)
        picker.buttons["年"].tap()
        XCTAssertFalse(app.buttons["progress-selected-period"].exists)
        app.descendants(matching: .any)["progress-energy-chart"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(picker.buttons["年"].isSelected)
        XCTAssertFalse(app.buttons["progress-selected-period"].exists)
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
        XCTAssertFalse(app.buttons["progress-training-summary"].exists)
        keep(app, "progress-day-accessibility-dark")
        selectPeriod("周", in: app)
        let training = app.buttons["progress-training-summary"]
        reveal(training, in: app)
        XCTAssertTrue(training.isHittable)
        XCTAssertGreaterThanOrEqual(training.frame.height, 44)
        training.tap()
        XCTAssertTrue(app.segmentedControls["progress-detail-metric"].waitForExistence(timeout: 10))
    }

    func testPeriodsShowDifferentTrainingAndBodyFocus() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            let picker = app.segmentedControls["progress-period-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 15))
            XCTAssertTrue(picker.buttons["日"].isSelected)
            XCTAssertTrue(app.staticTexts["饮食记录"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["progress-training-summary"].exists)
            XCTAssertFalse(app.buttons["progress-body-summary"].exists)
            keep(app, "focus-day-\(appearance)")
            for (period, trainingText, bodyText) in [("周", "训练 ", "周均体重"), ("月", "总容量", "最新体重"), ("年", "累计训练", "最新月均体重")] {
                selectPeriod(period, in: app)
                if period == "月" {
                    app.buttons["上一月"].tap()
                }
                let training = app.buttons["progress-training-summary"]
                reveal(training, in: app)
                XCTAssertTrue(training.label.contains(trainingText))
                let body = app.buttons["progress-body-summary"]
                reveal(body, in: app)
                XCTAssertTrue(body.label.contains(bodyText))
                if period == "月" {
                    XCTAssertTrue(body.label.contains("月内变化"))
                }
                if period == "年" {
                    XCTAssertTrue(body.label.contains("月均变化"))
                }
                keep(app, "focus-\(period)-\(appearance)")
            }
            app.terminate()
        }
    }

    private func selectPeriod(_ period: String, in app: XCUIApplication) {
        let picker = app.segmentedControls["progress-period-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        for _ in 0 ..< 8 where !picker.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(picker.isHittable)
        picker.buttons[period].tap()
    }

    private func launch(_ appearance: String, largeType: Bool = false, noBaseline: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PROGRESS_FIXTURE"] = "1"
        app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
        if noBaseline {
            app.launchEnvironment["SOMA_UI_PROGRESS_NO_BASELINE"] = "1"
        }
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
