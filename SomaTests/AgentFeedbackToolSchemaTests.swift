@testable import Soma
import XCTest

final class AgentFeedbackToolSchemaTests: XCTestCase {
    func testSubmitFeedbackSchemaHasNoModelControlledArguments() throws {
        let data = try JSONEncoder().encode(
            AgentToolName.submitFeedback.chatTool
        )
        let tool = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let function = try XCTUnwrap(tool["function"] as? [String: Any])
        let parameters = try XCTUnwrap(
            function["parameters"] as? [String: Any]
        )

        XCTAssertEqual(function["name"] as? String, "submit_feedback")
        XCTAssertEqual((parameters["properties"] as? [String: Any])?.count, 0)
        XCTAssertEqual(parameters["additionalProperties"] as? Bool, false)
    }
}
