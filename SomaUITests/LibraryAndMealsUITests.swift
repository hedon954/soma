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
