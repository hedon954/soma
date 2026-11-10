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

    func testPairedKeepMeasurementShowsBothMetricsReadOnlyDetailAndNoWaist() {
        for appearance in ["light", "dark"] {
            assertPairedMeasurement(in: launch(appearance), appearance: appearance, large: false)
        }
        assertPairedMeasurement(in: launch("light", large: true), appearance: "light-large", large: true)
    }

    private func assertPairedMeasurement(in app: XCUIApplication, appearance: String, large: Bool) {
        openBodyHistory(app)
        if large {
            scrollBodyHistoryList(in: app)
        }
        let paired = app.descendants(matching: .any)["body-history-paired-row"].firstMatch
        XCTAssertTrue(paired.waitForExistence(timeout: 8), "同源同一秒的 Keep 体重+体脂应显示为一行")
        let tabTop = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
        if paired.frame.minY >= tabTop - 8 {
            scrollBodyHistoryList(in: app)
        }
        let rowLabel = paired.label
        let weight = paired.descendants(matching: .any)["body-history-row-weight"].firstMatch
        let bodyFat = paired.descendants(matching: .any)["body-history-row-body-fat"].firstMatch
        XCTAssertTrue(
            rowLabel.contains("72.4") || (weight.exists && weight.label.contains("72.4")),
            "组合行应含体重 72.4，got \(rowLabel) / \(weight.label)"
        )
        XCTAssertTrue(
            rowLabel.contains("18.6") || (bodyFat.exists && bodyFat.label.contains("18.6")),
            "组合行应含体脂 18.6，got \(rowLabel) / \(bodyFat.label)"
        )
        XCTAssertFalse(rowLabel.contains("腰围"))
        XCTAssertFalse(paired.label.contains("腰围"))

        // 超大字号下列表行使用 contain 而非 combine，70.9 在子元素 label 中。
        let splitWeight = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "body-history-row-weight", "70.9"))
            .firstMatch
        if !splitWeight.exists {
            scrollBodyHistoryList(in: app)
        }
        XCTAssertTrue(splitWeight.waitForExistence(timeout: 5), "同日不同秒的 Keep 体重应保持单指标行")
        XCTAssertFalse(splitWeight.label.contains("18.6"))
        keepScreenshot(app, "body-history-paired-row-\(appearance)")

        XCTAssertTrue(paired.isHittable || paired.exists)
        if !paired.isHittable {
            scrollBodyHistoryList(in: app)
        }
        paired.tap()
        let detail = app.descendants(matching: .any)["body-record-detail-readonly"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 6), "健康导入组合记录应为只读明细")
        let detailWeight = app.descendants(matching: .any)["body-record-detail-weight"].firstMatch
        let detailFat = app.descendants(matching: .any)["body-record-detail-body-fat"].firstMatch
        XCTAssertTrue(detailWeight.waitForExistence(timeout: 5))
        XCTAssertTrue(detailFat.waitForExistence(timeout: 5))
        XCTAssertTrue(detailWeight.label.contains("72.4") || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "72.4")).firstMatch.exists)
        XCTAssertTrue(detailFat.label.contains("18.6") || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "18.6")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["腰围"].firstMatch.exists)
        XCTAssertFalse(app.buttons["腰围"].exists)
        XCTAssertFalse(app.buttons["保存"].exists)
        keepScreenshot(app, "body-history-paired-detail-\(appearance)")
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.navigationBars["体重记录"].waitForExistence(timeout: 6))
        keepScreenshot(app, "body-history-paired-after-back-\(appearance)")
        app.terminate()
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

    func testBodyHistoryLargeTypeClearsFloatingTabInLight() {
        assertLargeTypeClearsFloatingTab(appearance: "light")
    }

    /// 独立启动深色 XXXL，避免在同一测试进程里先跑完浅色再 relaunch 导致进展页滑动卡住 idle。
    func testBodyHistoryLargeTypeClearsFloatingTabInDark() {
        assertLargeTypeClearsFloatingTab(appearance: "dark")
    }

    private func assertLargeTypeClearsFloatingTab(appearance: String) {
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
        assertPairedRowVisibleOnHistory(in: app)

        let before = app.screenshot().pngRepresentation
        keepScreenshot(app, "body-history-large-\(appearance)-before")

        assertAccessibilityMetricLinesUnbroken(in: app, appearance: appearance)

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
        assertSingleLineMetric(
            lastRow.descendants(matching: .any)["body-history-row-weight"].firstMatch,
            expectedSubstring: "kg",
            name: "末行体重"
        )
        keepScreenshot(app, "body-history-large-\(appearance)-bottom")

        lastRow.tap()
        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 6),
            "应能点开最后一条记录进入详情"
        )
        XCTAssertFalse(app.staticTexts["腰围"].firstMatch.exists)
        XCTAssertFalse(app.buttons["腰围"].exists)
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.navigationBars["体重记录"].waitForExistence(timeout: 6))
        keepScreenshot(app, "body-history-large-\(appearance)-after-back")
        app.terminate()
    }

    private func assertPairedRowVisibleOnHistory(in app: XCUIApplication) {
        let paired = app.descendants(matching: .any)["body-history-paired-row"].firstMatch
        for _ in 0 ..< 8 where !paired.exists {
            scrollBodyHistoryList(in: app)
        }
        XCTAssertTrue(paired.waitForExistence(timeout: 5), "大字号列表应能看到同源同一秒的体重+体脂组合行")
        let weight = paired.descendants(matching: .any)["body-history-row-weight"].firstMatch
        let bodyFat = paired.descendants(matching: .any)["body-history-row-body-fat"].firstMatch
        XCTAssertTrue(
            paired.label.contains("72.4") || (weight.exists && weight.label.contains("72.4")),
            "组合行应含体重 72.4，got \(paired.label) / \(weight.label)"
        )
        XCTAssertTrue(
            paired.label.contains("18.6") || (bodyFat.exists && bodyFat.label.contains("18.6")),
            "组合行应含体脂 18.6，got \(paired.label) / \(bodyFat.label)"
        )
        XCTAssertFalse(paired.label.contains("腰围"))
        keepScreenshot(app, "body-history-large-\(app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] ?? "")-paired-row")
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
        let progress = app.descendants(matching: .any)["进展"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 20))
        progress.tap()
        XCTAssertTrue(app.segmentedControls["progress-period-picker"].waitForExistence(timeout: 10))
        _ = app.descendants(matching: .any)["insights-content"].firstMatch.waitForExistence(timeout: 5)
        let link = app.buttons["身体记录"].firstMatch
        reveal(link, in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 2), "应能找到身体记录入口")
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

    /// 滚过图表后核对：体重「70.9 kg」、体脂「体脂率 18.x%」各为足宽单行，不被窄横排拆小数。
    private func assertAccessibilityMetricLinesUnbroken(in app: XCUIApplication, appearance: String) {
        var sawWeight = false
        var sawBodyFat = false
        var sawLongSource = false
        for _ in 0 ..< 36 {
            let weight = app.descendants(matching: .any)["body-history-row-weight"].firstMatch
            if weight.exists {
                assertSingleLineMetric(weight, expectedSubstring: "kg", name: "体重")
                sawWeight = true
            }
            let bodyFat = app.descendants(matching: .any)["body-history-row-body-fat"].firstMatch
            if bodyFat.exists {
                assertSingleLineMetric(bodyFat, expectedSubstring: "体脂率", name: "体脂")
                XCTAssertTrue(bodyFat.label.contains("%"), "体脂行应含 %，got \(bodyFat.label)")
                sawBodyFat = true
            }
            let source = app.descendants(matching: .any)["body-history-row-source"].firstMatch
            if source.exists, source.label.contains("超长厂商名称") {
                sawLongSource = true
            }
            if sawWeight, sawBodyFat, sawLongSource {
                break
            }
            scrollBodyHistoryList(in: app)
        }
        XCTAssertTrue(sawWeight, "超大字号应见到体重整行")
        XCTAssertTrue(sawBodyFat, "超大字号应见到体脂率整行（含纯体脂/体重+体脂行）")
        XCTAssertTrue(sawLongSource, "超大字号应见到长来源名整行")
        keepScreenshot(app, "body-history-large-\(appearance)-metrics")
    }

    private func assertSingleLineMetric(
        _ element: XCUIElement,
        expectedSubstring: String,
        name: String
    ) {
        XCTAssertTrue(element.exists, "\(name) 元素应存在")
        let label = element.label
        XCTAssertTrue(
            label.contains(expectedSubstring),
            "\(name) label 应含 \(expectedSubstring)，got \(label)"
        )
        XCTAssertFalse(label.contains("\n"), "\(name) label 不应含换行：\(label)")
        XCTAssertFalse(
            label.contains("…") || label.contains("..."),
            "\(name) 不应被截断成省略号：\(label)"
        )
        // 关键读数：小数点两侧数字与单位同在 label 内（防「70.」/「9」拆开后只露出半截）。
        let pattern = expectedSubstring == "kg"
            ? #"\d+\.\d+\s*kg"#
            : #"\d+\.\d+\s*%"#
        XCTAssertTrue(
            label.range(of: pattern, options: .regularExpression) != nil,
            "\(name) 应含完整小数读数，got \(label)"
        )
        XCTAssertGreaterThan(element.frame.width, 80, "\(name) 应占用足宽，width=\(element.frame.width)")
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
        let container = app.descendants(matching: .any)["insights-content"].firstMatch
        _ = container.waitForExistence(timeout: 5)
        for _ in 0 ..< 24 {
            if element.waitForExistence(timeout: 0.6), element.isHittable {
                return
            }
            // 从下半部短拖，避免顶部图表手势或整页 swipeUp 卡住 event-loop idle。
            let target: XCUIElement = container.exists ? container : app
            let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86))
            let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
            start.press(forDuration: 0.05, thenDragTo: end)
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
