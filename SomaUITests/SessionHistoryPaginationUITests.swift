import XCTest

final class SessionHistoryPaginationUITests: XCTestCase {
    func testPagesRemainCachedAcrossDrawerSessionAndTabChanges() {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["SOMA_UI_TEST_PROCESS"] = "1"
            app.launchEnvironment["SOMA_UI_SESSION_HISTORY_FIXTURE"] = "1"
            app.launchEnvironment["SOMA_UI_TEST_APPEARANCE"] = appearance
            app.launch()
            let historyButton = app.buttons["历史对话"]
            XCTAssertTrue(historyButton.waitForExistence(timeout: 15))
            historyButton.tap()
            let list = app.descendants(matching: .any)["coach-session-history"].firstMatch
            assertPage("count=14,fetches=1", list)
            let more = app.buttons["加载更早对话"]
            for _ in 0 ..< 10 where !more.isHittable {
                list.swipeUp()
            }
            XCTAssertTrue(more.isHittable)
            more.tap()
            assertPage("count=28,fetches=2", list)
            keep(app, "session-pages-\(appearance)")
            app.tabBars.buttons["进展"].tap()
            app.tabBars.buttons["教练"].tap()
            assertPage("count=28,fetches=2", list)
            let oldSession = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "虚构分页对话")).firstMatch
            for _ in 0 ..< 10 where !oldSession.isHittable {
                list.swipeDown()
            }
            XCTAssertTrue(oldSession.isHittable)
            oldSession.tap()
            historyButton.tap()
            assertPage("count=28,fetches=2", list)
            keep(app, "session-cache-return-\(appearance)")
            app.terminate()
        }
    }

    private func assertPage(_ value: String, _ list: XCUIElement) {
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: list)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
