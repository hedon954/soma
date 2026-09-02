import XCTest

final class RecordOptimizationUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testWorkoutCardUsesExerciseDefinitionInLightTheme() {
        let app = launchRecordFixture(appearance: "light")
        assertWorkoutCard(in: app)
        keepScreenshot(of: app, named: "record-optimizations-light")
    }

    func testWorkoutCardUsesExerciseDefinitionInDarkTheme() {
        let app = launchRecordFixture(appearance: "dark")
        assertWorkoutCard(in: app)
        keepScreenshot(of: app, named: "record-optimizations-dark")
    }

    func testSingleSideLabelAppearsOnlyOnceInWorkoutHeader() {
        for (laterality, headerLabel, innerLabel) in [
            ("left", "仅左", "左"),
            ("right", "仅右", "右")
        ] {
            let app = launchRecordFixture(
                appearance: "light",
                workoutLaterality: laterality
            )
            let list = app.scrollViews["coach-message-list"]
            XCTAssertTrue(list.waitForExistence(timeout: 15))
            let title = app.descendants(matching: .any)["inline-record-title"].firstMatch
            for _ in 0 ..< 5 where !title.exists {
                list.swipeDown()
            }
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertEqual(
                app.staticTexts.matching(
                    NSPredicate(format: "label == %@", headerLabel)
                ).count,
                1
            )
            XCTAssertFalse(app.staticTexts[innerLabel].exists)
            app.terminate()
        }
    }

    func testLongWorkoutNameRemainsVisible() {
        let exerciseName = "超长动作名称哑铃交替保加利亚分腿深蹲"
        let app = launchRecordFixture(
            appearance: "light",
            workoutName: exerciseName
        )
        let list = app.scrollViews["coach-message-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        let title = app.descendants(matching: .any)["inline-record-title"].firstMatch
        for _ in 0 ..< 5 where !title.exists {
            list.swipeDown()
        }
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(title.frame.height, 36, "长动作名应获得完整多行空间而不是被截断")
        keepScreenshot(of: app, named: "record-optimizations-long-workout-name")
    }

    func testResumableWorkoutCardIsCompleteAndUsesIconOnlyDeleteAction() {
        let app = launchRecordFixture(appearance: "dark")
        app.tabBars.buttons["训练"].tap()

        let card = app.descendants(matching: .any)
            .matching(identifier: "training-resume-card")
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(
            card.frame.height,
            126,
            "继续训练卡必须使用真实内容高度，不能被旧固定高度截掉底部进度"
        )

        card.swipeLeft()
        let delete = app.buttons["删除未完成训练"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertLessThan(delete.frame.width, 100, "删除区只显示系统垃圾桶，不应被文字撑宽")
        XCTAssertFalse(app.staticTexts["删除未完成训练"].exists)
        keepScreenshot(of: app, named: "training-resume-icon-only-delete")
    }

    func testAssistantMetadataActionsDoNotOverlapTimestamp() {
        let app = launchRecordFixture(appearance: "dark")

        let trace = app.buttons["查看这条回复的执行日志"]
        XCTAssertTrue(trace.waitForExistence(timeout: 15))
        let feedbacks = app.buttons
            .matching(NSPredicate(format: "label == %@", "反馈这条 AI 回复"))
            .allElementsBoundByIndex
        let feedback = feedbacks.min {
            abs($0.frame.midY - trace.frame.midY) < abs($1.frame.midY - trace.frame.midY)
        }
        XCTAssertNotNil(feedback)

        let timestamps = app.staticTexts
            .matching(identifier: "assistant-message-timestamp")
            .allElementsBoundByIndex
        let timestamp = timestamps.min {
            abs($0.frame.midY - trace.frame.midY) < abs($1.frame.midY - trace.frame.midY)
        }
        XCTAssertNotNil(timestamp)
        if let timestamp {
            XCTAssertLessThanOrEqual(timestamp.frame.maxX, trace.frame.minX + 0.5)
            XCTAssertLessThanOrEqual(
                trace.frame.minX - timestamp.frame.maxX,
                24,
                "时间和日志按钮的可见间距应保持紧凑"
            )
        }
        if let feedback {
            XCTAssertLessThanOrEqual(trace.frame.maxX, feedback.frame.minX + 0.5)
            XCTAssertLessThanOrEqual(
                feedback.frame.minX - trace.frame.maxX,
                20,
                "两个图标的可见间距应保持紧凑"
            )
            XCTAssertGreaterThanOrEqual(trace.frame.width, 44)
            XCTAssertGreaterThanOrEqual(feedback.frame.width, 44)
        }
        keepScreenshot(of: app, named: "assistant-metadata-no-overlap")
    }

    func testWorkoutFooterKeepsAddActionAndCaloriesOnOneLine() {
        let app = launchRecordFixture(appearance: "dark")
        revealWorkoutCard(in: app)
        let add = app.buttons["添加一组"].firstMatch
        let calories = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "预计消耗约 23 千卡")
        ).firstMatch

        XCTAssertTrue(add.waitForExistence(timeout: 15))
        XCTAssertTrue(calories.waitForExistence(timeout: 5))
        XCTAssertLessThan(abs(add.frame.midY - calories.frame.midY), 4)
        XCTAssertLessThan(add.frame.maxX, calories.frame.minX)
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
    }

    func testProgressEnergyUsesCurrentScopeAndLabelsWorkoutOnlyFallback() {
        let app = launchRecordFixture(appearance: "light")
        app.tabBars.buttons["进展"].tap()

        XCTAssertTrue(app.staticTexts["今日能量"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["已记录摄入"].exists)
        XCTAssertTrue(app.staticTexts["截至当前总消耗"].exists)
        XCTAssertTrue(app.staticTexts["静息消耗"].exists)
        XCTAssertTrue(app.staticTexts["训练消耗"].exists)
        XCTAssertFalse(app.staticTexts["活动消耗"].exists)
        XCTAssertTrue(app.staticTexts["截至当前能量差"].exists)
        XCTAssertFalse(app.staticTexts["全天总消耗预估"].exists)
        keepScreenshot(of: app, named: "progress-current-energy-scope")
    }

    func testWorkoutDetailShowsMuscleMapWithoutDisclosure() {
        let app = launchRecordFixture(appearance: "dark")
        app.tabBars.buttons["进展"].tap()

        let workout = app.staticTexts["单杠悬吊"].firstMatch
        XCTAssertTrue(workout.waitForExistence(timeout: 15))
        workout.tap()
        XCTAssertTrue(app.navigationBars["单杠悬吊"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["受力图"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["受力图"].exists, "受力图不得再由折叠按钮控制")
        keepScreenshot(of: app, named: "workout-detail-muscle-map-expanded")
    }

    func testCompletedSessionReviewReusesRecentWorkoutRow() {
        let app = launchRecordFixture(appearance: "dark")
        app.tabBars.buttons["训练"].tap()

        let session = app.staticTexts["虚构复盘计划"]
        for _ in 0 ..< 4 where !session.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.navigationBars["训练复盘"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["虚构复盘深蹲"].exists)
        XCTAssertTrue(app.staticTexts["5组 × 5次 · 50kg"].exists)
        XCTAssertTrue(app.staticTexts["1,250 kg"].exists)
        XCTAssertFalse(app.staticTexts["5组已确认"].exists)
        keepScreenshot(of: app, named: "completed-session-reuses-progress-row")
    }

    func testWorkoutHistoryDayHeaderSharesTheWholeDay() {
        let app = launchRecordFixture(appearance: "dark")
        let share = revealWorkoutDayShare(in: app)
        keepScreenshot(of: app, named: "workout-history-day-share-button")
        share.tap()

        XCTAssertTrue(app.navigationBars["分享训练"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["训练分享海报"]
                .waitForExistence(timeout: 10)
        )
        keepScreenshot(of: app, named: "workout-history-day-share")
    }

    func testWorkoutHistoryDayShareButtonInLightTheme() {
        let app = launchRecordFixture(appearance: "light")
        _ = revealWorkoutDayShare(in: app)
        keepScreenshot(of: app, named: "workout-history-day-share-button-light")
    }

    func testSettingsAreFlattenedAndBirthDateHasNoToggle() {
        let app = launchEmptyApp(appearance: "light")
        let settings = app.tabBars.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["更多"].exists)
        XCTAssertTrue(app.staticTexts["任务进度与通知"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["后台持续处理"].exists)
        XCTAssertTrue(app.staticTexts["数据与备份"].exists)

        app.buttons["身体信息"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["身体信息"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["填写出生日期"].exists)
        XCTAssertTrue(app.staticTexts["称呼"].exists)
        XCTAssertTrue(app.staticTexts["出生日期"].exists)
        keepScreenshot(of: app, named: "body-info-without-birth-toggle")

        let nameField = app.textFields["可选"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(nameField.isHittable)
        XCTAssertLessThan(nameField.frame.maxY, keyboard.frame.minY)
        keepScreenScreenshot(named: "body-info-keyboard-safe-area")
    }

    func testExerciseContentEditorOpensWithoutBlocking() {
        let app = launchRecordFixture(
            appearance: "light",
            exerciseStressCount: 500
        )
        app.tabBars.buttons["进展"].tap()

        XCTAssertTrue(
            app.scrollViews["insights-content"].waitForExistence(timeout: 20)
        )
        let exerciseLibrary = app.descendants(matching: .any)
            .matching(identifier: "exercise-library-link")
            .firstMatch
        for _ in 0 ..< 5 where !exerciseLibrary.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(exerciseLibrary.waitForExistence(timeout: 5))
        exerciseLibrary.tap()

        XCTAssertTrue(app.navigationBars["动作库"].waitForExistence(timeout: 5))
        let exercise = app.descendants(matching: .any)
            .matching(identifier: "exercise-link-0000 编辑回归动作")
            .firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 5))
        exercise.tap()
        XCTAssertTrue(app.navigationBars["0000 编辑回归动作"].waitForExistence(timeout: 5))

        app.buttons["编辑与管理"].tap()
        app.buttons["编辑动作"].tap()

        XCTAssertTrue(
            app.navigationBars["编辑动作"].waitForExistence(timeout: 2),
            "动作编辑页不应因同步加载合并候选而阻塞"
        )
        XCTAssertTrue(app.textFields["动作名称"].isHittable)
    }

    private func launchRecordFixture(
        appearance: String,
        exerciseStressCount: Int? = nil,
        workoutLaterality: String? = nil,
        workoutName: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FIXTURE"] = "record-optimizations"
        app.launchEnvironment["SOMA_UI_PERFORMANCE_FAST_STREAM"] = "1"
        app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
        if let exerciseStressCount {
            app.launchEnvironment["SOMA_UI_EXERCISE_STRESS_COUNT"] =
                String(exerciseStressCount)
        }
        if let workoutLaterality {
            app.launchEnvironment["SOMA_UI_WORKOUT_LATERALITY"] = workoutLaterality
        }
        if let workoutName {
            app.launchEnvironment["SOMA_UI_WORKOUT_NAME"] = workoutName
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        return app
    }

    private func launchEmptyApp(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        return app
    }

    private func assertWorkoutCard(in app: XCUIApplication) {
        revealWorkoutCard(in: app)
        let title = app.descendants(matching: .any)["inline-record-title"].firstMatch
        XCTAssertEqual(title.value as? String, "单杠悬吊")
        let targetKind = app.staticTexts["时长"]
        let side = app.staticTexts["双侧同时"]
        let save = app.buttons["自动保存已就绪"]
        let delete = app.buttons["删除"]
        XCTAssertTrue(targetKind.exists)
        XCTAssertEqual(
            app.staticTexts.matching(
                NSPredicate(format: "label == %@", "双侧同时")
            ).count,
            1
        )
        let headerCenters = [title, targetKind, side, save, delete].map(\.frame.midY)
        XCTAssertLessThan(
            (headerCenters.max() ?? 0) - (headerCenters.min() ?? 0),
            3,
            "动作名、目标、侧别、保存和删除必须位于同一条水平中线"
        )
        XCTAssertEqual(app.textFields["时长"].value as? String, "20 秒")
        XCTAssertEqual(app.textFields["外部重量"].value as? String, "自重")
        XCTAssertEqual(app.textFields["间歇"].value as? String, "30 秒")
        XCTAssertTrue(
            app.descendants(matching: .any)["workout-run-count-3"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["workout-compact-inline-run"].exists
        )
        XCTAssertTrue(save.exists)
        XCTAssertTrue(delete.exists)
        XCTAssertFalse(app.images["已锁定"].exists)
        XCTAssertFalse(app.staticTexts["A. 单杠悬吊"].exists)
        XCTAssertTrue(
            app.buttons["查看这条回复的执行日志"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["反馈这条 AI 回复"].exists)
    }

    private func revealWorkoutCard(in app: XCUIApplication) {
        let list = app.scrollViews["coach-message-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        let title = app.descendants(matching: .any)["inline-record-title"].firstMatch
        for _ in 0 ..< 5 where !title.exists {
            list.swipeDown()
        }
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }

    private func revealWorkoutDayShare(in app: XCUIApplication) -> XCUIElement {
        app.tabBars.buttons["进展"].tap()

        let history = app.buttons["训练记录"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        history.tap()
        XCTAssertTrue(app.navigationBars["训练记录"].waitForExistence(timeout: 5))

        let share = app.buttons.matching(identifier: "workout-day-share").firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(share.frame.width, 44)
        XCTAssertGreaterThanOrEqual(share.frame.height, 44)
        return share
    }

    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func keepScreenScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
