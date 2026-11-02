import XCTest

final class EnergySystemUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testEnergyEvidenceFactsAndTrainingLinkInBothThemes() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            openSources(app)
            keep(app, "energy-sources-\(appearance)")
            let link = app.buttons["同场训练关联"]
            reveal(link, in: app)
            link.tap()
            XCTAssertTrue(app.navigationBars["同场训练关联"].waitForExistence(timeout: 5))
            app.buttons["energy-training-association"].tap()
            let candidate = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "虚构 COROS")).firstMatch
            XCTAssertTrue(candidate.waitForExistence(timeout: 5))
            candidate.tap()
            if app.navigationBars["同一场健康训练"].exists {
                app.navigationBars["同一场健康训练"].buttons.element(boundBy: 0).tap()
            }
            XCTAssertTrue(app.navigationBars["同场训练关联"].waitForExistence(timeout: 5))
            keep(app, "energy-linked-\(appearance)")
            app.navigationBars["同场训练关联"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["能量依据"].waitForExistence(timeout: 5))
            let facts = app.buttons["生活与记录确认"]
            reveal(facts, in: app)
            facts.tap()
            XCTAssertTrue(app.buttons["当前生活情况"].waitForExistence(timeout: 5))
            app.buttons["当前生活情况"].tap()
            XCTAssertTrue(app.navigationBars["编辑已记录事实"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["保存"].exists)
            let hours = app.textFields["每工作日工时"]
            XCTAssertEqual(hours.label, "每工作日工时")
            hours.tap()
            XCTAssertFalse(app.buttons["保存"].exists)
            keep(app, "energy-number-keyboard-\(appearance)")
            let commuting = app.textFields["通勤方式"]
            commuting.tap()
            commuting.typeText(" Test")
            XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 3))
            keep(app, "energy-edit-keyboard-\(appearance)")
            app.buttons["保存"].tap()
            XCTAssertTrue(app.navigationBars["生活与记录确认"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let history = app.buttons["系数与调整历史"]
            reveal(history, in: app)
            history.tap()
            XCTAssertTrue(app.switches["暂停自动校准"].waitForExistence(timeout: 5))
            app.switches["暂停自动校准"].tap()
            keep(app, "energy-history-\(appearance)")
            app.terminate()
        }
    }

    func testEnergyFactsAtAccessibilitySizeRemainEditableAndScrollable() {
        let app = launch("dark", large: true)
        openSources(app)
        let facts = app.buttons["生活与记录确认"]
        reveal(facts, in: app)
        facts.tap()
        let current = app.buttons["当前生活情况"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        current.tap()
        let housework = app.textFields["平均每日家务分钟"]
        reveal(housework, in: app)
        housework.tap()
        keep(app, "energy-facts-large-keyboard")
        XCTAssertTrue(housework.isHittable)
    }

    func testFrozenDailyAndCalibrationInputsRemainReviewable() {
        let app = launch("dark")
        openSources(app)
        let history = app.buttons["系数与调整历史"]
        reveal(history, in: app)
        history.tap()
        let row = app.buttons["energy-history-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.navigationBars["调整依据"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["有效系数"].exists)
        keep(app, "energy-frozen-daily-dark")
        app.navigationBars["调整依据"].buttons.element(boundBy: 0).tap()
        app.buttons["长期调整"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let inputs = app.buttons["冻结的每日依据"]
        reveal(inputs, in: app)
        inputs.tap()
        let day = app.buttons["energy-review-day"].firstMatch
        reveal(day, in: app)
        day.tap()
        XCTAssertTrue(app.navigationBars["每日评估依据"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["采用摄入"].exists)
        keep(app, "energy-frozen-calibration-day-dark")
    }

    private func launch(_ appearance: String, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["SOMA_UI_TEST_PROCESS": "1", "SOMA_UI_TEST_APPEARANCE": appearance,
                                 "SOMA_UI_PROGRESS_FIXTURE": "1", "SOMA_UI_DAILY_ACTIVITY_FIXTURE": "1", "SOMA_UI_ENERGY_FIXTURE": "1"]
        app.launchArguments = ["-data.activeSpace", "demo"]
        if large {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let progress = app.descendants(matching: .any)["进展"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 20))
        progress.tap()
        return app
    }

    private func openSources(_ app: XCUIApplication) {
        let picker = app.segmentedControls["progress-period-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        picker.buttons["日"].tap()
        let header = app.buttons["饮食与能量，查看估算依据"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        header.tap()
        XCTAssertTrue(app.navigationBars["能量依据"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 16 {
            if element.exists, element.isHittable {
                return
            }
            if element.exists, element.frame.minY < app.navigationBars.firstMatch.frame.maxY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
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
