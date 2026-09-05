import XCTest

final class ProgressResourceLinksUITests: XCTestCase {
    private let titles = ["全部训练", "全部饮食", "身体记录", "足迹", "健身房", "动作库"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testDarkResourceGridAndDestinations() {
        let app = launch("dark")
        checkGrid(app, columns: 3)
        keep(app, "progress-resources-dark")
        for title in titles {
            let link = app.buttons[title].firstMatch
            reveal(link, in: app)
            link.tap()
            XCTAssertFalse(app.segmentedControls["progress-period-picker"].exists)
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
            XCTAssertTrue(app.segmentedControls["progress-period-picker"].waitForExistence(timeout: 5))
        }
    }

    func testLightResourceGrid() {
        let app = launch("light")
        checkGrid(app, columns: 3)
        keep(app, "progress-resources-light")
    }

    func testAccessibilityResourceGridUsesTwoColumns() {
        let app = launch("dark", largeType: true)
        checkGrid(app, columns: 2)
        for title in titles {
            let link = app.buttons[title].firstMatch
            reveal(link, in: app)
            XCTAssertEqual(link.label, title)
            XCTAssertGreaterThanOrEqual(link.frame.width, 44)
        }
        keep(app, "progress-resources-accessibility")
    }

    private func checkGrid(_ app: XCUIApplication, columns: Int) {
        reveal(app.buttons["动作库"].firstMatch, in: app)
        let frames = titles.map { app.buttons[$0].firstMatch.frame }
        for (index, frame) in frames.enumerated() {
            XCTAssertGreaterThanOrEqual(frame.height, 80, "入口应为完整卡片而非裸文字链接")
            XCTAssertEqual(frame.width, frames[0].width, accuracy: 1)
            if index % columns != 0 {
                XCTAssertEqual(frame.minY, frames[index - 1].minY, accuracy: 1)
                XCTAssertGreaterThanOrEqual(frame.minX - frames[index - 1].maxX, 8)
            }
            if index >= columns {
                XCTAssertGreaterThanOrEqual(frame.minY - frames[index - columns].maxY, 8)
            }
        }
    }

    private func launch(_ appearance: String, largeType: Bool = false) -> XCUIApplication {
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
        XCTAssertTrue(app.segmentedControls["progress-period-picker"].waitForExistence(timeout: 10))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 12 {
            if element.exists, element.isHittable {
                return
            }
            app.scrollViews["insights-content"].swipeUp()
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
