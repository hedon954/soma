@testable import Soma
import XCTest

final class AgentChatPresentationTests: XCTestCase {
    func testSingleExerciseResultBecomesFriendlySummaryWithoutIdentifier() throws {
        let observation = try AgentTraceText.json([
            ExerciseNameReference(
                id: XCTUnwrap(UUID(uuidString: "E7061B11-1A7D-471A-B9C8-40EF6CC2575C")),
                name: "杠铃深蹲"
            )
        ])
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "读取动作库",
            name: "list_exercise_names",
            observation: observation
        ))

        XCTAssertEqual(presentation?.summary, "动作库中有 1 个动作：杠铃深蹲")
        XCTAssertEqual(presentation?.details, [])
        XCTAssertNil(presentation?.disclosureLabel)
    }

    func testManyExerciseResultsBecomeExpandableNameList() {
        let names = ["杠铃深蹲", "引体向上", "哑铃卧推", "罗马尼亚硬拉"]
        let observation = AgentTraceText.json(names.enumerated().map { index, name in
            ExerciseNameReference(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
                name: name
            )
        })
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "读取动作库",
            name: "list_exercise_names",
            observation: observation
        ))

        XCTAssertEqual(presentation?.summary, "动作库中有 4 个动作")
        XCTAssertEqual(presentation?.details, names)
        XCTAssertEqual(presentation?.disclosureLabel, "查看全部 4 个动作")
    }

    func testWorkoutQueryHidesIdentifiersAndFormatsBodyweight() {
        let observation = """
        [id:643DC70A-0E1E-4CC4-A8F0-D3EB2EC4853A] 2026年8月3日 引体向上，5组 × 5次 · 0kg，间歇 120 秒
        [id:F948F483-9CE2-4662-802F-050F0734762D] 2026年8月3日 杠铃深蹲，2组 × 5次 · 30kg，间歇 60 秒
        """
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "读取用户数据",
            name: "query_user_data",
            scope: "workouts",
            observation: observation
        ))

        XCTAssertEqual(presentation?.summary, "找到 2 条训练记录")
        XCTAssertEqual(presentation?.details, [
            "2026年8月3日 引体向上，5组 × 5次 · 自重，间歇 120 秒",
            "2026年8月3日 杠铃深蹲，2组 × 5次 · 30kg，间歇 60 秒"
        ])
        XCTAssertEqual(presentation?.disclosureLabel, "查看 2 条训练记录")
    }

    func testMutationSummaryHidesInternalRecordIdentifier() {
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "创建训练计划",
            name: "create_training_program",
            observation: "已创建训练计划 [id:888F4F29-7C5C-40DC-ACCB-A0AABC015F34]：基础力量训练。"
        ))

        XCTAssertEqual(presentation?.summary, "已创建训练计划：基础力量训练。")
        XCTAssertEqual(presentation?.details, [])
    }

    func testLongGenericResultKeepsCompleteTextBehindDisclosure() {
        let observation = String(repeating: "完整结果", count: 30)
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "读取用户数据",
            name: "query_user_data",
            observation: observation
        ))

        XCTAssertEqual(presentation?.summary, "操作已完成，可查看完整结果")
        XCTAssertEqual(presentation?.details, [observation])
        XCTAssertEqual(presentation?.disclosureLabel, "查看完整结果")
    }

    func testInternalFunctionMarkupIsRemovedFromChatText() {
        XCTAssertEqual(
            AgentVisibleTextSanitizer.sanitize(
                "<function=list_exercise_names> </function>\n</tool_call>"
            ),
            ""
        )
        XCTAssertEqual(
            AgentVisibleTextSanitizer.sanitize(
                "正在准备\n<function=list_exercise_names"
            ),
            "正在准备"
        )
        XCTAssertEqual(
            AgentVisibleTextSanitizer.sanitize("正常的教练回复"),
            "正常的教练回复"
        )
    }

    private func toolItem(
        title: String,
        name: String,
        scope: String? = nil,
        observation: String
    ) -> AgentTurnItem {
        let scopeJSON = scope.map { #", "scope": "\#($0)""# } ?? ""
        return AgentTurnItem(
            kind: .tool,
            status: .succeeded,
            title: title,
            input: #"{"name":"\#(name)","arguments":{"placeholder":true\#(scopeJSON)}}"#,
            output: AgentTraceText.json(AgentToolResult.success(observation))
        )
    }
}
