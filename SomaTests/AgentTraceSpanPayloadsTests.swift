@testable import Soma
import XCTest

final class AgentTraceSpanPayloadsTests: XCTestCase {
    func testModelSpanSectionsKeepToolsInputAndOutputOffTheTimeline() {
        let span = AgentTraceSpan(
            kind: .model,
            title: "LLM 推理",
            status: .succeeded,
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            input: String(repeating: "system prompt ", count: 80),
            output: "ok",
            metadata: #"{"exposed_tool_names":["create_meal","update_meal"]}"#
        )

        let sections = AgentTraceSpanPayloads.sections(
            for: span,
            metadata: TraceSpanMetadata(span.metadata)
        )

        XCTAssertEqual(sections.map(\.title), ["绑定工具", "入参", "返回", "元数据"])
        XCTAssertTrue(sections.contains { $0.title == "入参" && $0.value.count > 200 })
    }

    func testFailedToolKeepsErrorSection() {
        let span = AgentTraceSpan(
            kind: .tool,
            title: "create_meal",
            status: .failed,
            startedAt: Date(),
            endedAt: Date(),
            errorMessage: "参数缺少 name"
        )

        let sections = AgentTraceSpanPayloads.sections(
            for: span,
            metadata: TraceSpanMetadata(nil)
        )

        XCTAssertEqual(sections.map(\.title), ["错误"])
        XCTAssertTrue(sections[0].isError)
    }
}
