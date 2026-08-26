import XCTest

/// BUG 0040 的模拟器回归：切回「教练」自动显示最新消息、再点「教练」无重建回根、
/// Tab 切换保留分页与滚动状态。使用完成态长流夹具（no-newline + fast stream），
/// 避免流式自动跟随把上滑断言拉回底部。
final class CoachTabBehaviorUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSwitchingBackToCoachReturnsToLatestMessageAndKeepsPages() {
        let app = launchCompletedLongStreamApp()
        let messageList = app.scrollViews["coach-message-list"]
        XCTAssertTrue(messageList.waitForExistence(timeout: 15))
        scrollUpUntilPagedAwayFromBottom(messageList)

        let training = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.375, dy: 0.93)
        )
        let coach = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.125, dy: 0.93)
        )
        training.tap()
        Thread.sleep(forTimeInterval: 0.4)
        coach.tap()

        XCTAssertTrue(
            waitForValue(containing: "nearBottom=true", on: messageList, timeout: 5),
            "切回教练没有自动回到最新消息：\(messageList.value as? String ?? "nil")"
        )
        XCTAssertTrue(
            (messageList.value as? String ?? "").hasPrefix("count=20"),
            "Tab 切换重建了会话页（分页被重置）：\(messageList.value as? String ?? "nil")"
        )
    }

    func testReselectingCoachTabRestoresLatestMessageWithoutRebuilding() {
        let app = launchCompletedLongStreamApp()
        let messageList = app.scrollViews["coach-message-list"]
        XCTAssertTrue(messageList.waitForExistence(timeout: 15))
        scrollUpUntilPagedAwayFromBottom(messageList)

        // 已在教练 Tab 上再次点按同一 Tab：应收起导航层级并滚到底部，
        // 而不是销毁重建整棵对话树。
        app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.125, dy: 0.93)
        ).tap()

        XCTAssertTrue(
            waitForValue(containing: "nearBottom=true", on: messageList, timeout: 5),
            "再点教练没有回到最新消息：\(messageList.value as? String ?? "nil")"
        )
        XCTAssertTrue(
            (messageList.value as? String ?? "").hasPrefix("count=20"),
            "再点教练重建了会话页（分页被重置）：\(messageList.value as? String ?? "nil")"
        )
    }

    /// 启动完成态长流夹具：流式已结束（streaming=false），列表初始贴底。
    private func launchCompletedLongStreamApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = "long-stream-no-newline"
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

    /// 上滑触发到顶自动分页（10 → 20 条），并确认离开底部。
    private func scrollUpUntilPagedAwayFromBottom(_ messageList: XCUIElement) {
        for _ in 0 ..< 12 where !(messageList.value as? String ?? "").hasPrefix("count=20") {
            messageList.swipeDown()
        }
        XCTAssertTrue(
            waitForValue(containing: "count=20", on: messageList, timeout: 5),
            "上滑到顶未自动加载更早消息：\(messageList.value as? String ?? "nil")"
        )
        XCTAssertTrue(
            waitForValue(containing: "nearBottom=false", on: messageList, timeout: 5),
            "上滑后仍停留在底部：\(messageList.value as? String ?? "nil")"
        )
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
