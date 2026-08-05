@testable import Soma
import XCTest

final class AgentTurnDisclosureTests: XCTestCase {
    func testOnlyLongToolResultsNeedDisclosure() {
        // 字数阈值 200：「结果」2 字 × 100 = 200，未超过则不展开。
        XCTAssertFalse(AgentToolResultDisclosure.shouldCollapse(
            String(repeating: "结果", count: 100)
        ))
        XCTAssertTrue(AgentToolResultDisclosure.shouldCollapse(
            String(repeating: "结果", count: 101)
        ))
        XCTAssertFalse(AgentToolResultDisclosure.shouldCollapse(
            "第一行\n第二行\n第三行\n第四行"
        ))
        XCTAssertTrue(AgentToolResultDisclosure.shouldCollapse(
            "第一行\n第二行\n第三行\n第四行\n第五行"
        ))
    }
}
