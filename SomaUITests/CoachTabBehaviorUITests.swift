import XCTest

/// BUG 0040 / PRD 047 的模拟器回归：切回「教练」自动显示最新消息，
/// 再点「教练」保持当前阅读状态，非教练 Tab 仅在详情页再点回根。
/// 使用带 39 轮历史的专用完成态短回复夹具，
/// 避免流式自动跟随与超长正文高度干扰分页断言。
final class CoachTabBehaviorUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSwitchingBackToCoachReturnsToLatestMessageAndKeepsPages() {
        let app = launchCompletedLongStreamApp()
        let messageList = app.scrollViews["coach-message-list"]
        XCTAssertTrue(messageList.waitForExistence(timeout: 15))
        let retainedCount = scrollUpUntilPagedAwayFromBottom(messageList)

        let training = app.tabBars.buttons["训练"]
        let coach = app.tabBars.buttons["教练"]
        XCTAssertTrue(training.waitForExistence(timeout: 5))
        XCTAssertTrue(coach.waitForExistence(timeout: 5))
        training.tap()
        XCTAssertTrue(waitForSelection(of: training, timeout: 5), "未切换到训练 Tab")
        coach.tap()

        XCTAssertTrue(messageList.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForValue(containing: "nearBottom=true", on: messageList, timeout: 5),
            "切回教练没有自动回到最新消息：\(messageList.value as? String ?? "nil")"
        )
        XCTAssertEqual(
            messageCount(of: messageList),
            retainedCount,
            "Tab 切换重建了会话页（分页被重置）：\(messageList.value as? String ?? "nil")"
        )
    }

    func testReselectingCoachTabDoesNothing() {
        let app = launchCompletedLongStreamApp()
        let messageList = app.scrollViews["coach-message-list"]
        XCTAssertTrue(messageList.waitForExistence(timeout: 15))
        let retainedCount = scrollUpUntilPagedAwayFromBottom(messageList)

        // 已在教练 Tab 上再次点按同一 Tab：页面、滚动和分页都不应变化。
        let coach = app.tabBars.buttons["教练"]
        XCTAssertTrue(coach.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSelection(of: coach, timeout: 5), "教练 Tab 未处于选中态")
        coach.tap()

        let unexpectedScroll = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "nearBottom=true"),
            object: messageList
        )
        unexpectedScroll.isInverted = true
        wait(for: [unexpectedScroll], timeout: 1.5)
        XCTAssertGreaterThanOrEqual(
            messageCount(of: messageList) ?? 0,
            retainedCount,
            "再点教练丢失了已加载分页：\(messageList.value as? String ?? "nil")"
        )
    }

    func testReselectingSettingsReturnsToRootOnlyFromDetail() {
        let app = launchCompletedLongStreamApp()
        let settings = app.tabBars.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(waitForSelection(of: settings, timeout: 5), "未切换到设置 Tab")

        let llmConfiguration = app.descendants(matching: .any)[
            "settings-llm-configuration"
        ].firstMatch
        XCTAssertTrue(llmConfiguration.waitForExistence(timeout: 5))
        llmConfiguration.tap()
        XCTAssertTrue(app.navigationBars["LLM 配置"].waitForExistence(timeout: 5))

        settings.tap()
        XCTAssertTrue(
            app.navigationBars["设置"].waitForExistence(timeout: 5),
            "设置详情再选没有回到设置根页"
        )
    }

    /// 启动专用 Tab 行为夹具：流式已结束（streaming=false），列表初始贴底。
    private func launchCompletedLongStreamApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = "coach-tab-behavior"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FAST_STREAM"] = "1"
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "Soma 未进入前台"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["coach-completed-agent-text"]
                .waitForExistence(timeout: 15),
            "完成态长流夹具未就绪"
        )
        return app
    }

    /// 上滑触发至少一页历史加载，等分页数量稳定后确认离开底部。
    private func scrollUpUntilPagedAwayFromBottom(_ messageList: XCUIElement) -> Int {
        let initialCount = messageCount(of: messageList) ?? 0
        var loadedCount: Int?
        for _ in 0 ..< 12 where loadedCount == nil {
            messageList.swipeDown()
            loadedCount = waitForCount(greaterThan: initialCount, on: messageList, timeout: 1.5)
        }
        XCTAssertNotNil(
            loadedCount,
            "上滑到顶未自动加载更早消息：\(messageList.value as? String ?? "nil")"
        )
        XCTAssertTrue(
            waitForValue(containing: "nearBottom=false", on: messageList, timeout: 5),
            "上滑后仍停留在底部：\(messageList.value as? String ?? "nil")"
        )
        return stableMessageCount(on: messageList, timeout: 5) ?? loadedCount ?? initialCount
    }

    private func messageCount(of element: XCUIElement) -> Int? {
        let value = element.value as? String ?? ""
        return value
            .split(separator: ",")
            .map(String.init)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("count=") })
            .flatMap { token in
                Int(token.trimmingCharacters(in: .whitespaces).dropFirst("count=".count))
            }
    }

    private func waitForCount(
        greaterThan baseline: Int,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let count = messageCount(of: element), count > baseline {
                return count
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return nil
    }

    private func stableMessageCount(
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        var lastCount = messageCount(of: element)
        var stableSince = Date()
        repeat {
            let count = messageCount(of: element)
            if count != lastCount {
                lastCount = count
                stableSince = Date()
            } else if count != nil, Date().timeIntervalSince(stableSince) >= 2 {
                return count
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return lastCount
    }

    private func waitForSelection(
        of element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.isSelected {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    private func waitForValue(
        containing fragment: String,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if (element.value as? String ?? "").contains(fragment) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }
}
