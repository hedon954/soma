@testable import Soma
import XCTest

final class AgentTurnDisclosureTests: XCTestCase {
    func testOnlyLongToolResultsNeedDisclosure() {
        XCTAssertFalse(AgentToolResultDisclosure.shouldCollapse(
            String(repeating: "结果", count: 40)
        ))
        XCTAssertTrue(AgentToolResultDisclosure.shouldCollapse(
            String(repeating: "结果", count: 41)
        ))
        XCTAssertFalse(AgentToolResultDisclosure.shouldCollapse(
            "第一行\n第二行\n第三行\n第四行"
        ))
        XCTAssertTrue(AgentToolResultDisclosure.shouldCollapse(
            "第一行\n第二行\n第三行\n第四行\n第五行"
        ))
    }
}
