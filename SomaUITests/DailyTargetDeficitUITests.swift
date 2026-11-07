import XCTest

final class DailyTargetDeficitUITests: XCTestCase {
    func testFatLossPreferenceSavesReopensAndUpdatesRecommendationInLight() throws {
        try verifyPreference(goalTitle: "减脂", appearance: "light", largeType: false)
    }

    func testFatLossPreferenceSavesReopensAndUpdatesRecommendationInDarkLargeType() throws {
        try verifyPreference(goalTitle: "减脂", appearance: "dark", largeType: true)
    }

    func testRecompositionPreferenceSavesReopensAndUpdatesRecommendationInLight() throws {
        try verifyPreference(goalTitle: "增肌减脂", appearance: "light", largeType: false)
    }

    func testRecompositionPreferenceSavesReopensAndUpdatesRecommendationInDarkLargeType() throws {
        try verifyPreference(goalTitle: "增肌减脂", appearance: "dark", largeType: true)
    }

    private func verifyPreference(goalTitle: String, appearance: String, largeType: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PROGRESS_FIXTURE"] = "1"
        app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
        if largeType {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        openBodyInfo(app)
        let goal = app.buttons["fitnessGoalPicker"]
        reveal(goal, in: app)
        goal.tap()
        app.buttons[goalTitle].tap()
        let field = app.textFields["dailyTargetDeficitField"]
        reveal(field, in: app)
        XCTAssertEqual(field.value as? String, "400")
        app.navigationBars["身体信息"].buttons["保存"].tap()

        app.tabBars.buttons["进展"].tap()
        let ring = app.buttons["progress-calories-ring-breakdown"]
        reveal(ring, in: app)
        let recommendation = NSPredicate(format: "label CONTAINS %@", "推荐摄入 ")
        expectation(for: recommendation, evaluatedWith: ring)
        waitForExpectations(timeout: 10)
        let targetText = try XCTUnwrap(ring.label.components(separatedBy: "推荐摄入 ").last?.components(separatedBy: " ").first)
        let originalTarget = try XCTUnwrap(Int(targetText.replacingOccurrences(of: ",", with: "")))

        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["身体信息"].waitForExistence(timeout: 5))
        reveal(field, in: app)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        XCTAssertFalse(app.navigationBars["身体信息"].buttons["保存"].isEnabled)
        field.typeText("600")
        app.navigationBars["身体信息"].buttons["保存"].tap()
        XCTAssertFalse(app.navigationBars["身体信息"].buttons["保存"].exists)
        app.navigationBars["身体信息"].buttons.element(boundBy: 0).tap()
        app.buttons["身体信息"].tap()
        reveal(field, in: app)
        XCTAssertEqual(field.value as? String, "600")
        keep(app, name: "daily-deficit-settings-\(goalTitle)-\(appearance)-large-\(largeType)")
        if goalTitle == "增肌减脂", !largeType {
            reveal(goal, in: app)
            goal.tap()
            app.buttons["减脂"].tap()
            reveal(field, in: app)
            XCTAssertEqual(field.value as? String, "600")
            app.navigationBars["身体信息"].buttons["保存"].tap()
            reveal(goal, in: app)
            goal.tap()
            app.buttons["增肌减脂"].tap()
            reveal(field, in: app)
            XCTAssertEqual(field.value as? String, "600")
            app.navigationBars["身体信息"].buttons["保存"].tap()
        }

        app.tabBars.buttons["进展"].tap()
        reveal(ring, in: app)
        let expectedTarget = (originalTarget - 200).formatted(.number.precision(.fractionLength(0)))
        let updated = NSPredicate(format: "label CONTAINS %@", "推荐摄入 \(expectedTarget) ")
        expectation(for: updated, evaluatedWith: ring)
        waitForExpectations(timeout: 10)
        let caption = app.descendants(matching: .any)["progress-energy-balance-caption"].firstMatch
        reveal(caption, in: app)
        XCTAssertTrue((caption.value as? String ?? "").contains("仍可摄入 0 千卡"))
        keep(app, name: "daily-deficit-600-\(goalTitle)-\(appearance)-large-\(largeType)")
        if goalTitle == "增肌减脂", !largeType {
            app.tabBars.buttons["设置"].tap()
            reveal(field, in: app)
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "0")
            app.navigationBars["身体信息"].buttons["保存"].tap()
            app.navigationBars["身体信息"].buttons.element(boundBy: 0).tap()
            app.buttons["身体信息"].tap()
            reveal(field, in: app)
            XCTAssertEqual(field.value as? String, "0")
            keep(app, name: "daily-deficit-settings-zero-recomposition-light")
            app.tabBars.buttons["进展"].tap()
            reveal(ring, in: app)
            let zeroTarget = (originalTarget + 400).formatted(.number.precision(.fractionLength(0)))
            expectation(for: NSPredicate(format: "label CONTAINS %@", "推荐摄入 \(zeroTarget) "), evaluatedWith: ring)
            waitForExpectations(timeout: 10)
            keep(app, name: "daily-deficit-zero-recomposition-light")
        }
    }

    private func keep(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func openBodyInfo(_ app: XCUIApplication) {
        app.tabBars.buttons["设置"].tap()
        app.buttons["身体信息"].tap()
        XCTAssertTrue(app.navigationBars["身体信息"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 10 where !element.isHittable {
            if element.exists, element.frame.minY < app.navigationBars.firstMatch.frame.maxY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }
}
