import XCTest

final class RootTabContractUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testRootKeepsAllFourTabsInProductOrder() {
        let app = XCUIApplication()
        app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15), "根 Tab Bar 未出现")

        let expectedLabels = ["教练", "训练", "进展", "设置"]
        XCTAssertEqual(tabBar.buttons.count, expectedLabels.count)
        XCTAssertEqual(
            tabBar.buttons.allElementsBoundByIndex.map(\.label),
            expectedLabels
        )
    }
}
