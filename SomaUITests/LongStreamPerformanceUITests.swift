import XCTest

final class LongStreamPerformanceUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLongStreamKeepsFourTabsResponsive() {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = "long-stream"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        XCTAssertEqual(
            tabBar.buttons.allElementsBoundByIndex.map(\.label),
            ["教练", "训练", "进展", "设置"]
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["coach-live-agent-text"]
                .waitForExistence(timeout: 15),
            "长流性能夹具未进入实时回复状态"
        )
        keepScreenshot(of: app, named: "long-stream-coach-before-loop")

        let targets: [CGFloat] = [0.375, 0.625, 0.875, 0.125]
        let coordinates = targets.map { x in
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.93))
        }
        for _ in 0 ..< 4 {
            for coordinate in coordinates {
                coordinate.tap()
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        XCTAssertTrue(app.navigationBars["Soma"].waitForExistence(timeout: 3))
        keepScreenshot(of: app, named: "long-stream-coach-after-loop")
    }

    func testLongStreamContinuesFollowingBottomAfterUserScroll() {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = "long-stream"
        app.launch()

        let messageList = app.scrollViews["coach-message-list"]
        XCTAssertTrue(messageList.waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.descendants(matching: .any)["coach-live-agent-text"]
                .waitForExistence(timeout: 15)
        )

        // 流式期间即使用户尝试上滑查看历史，也必须在下一次投影时回到底部；
        // 这是产品明确要求的持续跟随，不依赖用户手动追赶最新 token。
        messageList.swipeDown()
        let bottom = app.descendants(matching: .any)["coach-live-agent-bottom"]
        let deadline = Date().addingTimeInterval(5)
        var bottomIsVisible = false
        while Date() < deadline, !bottomIsVisible {
            bottomIsVisible = bottom.exists
                && bottom.isHittable
                && (messageList.value as? String ?? "").contains("streaming=true")
            if !bottomIsVisible {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }
        XCTAssertTrue(
            bottomIsVisible,
            "流式回复没有持续跟随可见底部：\(messageList.value as? String ?? "nil")"
        )
    }

    func testConversationHistoryCanReturnToLargeSession() {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = "long-stream"
        app.launch()

        let liveText = app.descendants(matching: .any)["coach-live-agent-text"]
        XCTAssertTrue(liveText.waitForExistence(timeout: 15))

        app.buttons["历史对话"].tap()
        let olderSession = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "性能测试：可切换旧对话")
        ).firstMatch
        XCTAssertTrue(olderSession.waitForExistence(timeout: 5))
        olderSession.coordinate(
            withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)
        ).tap()
        XCTAssertTrue(app.staticTexts["已成功切换到旧会话。"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons.matching(identifier: "meal-inline-value-display")
                .firstMatch.waitForExistence(timeout: 5),
            "十项饮食卡没有完成渲染"
        )
        XCTAssertEqual(
            app.textFields.matching(identifier: "meal-inline-value-editor").count,
            0,
            "未开始编辑时不应预先创建整张卡的原生输入控件"
        )

        app.buttons["历史对话"].tap()
        let currentOlderSession = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "性能测试：可切换旧对话")
        ).firstMatch
        currentOlderSession.press(forDuration: 0.7)
        XCTAssertTrue(app.alerts["重命名对话"].waitForExistence(timeout: 5))
        app.alerts["重命名对话"].buttons["取消"].tap()

        let largeSession = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "性能测试：虚构长对话")
        ).firstMatch
        XCTAssertTrue(largeSession.waitForExistence(timeout: 5))
        largeSession.coordinate(
            withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)
        ).tap()

        app.buttons["历史对话"].tap()
        let selectedLargeSession = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "性能测试：虚构长对话")
        ).firstMatch
        XCTAssertTrue(selectedLargeSession.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedLargeSession.value as? String, "当前对话")
    }

    func testCoachStartsWithTenMessagesAndPagesUpByTen() {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = "long-stream"
        app.launch()

        let messageList = app.scrollViews["coach-message-list"]
        XCTAssertTrue(messageList.waitForExistence(timeout: 15))
        XCTAssertTrue(
            (messageList.value as? String ?? "").hasPrefix("count=10"),
            "初始只应查询并渲染最近 10 条：\(messageList.value as? String ?? "nil")"
        )

        for _ in 0 ..< 12 where !(messageList.value as? String ?? "").hasPrefix("count=20") {
            messageList.swipeDown()
        }
        let loadedNextPage = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH %@", "count=20"),
            object: messageList
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [loadedNextPage], timeout: 5),
            .completed,
            "上滑到顶部后应自动再加载 10 条消息：\(messageList.value as? String ?? "nil")"
        )
    }

    func testNoNewlineLongStreamCompletesAndKeepsTabsResponsive() {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = "long-stream-no-newline"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FAST_STREAM"] = "1"
        app.launch()

        let liveText = app.descendants(matching: .any)["coach-live-agent-text"]
        XCTAssertTrue(liveText.waitForExistence(timeout: 15))
        let completed = app.descendants(matching: .any)["coach-completed-agent-text"]
        XCTAssertTrue(
            completed.waitForExistence(timeout: 15),
            "无换行长流没有走到持久化和完成态 Markdown 渲染"
        )

        let targets: [CGFloat] = [0.375, 0.625, 0.875, 0.125]
        for x in targets {
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.93)).tap()
        }
        XCTAssertTrue(app.navigationBars["Soma"].waitForExistence(timeout: 3))
        keepScreenshot(of: app, named: "no-newline-completed-after-tabs")
    }

    func testMarkdownLongStreamCompletesBackgroundPreparation() {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] =
            "long-stream-markdown-completion"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FAST_STREAM"] = "1"
        app.launch()

        let phase = app.descendants(matching: .any)["performance-fixture-phase"]
        XCTAssertTrue(
            phase.waitForExistence(timeout: 15),
            "混合 Markdown 性能夹具没有启动"
        )
        XCTAssertTrue(
            waitForValuePrefix("completed", on: phase, timeout: 15),
            "混合 Markdown 长流没有完成持久化切换；阶段="
                + (phase.value as? String ?? "missing")
        )

        let preparedResponse = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND value == %@ AND label CONTAINS %@",
                "coach-completed-agent-text",
                "Markdown 已就绪",
                "第 1 段虚构复盘"
            )
        ).firstMatch
        XCTAssertTrue(
            preparedResponse.waitForExistence(timeout: 10),
            "混合 Markdown 长流没有完成后台解析并提交语义布局；阶段="
                + (phase.value as? String ?? "missing")
        )

        let tabBar = app.tabBars.firstMatch
        for label in ["训练", "进展", "设置", "教练"] {
            tabBar.buttons[label].tap()
        }
        XCTAssertTrue(app.navigationBars["Soma"].waitForExistence(timeout: 3))
        keepScreenshot(of: app, named: "markdown-completed-after-tabs")
    }

    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForValuePrefix(
        _ prefix: String,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if (element.value as? String)?.hasPrefix(prefix) == true {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }
}
