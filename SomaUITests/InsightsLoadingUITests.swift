import XCTest

final class InsightsLoadingUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFirstEntryLoadsAndRepeatedTabSwitchesKeepContentVisible() {
        runInsightsLoadingScenario(appearance: "light", repeatedSwitches: 3)
    }

    func testDarkAppearanceLoadsWithoutBlankState() {
        runInsightsLoadingScenario(appearance: "dark", repeatedSwitches: 1)
    }

    private func runInsightsLoadingScenario(
        appearance: String,
        repeatedSwitches: Int
    ) {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        tabBar.buttons["进展"].tap()

        let content = app.scrollViews["insights-content"]
        XCTAssertTrue(
            content.waitForExistence(timeout: 10),
            "首次进入进展后没有从 idle/loading 进入 loaded"
        )
        XCTAssertFalse(app.descendants(matching: .any)["insights-loading"].exists)
        keepScreenshot(of: app, named: "insights-loaded-\(appearance)")

        for _ in 0 ..< repeatedSwitches {
            tabBar.buttons["教练"].tap()
            tabBar.buttons["进展"].tap()
            XCTAssertTrue(
                content.waitForExistence(timeout: 3),
                "重复切回进展后不应卡在空白或永久 loading"
            )
        }
    }

    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
