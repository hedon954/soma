import XCTest

final class WorkoutShareUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLightPosterAndSaveAction() {
        assertSharePoster(appearance: "light", largeType: false)
    }

    func testDarkPosterAndSaveActionWithAccessibilityType() {
        assertSharePoster(appearance: "dark", largeType: true)
    }

    private func assertSharePoster(appearance: String, largeType: Bool) {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_PROGRESS_FIXTURE"] = "1"
        app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
        if largeType {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["进展"].tap()
        let picker = app.segmentedControls["progress-period-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        picker.buttons["日"].tap()
        let share = app.buttons["分享当天训练"]
        reveal(share, in: app)
        XCTAssertGreaterThanOrEqual(share.frame.height, 44)
        share.tap()
        XCTAssertTrue(app.navigationBars["分享训练"].waitForExistence(timeout: 5))
        let poster = app.descendants(matching: .any)["训练分享海报"].firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 10))
        XCTAssertTrue((poster.value as? String)?.contains("5次 × 5组") == true)
        keep(app, "workout-share-top-\(appearance)")
        let save = app.buttons["保存到相册"]
        reveal(save, in: app)
        XCTAssertTrue(save.isHittable)
        app.swipeUp()
        let privacy = app.staticTexts["海报在本机渲染，不含照片、视频或位置。"]
        reveal(privacy, in: app)
        keep(app, "workout-share-bottom-\(appearance)")
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.tabBars.buttons["进展"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["进展"].isSelected)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 8 where !element.isHittable {
            app.swipeUp()
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
