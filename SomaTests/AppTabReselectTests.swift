@testable import Soma
import XCTest

final class AppTabReselectTests: XCTestCase {
    func testSwitchingTabsRequestsOnlyASelectionChange() {
        XCTAssertEqual(
            AppTabReselect.effect(
                selected: .coach,
                incoming: .training,
                isSelectedTabAtRoot: true
            ),
            .switchTo(.training)
        )
    }

    func testReselectingAnyRootTabDoesNothing() {
        for tab in [AppTab.coach, .training, .insights, .settings] {
            XCTAssertEqual(
                AppTabReselect.effect(
                    selected: tab,
                    incoming: tab,
                    isSelectedTabAtRoot: true
                ),
                .noAction
            )
        }
    }

    func testReselectingCoachAwayFromRootStillDoesNothing() {
        XCTAssertEqual(
            AppTabReselect.effect(
                selected: .coach,
                incoming: .coach,
                isSelectedTabAtRoot: false
            ),
            .noAction
        )
    }

    func testReselectingNonCoachTabAwayFromRootResetsOnlyThatStack() {
        for tab in [AppTab.training, .insights, .settings] {
            XCTAssertEqual(
                AppTabReselect.effect(
                    selected: tab,
                    incoming: tab,
                    isSelectedTabAtRoot: false
                ),
                .resetStack(tab)
            )
        }
    }

    @MainActor
    func testNavigationStateOnlyMarksVisibleSelectedRootAsPushed() {
        let state = AppTabNavigationState()

        state.selectionWillChange(to: .training)
        state.rootDidDisappear(.coach)
        XCTAssertTrue(state.isAtRoot(.coach))

        state.rootDidDisappear(.training)
        XCTAssertFalse(state.isAtRoot(.training))

        state.rootDidAppear(.training)
        XCTAssertTrue(state.isAtRoot(.training))
    }
}
