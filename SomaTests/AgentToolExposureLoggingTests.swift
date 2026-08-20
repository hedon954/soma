@testable import Soma
import XCTest

/// PRD 033：每次 LLM 调用都要能查到实际绑定的工具清单。
final class AgentToolExposureLoggingTests: XCTestCase {
    func testExposedToolNamesRenderIntoReadableSummary() {
        let metadata = TraceSpanMetadata(AgentTraceText.jsonObject([
            "exposed_tool_names": ["create_meal", "list_meals"],
            "exposed_tool_count": 2
        ]))

        XCTAssertEqual(
            metadata.exposedToolSummary,
            "工具 2 个：create_meal、list_meals"
        )
    }

    func testOlderTracesWithoutNamesStillShowCount() {
        let metadata = TraceSpanMetadata(AgentTraceText.jsonObject([
            "exposed_tool_count": 7
        ]))

        XCTAssertEqual(metadata.exposedToolSummary, "工具 7 个")
    }

    func testTraceWithoutToolMetadataShowsNothing() {
        XCTAssertNil(TraceSpanMetadata(nil).exposedToolSummary)
        XCTAssertNil(
            TraceSpanMetadata(AgentTraceText.jsonObject(["stream": true]))
                .exposedToolSummary
        )
    }

    func testExposedToolNamesMatchTheResolvedToolList() {
        let shortcut = AgentInputShortcut(
            title: "饮食分析",
            toolNames: AgentToolExposurePolicy.toolNames(for: [.core, .meals])
        )
        let tools = AgentToolExposurePolicy.tools(selectedShortcut: shortcut)
        let state = AgentToolLoopState(
            messages: [],
            tools: tools.map(\.chatTool),
            exposedToolNames: tools.map(\.rawValue)
        )

        XCTAssertEqual(state.exposedToolNames.count, state.tools.count)
        XCTAssertTrue(state.exposedToolNames.contains(
            AgentToolName.createMeal.rawValue
        ))
        XCTAssertFalse(state.exposedToolNames.contains(
            AgentToolName.createWorkout.rawValue
        ))
    }
}
