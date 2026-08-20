@testable import Soma
import XCTest

final class AppTabReselectTests: XCTestCase {
    func testReselectingTheSameTabIssuesANewStackID() {
        let current = UUID()
        let next = AppTabReselect.stackID(
            selected: .insights,
            incoming: .insights,
            current: current
        )
        XCTAssertNotEqual(next, current)
    }

    func testSwitchingTabsKeepsTheIncomingStackID() {
        let current = UUID()
        let next = AppTabReselect.stackID(
            selected: .coach,
            incoming: .insights,
            current: current
        )
        XCTAssertEqual(next, current)
    }
}
