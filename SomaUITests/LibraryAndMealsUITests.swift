import XCTest

final class LibraryAndMealsUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testMealPrefixesAndLibraryFiltersInBothThemes() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            app.buttons["progress-intake-breakdown"].tap()
            let breakdown = app.scrollViews["progress-energy-breakdown-list"]
            XCTAssertTrue(breakdown.waitForExistence(timeout: 5))
            XCTAssertTrue(breakdown.staticTexts["早餐 · 虚构餐食 0"].exists)
            XCTAssertTrue(breakdown.staticTexts["晚餐 · 虚构餐食 3"].exists)
            keep(app, "meal-types-\(appearance)")
            app.tapCoordinate(x: 0.5, y: 0.15)
            openLibrary(app)
            let search = app.textFields["exercise-library-search"]
            search.tap()
            search.typeText("分类")
            keep(app, "library-search-keyboard-\(appearance)")
            app.buttons["exercise-category-region-胸部"].tap()
            let press = app.buttons["exercise-link-分类推举"]
            XCTAssertTrue(press.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["exercise-link-分类深蹲"].exists)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            app.buttons["exercise-category-region-muscle-胸大肌"].tap()
            keep(app, "library-sidebar-\(appearance)")
            press.tap()
            XCTAssertTrue(app.navigationBars["分类推举"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["exercise-category-region-muscle-胸大肌"].isSelected)
            app.buttons["exercise-category-all"].tap()
            XCTAssertTrue(app.buttons["exercise-link-分类深蹲"].waitForExistence(timeout: 5))
            app.buttons["exercise-category-region-颈部"].tap()
            XCTAssertTrue(app.staticTexts["没有符合条件的动作"].waitForExistence(timeout: 5))
            keep(app, "library-empty-\(appearance)")
            app.buttons["重置搜索与筛选"].tap()
            XCTAssertTrue(app.buttons["exercise-category-all"].isSelected)
            app.terminate()
        }
    }

    func testExerciseTrendsSwitchUnitsAndOpenSelectedRecordInBothThemes() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            openLibrary(app)
            app.buttons["exercise-category-region-胸部"].tap()
            let exercise = app.buttons["exercise-link-分类推举"]
            XCTAssertTrue(exercise.waitForExistence(timeout: 5))
            exercise.tap()
            let metric = app.segmentedControls["exercise-trend-metric"]
            for _ in 0 ..< 8 where !metric.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(metric.buttons["容量"].isSelected)
            let capacityChart = app.descendants(matching: .any)["exercise-capacity-trend"].firstMatch
            for _ in 0 ..< 3 where capacityChart.frame.midY >= app.tabBars.firstMatch.frame.minY {
                app.swipeUp()
            }
            capacityChart.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.42)).tap()
            let selected = app.descendants(matching: .any)["exercise-trend-selected-record"].firstMatch
            XCTAssertTrue(selected.waitForExistence(timeout: 5), capacityChart.debugDescription)
            let chart = app.descendants(matching: .any)["exercise-effort-trend"].firstMatch
            for (title, unit) in [("重量", "kg"), ("次数", "次"), ("时长", "秒")] {
                metric.buttons[title].tap()
                XCTAssertTrue(chart.waitForExistence(timeout: 5))
                XCTAssertEqual(chart.label, "训练\(title)趋势，单位\(unit)")
                XCTAssertFalse(selected.exists)
            }
            for _ in 0 ..< 3 where chart.frame.midY >= app.tabBars.firstMatch.frame.minY {
                app.swipeUp()
            }
            chart.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.42)).tap()
            XCTAssertTrue(selected.waitForExistence(timeout: 5), chart.debugDescription)
            keep(app, "exercise-trend-selection-\(appearance)")
            selected.tap()
            XCTAssertTrue(app.staticTexts["训练数据"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testCoachShortcutChipsSupportFullTapTargetsAndSelectionInBothThemes() {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["SOMA_UI_TEST_PROCESS": "1", "SOMA_UI_TEST_APPEARANCE": appearance]
            app.launch()
            let meal = app.buttons["快捷按钮：记录饮食"]
            let workout = app.buttons["快捷按钮：训练记录"]
            let review = app.buttons["快捷按钮：近期分析"]
            XCTAssertTrue(meal.waitForExistence(timeout: 10))
            for button in [meal, workout, review] {
                XCTAssertTrue(button.isHittable)
                XCTAssertGreaterThanOrEqual(button.frame.height + 0.01, 44)
                XCTAssertGreaterThanOrEqual(button.frame.width + 0.01, 44)
                XCTAssertEqual(button.value as? String, "未选择")
            }
            keep(app, "coach-shortcuts-outline-\(appearance)")
            meal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
            XCTAssertEqual(meal.value as? String, "已选择")
            XCTAssertTrue(meal.isSelected)
            workout.tap()
            XCTAssertEqual(meal.value as? String, "未选择")
            XCTAssertEqual(workout.value as? String, "已选择")
            keep(app, "coach-shortcuts-selected-\(appearance)")
            workout.tap()
            XCTAssertEqual(workout.value as? String, "未选择")
            app.terminate()
        }
    }

    func testMealShareCanIncludePhotoAndHideDateInBothThemes() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            let meal = app.staticTexts["虚构餐食 0"].firstMatch
            for _ in 0 ..< 10 where !meal.isHittable {
                app.scrollViews["insights-content"].swipeUp()
            }
            XCTAssertTrue(meal.isHittable)
            meal.tap()
            let share = app.buttons["分享饮食记录"]
            XCTAssertTrue(share.waitForExistence(timeout: 5))
            share.tap()
            let preview = app.images["饮食分享预览，虚构餐食 0"]
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            let initialHeight = preview.frame.height
            keep(app, "meal-share-no-photo-\(appearance)")
            let photo = app.switches["显示餐图"]
            XCTAssertEqual(photo.value as? String, "0")
            photo.tap()
            waitForFrame(of: preview) { $0.height > initialHeight + 100 }
            keep(app, "meal-share-photo-\(appearance)")
            let date = app.switches["显示日期"]
            XCTAssertEqual(date.value as? String, "1")
            date.tap()
            XCTAssertEqual(date.value as? String, "0")
            let systemShare = app.navigationBars["分享饮食"].buttons["分享"]
            XCTAssertTrue(systemShare.waitForExistence(timeout: 5))
            systemShare.tap()
            let saveImage = app.descendants(matching: .any)["保存图像"].firstMatch
            XCTAssertTrue(saveImage.waitForExistence(timeout: 5), app.debugDescription)
            keep(app, "meal-share-system-\(appearance)")
            app.tapCoordinate(x: 0.5, y: 0.88)
            XCTAssertFalse(saveImage.exists)
            app.navigationBars["分享饮食"].buttons["关闭"].tap()
            XCTAssertTrue(share.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    private func waitForFrame(of element: XCUIElement, matching condition: @escaping (CGRect) -> Bool) {
        let predicate = NSPredicate { _, _ in element.exists && condition(element.frame) }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5), .completed)
    }

    private func openLibrary(_ app: XCUIApplication) {
        let link = app.buttons["动作库"].firstMatch
        for _ in 0 ..< 15 {
            if link.exists, link.isHittable {
                break
            }
            app.scrollViews["insights-content"].swipeUp()
        }
        XCTAssertTrue(link.isHittable)
        link.tap()
        XCTAssertTrue(app.scrollViews["exercise-library-categories"].waitForExistence(timeout: 5))
    }

    private func launch(_ appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "SOMA_UI_TEST_PROCESS": "1", "SOMA_UI_PROGRESS_FIXTURE": "1",
            "SOMA_UI_LIBRARY_MEALS_FIXTURE": "1", "SOMA_UI_TEST_APPEARANCE": appearance
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["进展"].tap()
        XCTAssertTrue(app.buttons["progress-intake-breakdown"].waitForExistence(timeout: 10))
        return app
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIApplication {
    func tapCoordinate(x: CGFloat, y: CGFloat) {
        coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    }
}
