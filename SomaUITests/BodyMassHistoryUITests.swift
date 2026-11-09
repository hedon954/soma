import XCTest

final class BodyMassHistoryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testBodyHistoryShowsSourcesAndCombinedTrendInLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            openBodyHistory(app)
            XCTAssertTrue(app.descendants(matching: .any)["body-history-trend-section"].firstMatch.waitForExistence(timeout: 8))
            XCTAssertTrue(app.descendants(matching: .any)["body-history-trend-legend"].firstMatch.waitForExistence(timeout: 5))
            let range = app.descendants(matching: .any)["body-history-trend-range"].firstMatch
            XCTAssertTrue(range.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["一个月"].exists || range.label.contains("一个月"))
            // 默认一个月；切换四种区间后列表仍在。
            let ranges: [(String, String)] = [
                ("一周", "week"),
                ("一个月", "month"),
                ("三个月", "three-months"),
                ("一年", "year")
            ]
            for (title, slug) in ranges {
                let button = app.buttons[title]
                if button.exists {
                    button.tap()
                }
                keepScreenshot(app, "body-history-range-\(slug)-\(appearance)")
            }
            XCTAssertTrue(app.descendants(matching: .any)["body-history-health-row"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["body-history-trend-axis-units"].firstMatch.exists
                || app.staticTexts["kg"].exists)

            let chart = app.descendants(matching: .any)["body-history-trend-chart"].firstMatch
            XCTAssertTrue(chart.waitForExistence(timeout: 5))
            // 合并单图：不应再出现分拆的两张图标识。
            XCTAssertFalse(app.descendants(matching: .any)["body-history-trend-chart-weight"].firstMatch.exists)
            XCTAssertFalse(app.descendants(matching: .any)["body-history-trend-chart-body-fat"].firstMatch.exists)
            XCTAssertFalse(app.descendants(matching: .any)["body-history-trend-metric"].firstMatch.exists)
            XCTAssertFalse(app.buttons["腰围"].exists)
            // 回归：无障碍文案声明两条独立曲线（防 LineMark 混 series 串线）。
            XCTAssertTrue(
                chart.label.contains("独立") || chart.label.contains("体重与体脂"),
                "chart a11y should describe independent combined series, got: \(chart.label)"
            )

            let legend = app.descendants(matching: .any)["body-history-trend-legend"].firstMatch
            XCTAssertTrue(legend.label.contains("体重") || app.staticTexts["体重 kg"].exists)
            XCTAssertTrue(legend.label.contains("体脂") || app.staticTexts["体脂率 %"].exists)

            XCTAssertTrue(app.descendants(matching: .any)["body-history-health-row"].firstMatch.exists)
            XCTAssertTrue(app.descendants(matching: .any)["body-history-manual-row"].firstMatch.exists)
            let keep = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Keep")).firstMatch
            XCTAssertTrue(keep.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Keep·自备识别标"].exists)
            XCTAssertFalse(keep.label.contains("腰围"))
            if app.buttons["一个月"].exists {
                app.buttons["一个月"].tap()
            }
            keepScreenshot(app, "body-history-range-\(appearance)")
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

        let tabTop = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
        if keep.frame.minY >= tabTop - 8 || manual.frame.minY >= tabTop - 8 {
            app.swipeUp()
        }
        XCTAssertLessThan(keep.frame.minY, tabTop)
        XCTAssertLessThan(manual.frame.minY, tabTop)

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

    func testBodyHistoryLargeTypeCombinedTrend() {
        let app = launch("dark", large: true)
        openBodyHistory(app)
        XCTAssertTrue(
            app.descendants(matching: .any)["body-history-trend-section"].firstMatch.waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["body-history-trend-chart"].firstMatch.exists
                || app.descendants(matching: .any)["body-history-trend-legend"].firstMatch.exists
        )
        XCTAssertFalse(app.buttons["腰围"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["body-history-trend-metric"].firstMatch.exists)
        keepScreenshot(app, "body-history-large")
    }

    func testHealthSettingsMentionsWeightAndBodyFatScope() {
        let app = launch("light")
        app.descendants(matching: .any)["设置"].firstMatch.tap()
        let health = app.buttons["settings-apple-health"]
        reveal(health, in: app)
        health.tap()
        XCTAssertTrue(app.navigationBars["Apple 健康"].waitForExistence(timeout: 5))
        let weightCopy = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "体重")).firstMatch
        XCTAssertTrue(weightCopy.waitForExistence(timeout: 5))
        let fatCopy = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "体脂")).firstMatch
        XCTAssertTrue(fatCopy.waitForExistence(timeout: 5))
        keepScreenshot(app, "health-settings-weight-bodyfat-scope")
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
