import XCTest

final class AgentStageFeedbackUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testReceivedAndModelRunningUseTheSameActivityCard() {
        for (stage, label) in [
            ("received", "已收到，正在准备处理…"),
            ("model", "正在处理请求…")
        ] {
            let app = launch(stage: stage)
            let activity = app.activityIndicators["agent-activity-item"].firstMatch
            XCTAssertTrue(activity.waitForExistence(timeout: 15))
            XCTAssertEqual(activity.label, label)
            keepScreenshot(of: app, named: "agent-stage-\(stage)")
            app.terminate()
        }
    }

    func testToolAndSkillStagesRenderAsStableOperationCards() {
        let fixtures: [(stage: String, identifier: String, visibleText: String)] = [
            ("preparing", "agent-operation-preparing", "准备执行"),
            ("running", "agent-operation-running", "正在执行"),
            ("waiting", "agent-operation-waitingForDevice", "等待在本机执行"),
            ("completed", "agent-operation-completed", "虚构训练记录已保存。"),
            ("failed", "agent-operation-failed", "虚构参数错误"),
            ("skill", "agent-operation-preparing", "准备加载")
        ]
        for fixture in fixtures {
            let app = launch(stage: fixture.stage)
            XCTAssertTrue(
                app.descendants(matching: .any)[fixture.identifier]
                    .waitForExistence(timeout: 15)
            )
            XCTAssertTrue(app.staticTexts[fixture.visibleText].exists)
            XCTAssertFalse(app.descendants(matching: .any)["agent-activity-item"].exists)
            keepScreenshot(of: app, named: "agent-stage-\(fixture.stage)")
            app.terminate()
        }
    }

    func testReasoningIsExpandedWhileRunningAndCollapsedAfterCompletion() {
        let running = launch(stage: "reasoning-running")
        XCTAssertTrue(
            running.descendants(matching: .any)["agent-reasoning-running"]
                .waitForExistence(timeout: 15)
        )
        XCTAssertTrue(running.staticTexts["先核对训练事实，再组织最终答复。"].exists)
        keepScreenshot(of: running, named: "agent-reasoning-running")
        running.terminate()

        let completed = launch(stage: "reasoning-completed")
        XCTAssertTrue(
            completed.descendants(matching: .any)["agent-reasoning-succeeded"]
                .waitForExistence(timeout: 15)
        )
        XCTAssertFalse(completed.staticTexts["先核对训练事实，再组织最终答复。"].exists)
        let disclosure = completed.buttons["思考过程"]
        XCTAssertTrue(disclosure.exists)
        XCTAssertEqual(disclosure.value as? String, "已收起")
        disclosure.tap()
        XCTAssertTrue(completed.staticTexts["先核对训练事实，再组织最终答复。"].exists)
        keepScreenshot(of: completed, named: "agent-reasoning-completed-expanded")
    }

    private func launch(stage: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = "agent-stages"
        app.launchEnvironment["SOMA_UI_AGENT_STAGE"] = stage
        app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = "dark"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        return app
    }

    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
