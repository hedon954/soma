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

    func testManyExerciseResultsShowNamesDirectly() {
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

        XCTAssertEqual(
            presentation?.summary,
            "动作库中有 4 个动作：杠铃深蹲、引体向上、哑铃卧推、罗马尼亚硬拉"
        )
        XCTAssertEqual(presentation?.details, [])
        XCTAssertNil(presentation?.disclosureLabel)
    }

    func testWorkoutQueryShowsRecordsDirectlyWithoutIdentifiers() {
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

        XCTAssertEqual(
            presentation?.summary,
            "2026年8月3日 引体向上，5组 × 5次 · 自重，间歇 120 秒\n"
                + "2026年8月3日 杠铃深蹲，2组 × 5次 · 30kg，间歇 60 秒"
        )
        XCTAssertEqual(presentation?.details, [])
        XCTAssertNil(presentation?.disclosureLabel)
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

    func testLongGenericResultShowsTextWithExpandDisclosure() {
        let observation = String(repeating: "完整结果", count: 60)
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "读取用户数据",
            name: "query_user_data",
            observation: observation
        ))

        XCTAssertEqual(presentation?.summary, observation)
        XCTAssertEqual(presentation?.details, [])
        XCTAssertEqual(presentation?.disclosureLabel, "展开")
    }

    func testShortResultDoesNotShowExpandDisclosure() {
        let observation = "已记录训练：杠铃深蹲，4 组 × 8 次 · 60kg。"
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "记录训练",
            name: "record_workout",
            observation: observation
        ))

        XCTAssertEqual(presentation?.summary, observation)
        XCTAssertEqual(presentation?.details, [])
        XCTAssertNil(presentation?.disclosureLabel)
        XCTAssertFalse(AgentToolResultDisclosure.shouldCollapse(observation))
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
