@testable import Soma
import XCTest

final class AppTabReselectTests: XCTestCase {
    func testSwitchingTabsRequestsOnlyASelectionChange() {
        XCTAssertEqual(
            AppTabReselect.effect(selected: .coach, incoming: .training),
            .switchTo(.training)
        )
    }

    func testReselectingTabRequestsOnlyAStackReset() {
        XCTAssertEqual(
            AppTabReselect.effect(selected: .insights, incoming: .insights),
            .resetStack(.insights)
        )
    }
}
