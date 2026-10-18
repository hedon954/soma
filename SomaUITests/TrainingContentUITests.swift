import XCTest

final class TrainingContentUITests: XCTestCase {
    func testDirectExerciseUsesRecentParametersAndSavesWithoutCourseInBothThemes() {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
            app.launchEnvironment["SOMA_UI_TRAINING_CONTENT_FIXTURE"] = "1"
            app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
            app.launch()
            let training = app.tabBars.buttons["训练"]
            XCTAssertTrue(training.waitForExistence(timeout: 20))
            training.tap()
            let create = app.buttons["新建训练计划"]
            XCTAssertTrue(create.waitForExistence(timeout: 10))
            create.tap()
            let name = app.textFields["计划名称"]
            XCTAssertTrue(name.waitForExistence(timeout: 10))
            name.tap()
            name.typeText("Fixture plan")
            app.swipeUp()
            let add = app.buttons["training-add-content-0"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            add.tap()
            let tabs = app.segmentedControls["training-content-tabs"]
            XCTAssertTrue(tabs.waitForExistence(timeout: 10))
            XCTAssertTrue(tabs.buttons["课程"].isSelected)
            tabs.buttons["动作"].tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap()
            search.typeText("虚构深蹲")
            app.buttons["虚构深蹲"].tap()
            let join = app.buttons["加入计划"]
            XCTAssertTrue(join.waitForExistence(timeout: 10))
            keep(app, "training-parameters-\(appearance)")
            join.tap()
            let save = app.navigationBars.buttons["保存"]
            XCTAssertTrue(save.waitForExistence(timeout: 10))
            keep(app, "training-composition-\(appearance)")
            save.tap()
            XCTAssertTrue(app.staticTexts["Fixture plan"].waitForExistence(timeout: 10))
            keep(app, "training-saved-\(appearance)")
            app.terminate()
        }
    }

    func testTabsReachCoursesAndPlansWithoutScrollingThroughExercises() {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
            app.launchEnvironment["SOMA_UI_TRAINING_CONTENT_FIXTURE"] = "1"
            app.launchEnvironment["SOMA_UI_TRAINING_PICKER_TABS_FIXTURE"] = "1"
            app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["训练"].waitForExistence(timeout: 20))
            app.tabBars.buttons["训练"].tap()
            app.buttons["新建训练计划"].tap()
            let add = app.buttons["training-add-content-0"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            add.tap()
            let tabs = app.segmentedControls["training-content-tabs"]
            XCTAssertTrue(tabs.waitForExistence(timeout: 10))
            XCTAssertTrue(tabs.buttons["课程"].isSelected)
            XCTAssertEqual(tabs.buttons.element(boundBy: 0).label, "课程")
            XCTAssertEqual(tabs.buttons.element(boundBy: 1).label, "动作")
            XCTAssertEqual(tabs.buttons.element(boundBy: 2).label, "计划")
            tabs.buttons["动作"].tap()
            keep(app, "training-picker-exercises-\(appearance)")
            tabs.buttons["课程"].tap()
            XCTAssertTrue(app.buttons["虚构课程"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["虚构引用计划"].exists)
            keep(app, "training-picker-courses-\(appearance)")
            tabs.buttons["计划"].tap()
            XCTAssertTrue(app.buttons["虚构引用计划"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["虚构课程"].exists)
            keep(app, "training-picker-plans-\(appearance)")
            let search = app.searchFields.firstMatch
            search.tap()
            search.typeText("missing")
            XCTAssertTrue(app.staticTexts["没有匹配的计划"].waitForExistence(timeout: 10))
            search.buttons.firstMatch.tap()
            app.buttons["虚构引用计划"].tap()
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            add.tap()
            let returnedTabs = app.segmentedControls["training-content-tabs"]
            XCTAssertTrue(returnedTabs.waitForExistence(timeout: 10))
            returnedTabs.buttons["课程"].tap()
            app.buttons["虚构课程"].tap()
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            keep(app, "training-picker-selections-\(appearance)")
            app.terminate()
        }
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
