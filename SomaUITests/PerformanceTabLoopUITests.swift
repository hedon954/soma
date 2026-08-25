import CoreFoundation
import XCTest

private let profilerReadyCallback: CFNotificationCallback = {
    _, observer, _, _, _ in
    guard let observer else { return }
    Unmanaged<XCTestExpectation>
        .fromOpaque(observer)
        .takeUnretainedValue()
        .fulfill()
}

final class PerformanceTabLoopUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTabLoop() {
        let rounds = configuredRounds()
        let app = launchPerformanceApp()

        // 从当前默认的“教练”开始，按训练 -> 进展 -> 设置 -> 教练循环，确保每一击
        // 都是一次真实的 Tab 切换。这里刻意不查询 Tab 的 AX 子树：长对话下，
        // XCUITest 为查询语义按钮构造完整可访问性文本会污染被测主线程。稳定坐标
        // 只负责注入点击，最终由 App 内 os_signpost 的 4 * rounds 样本数验证没有漏点。
        let targets: [(name: String, normalizedX: CGFloat)] = [
            ("训练", 0.375),
            ("进展", 0.625),
            ("设置", 0.875),
            ("教练", 0.125)
        ]
        let coordinateTargets = targets.map { target in
            app.coordinate(
                withNormalizedOffset: CGVector(dx: target.normalizedX, dy: 0.93)
            )
        }

        waitForProfilerReady()
        for _ in 0 ..< rounds {
            for index in targets.indices {
                coordinateTargets[index].tap()
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        // 最后一次回到教练时长对话仍需要完成可见区布局。
        // 保留收尾窗口，避免测试进程先退出、丢掉最后一个 signpost end。
        Thread.sleep(forTimeInterval: 1.5)
    }

    func testCoachSessionLoop() {
        let rounds = configuredRounds()
        let app = launchPerformanceApp(requiredFixture: "long-stream")
        let liveText = app.descendants(matching: .any)["coach-live-agent-text"]
        XCTAssertTrue(liveText.waitForExistence(timeout: 15), "长流夹具未启动")

        let historyButton = app.buttons["历史对话"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        historyButton.tap()
        let olderSession = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "性能测试：可切换旧对话")
        ).firstMatch
        let largeSession = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "性能测试：虚构长对话")
        ).firstMatch
        XCTAssertTrue(olderSession.waitForExistence(timeout: 5))
        XCTAssertTrue(largeSession.waitForExistence(timeout: 5))

        let appFrame = app.frame
        let normalized = { (frame: CGRect) in
            CGVector(
                dx: frame.midX / appFrame.width,
                dy: frame.midY / appFrame.height
            )
        }
        let historyCoordinate = app.coordinate(
            withNormalizedOffset: normalized(historyButton.frame)
        )
        let olderCoordinate = app.coordinate(
            withNormalizedOffset: normalized(olderSession.frame)
        )
        let largeCoordinate = app.coordinate(
            withNormalizedOffset: normalized(largeSession.frame)
        )
        largeCoordinate.tap()

        waitForProfilerReady()
        for _ in 0 ..< rounds {
            historyCoordinate.tap()
            Thread.sleep(forTimeInterval: 0.3)
            olderCoordinate.tap()
            Thread.sleep(forTimeInterval: 0.25)
            historyCoordinate.tap()
            Thread.sleep(forTimeInterval: 0.3)
            largeCoordinate.tap()
            Thread.sleep(forTimeInterval: 0.25)
        }
        Thread.sleep(forTimeInterval: 1.5)
    }

    func testCoachScrollLoop() {
        let rounds = configuredRounds()
        let app = launchPerformanceApp(requiredFixture: "long-stream")
        let list = app.scrollViews["coach-message-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15), "消息列表未出现")
        let scrollUpStart = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)
        )
        let scrollUpEnd = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)
        )

        waitForProfilerReady()
        for _ in 0 ..< rounds {
            scrollUpStart.press(forDuration: 0.05, thenDragTo: scrollUpEnd)
            scrollUpEnd.press(forDuration: 0.05, thenDragTo: scrollUpStart)
        }
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func configuredRounds() -> Int {
        let environment = ProcessInfo.processInfo.environment
        let configured = environment["SOMA_UI_TAB_ROUNDS"]
            ?? environment["TEST_RUNNER_SOMA_UI_TAB_ROUNDS"]
            ?? "30"
        return max(1, Int(configured) ?? 30)
    }

    private func launchPerformanceApp(requiredFixture: String? = nil) -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        let fixture = requiredFixture
            ?? environment["SOMA_UI_PERFORMANCE_FIXTURE"]
            ?? environment["TEST_RUNNER_SOMA_UI_PERFORMANCE_FIXTURE"]
        if let fixture, !fixture.isEmpty {
            app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = fixture
        }
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "Soma 未进入前台"
        )
        return app
    }

    private func waitForProfilerReady() {
        let environment = ProcessInfo.processInfo.environment
        if environment["SOMA_UI_SKIP_PROFILER_WAIT"] == "1"
            || environment["TEST_RUNNER_SOMA_UI_SKIP_PROFILER_WAIT"] == "1"
        {
            return
        }
        let notificationName = "top.hedon.soma.performance-profile-ready"
        let ready = expectation(description: "Time Profiler 已附着 Soma")
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(ready).toOpaque()
        let name = CFNotificationName(notificationName as CFString)
        CFNotificationCenterAddObserver(
            center,
            observer,
            profilerReadyCallback,
            name.rawValue,
            nil,
            .deliverImmediately
        )
        defer {
            CFNotificationCenterRemoveObserver(
                center,
                observer,
                name,
                nil
            )
        }
        wait(for: [ready], timeout: 120)
    }
}
