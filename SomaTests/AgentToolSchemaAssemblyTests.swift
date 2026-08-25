@testable import Soma
import SwiftOpenAI
import XCTest

final class AgentToolSchemaAssemblyTests: XCTestCase {
    func testNativeToolCallDeltasAssembleIntoLocalCall() throws {
        var accumulator = AgentStreamingToolCall()
        accumulator.append(ToolCall(
            index: 0,
            id: "call_1",
            function: FunctionCall(arguments: #"{"limit":"#, name: "list_workouts")
        ))
        accumulator.append(ToolCall(
            index: 0,
            id: nil,
            function: FunctionCall(arguments: #"5}"#, name: "")
        ))

        let resolved = try accumulator.resolved(fallbackID: "fallback")

        XCTAssertEqual(resolved.native.id, "call_1")
        XCTAssertEqual(resolved.local.name, .listWorkouts)
        XCTAssertEqual(resolved.local.arguments.limit, 5)
    }

    func testNativeToolsAreRegisteredWithJSONSchema() throws {
        let tools = AgentToolName.allCases.map(\.chatTool)
        let data = try JSONEncoder().encode(tools)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let names = json.compactMap {
            ($0["function"] as? [String: Any])?["name"] as? String
        }

        XCTAssertEqual(Set(names), Set(AgentToolName.allCases.map(\.rawValue)))
        XCTAssertTrue(names.contains("create_workout"))
        XCTAssertTrue(names.contains("update_workout"))
        XCTAssertTrue(names.contains("update_meal"))
        XCTAssertTrue(names.contains("update_body"))
        XCTAssertTrue(names.contains("delete_workout"))
        XCTAssertTrue(names.contains("load_skill"))
        XCTAssertTrue(names.contains("list_programs"))
        XCTAssertTrue(names.contains("get_program"))
        XCTAssertTrue(names.contains("delete_program"))
        XCTAssertTrue(names.contains("start_program"))
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(encoded.contains("set_entries"))
        XCTAssertTrue(encoded.contains("external_weight_kg"))
    }
}
