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
            // inline 小标题：导航栏仍有「体重记录」，并保留返回。
            XCTAssertTrue(app.navigationBars["体重记录"].exists)
            XCTAssertTrue(app.navigationBars["体重记录"].buttons.firstMatch.exists)
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
            XCTAssertFalse(app.staticTexts["两条曲线取自不同记录时间，不是同一次测量。"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["body-history-trend-selection"].firstMatch.exists)

            // 点选图上偏右侧样本，应出现图内浮层（默认无常驻读数）。
            let point = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.28))
            point.tap()
            let callout = app.descendants(matching: .any)["body-history-trend-selection-callout"].firstMatch
            XCTAssertTrue(callout.waitForExistence(timeout: 4), "expected on-chart selection callout after tap")
            keepScreenshot(app, "body-history-selection-\(appearance)")

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
            keepScreenshot(app, "body-history-inline-title-\(appearance)")
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
            scrollBodyHistoryList(in: app)
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

    func testBodyHistoryLargeTypeClearsFloatingTabInLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance, large: true)
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

            let before = app.screenshot().pngRepresentation
            keepScreenshot(app, "body-history-large-\(appearance)-before")

            let lastRow = revealLastBodyHistoryRow(in: app)
            let after = app.screenshot().pngRepresentation
            XCTAssertNotEqual(
                before,
                after,
                "超大字号滚动前后截图必须不同（此前 app.swipeUp 落在图表 DragGesture 上导致四张 MD5 相同）"
            )
            keepScreenshot(app, "body-history-large-\(appearance)-scrolled")

            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
            XCTAssertLessThan(
                lastRow.frame.maxY,
                tabBar.frame.minY,
                "末行 frame.maxY=\(lastRow.frame.maxY) 应低于 TabBar.minY=\(tabBar.frame.minY)；appearance=\(appearance)"
            )
            XCTAssertTrue(lastRow.isHittable, "末行应可点，不被浮动 Tab 挡住")
            keepScreenshot(app, "body-history-large-\(appearance)-bottom")

            lastRow.tap()
            XCTAssertTrue(
                app.navigationBars.firstMatch.waitForExistence(timeout: 6),
                "应能点开最后一条记录进入详情"
            )
            // 详情不一定改标题；有返回即可。
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
            XCTAssertTrue(app.navigationBars["体重记录"].waitForExistence(timeout: 6))
            keepScreenshot(app, "body-history-large-\(appearance)-after-back")
            app.terminate()
        }
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

    @discardableResult
    private func revealLastBodyHistoryRow(in app: XCUIApplication) -> XCUIElement {
        let lastRow = app.descendants(matching: .any)["body-history-last-row"].firstMatch
        let tabBar = app.tabBars.firstMatch
        var previousMaxY: CGFloat = -1
        for _ in 0 ..< 48 {
            if lastRow.exists {
                let tabTop = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
                if lastRow.frame.maxY > 0, lastRow.frame.maxY < tabTop, lastRow.isHittable {
                    return lastRow
                }
                // 已见到末行但仍被挡或未 hittable：继续滚列表容器，避免再点图表。
                if abs(lastRow.frame.maxY - previousMaxY) < 0.5 {
                    scrollBodyHistoryList(in: app)
                } else {
                    previousMaxY = lastRow.frame.maxY
                    scrollBodyHistoryList(in: app)
                }
            } else {
                scrollBodyHistoryList(in: app)
            }
        }
        XCTAssertTrue(lastRow.waitForExistence(timeout: 2), "应能滚到 body-history-last-row")
        return lastRow
    }

    private func scrollBodyHistoryList(in app: XCUIApplication) {
        let list = bodyHistoryScrollContainer(in: app)
        if list.exists {
            list.swipeUp(velocity: .fast)
            return
        }
        // 兜底：从屏幕下半部起拖，避开图表区域（根因复现路径是中心 swipe 落在图表上）。
        let frame = app.frame
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        _ = frame
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func bodyHistoryScrollContainer(in app: XCUIApplication) -> XCUIElement {
        let identified = app.descendants(matching: .any)["body-history-list"].firstMatch
        if identified.exists {
            return identified
        }
        if app.collectionViews.firstMatch.exists {
            return app.collectionViews.firstMatch
        }
        return app.tables.firstMatch
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
