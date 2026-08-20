@testable import Soma
import XCTest

final class AgentChatPresentationTests: XCTestCase {
    func testSingleExerciseResultBecomesFriendlySummaryWithoutIdentifier() {
        let observation = AgentTraceText.json([
            ExerciseNameReference(
                id: 41,
                name: "杠铃深蹲"
            )
        ])
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "读取动作库",
            name: "search_exercises",
            observation: observation
        ))

        XCTAssertEqual(presentation?.summary, "动作库中有 1 个动作：杠铃深蹲")
        XCTAssertEqual(presentation?.details, [String]())
        XCTAssertNil(presentation?.disclosureLabel)
        XCTAssertEqual(presentation?.defaultsCollapsed, true)
    }

    func testManyExerciseResultsShowNamesDirectly() {
        let names = ["杠铃深蹲", "引体向上", "哑铃卧推", "罗马尼亚硬拉"]
        let observation = AgentTraceText.json(names.enumerated().map { index, name in
            ExerciseNameReference(
                id: Int64(index + 1),
                name: name
            )
        })
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "读取动作库",
            name: "search_exercises",
            observation: observation
        ))

        XCTAssertEqual(presentation?.summary, "动作库中有 4 个动作")
        XCTAssertEqual(presentation?.details, names)
        XCTAssertEqual(presentation?.disclosureLabel, "展开")
        XCTAssertEqual(presentation?.defaultsCollapsed, true)
    }

    func testWorkoutQueryShowsRecordsDirectlyWithoutIdentifiers() {
        let observation = """
        [id:643DC70A-0E1E-4CC4-A8F0-D3EB2EC4853A] 2026年8月3日 引体向上，5组 × 5次 · 0kg，间歇 120 秒
        [id:F948F483-9CE2-4662-802F-050F0734762D] 2026年8月3日 杠铃深蹲，2组 × 5次 · 30kg，间歇 60 秒
        """
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "读取用户数据",
            name: "list_workouts",
            scope: "workouts",
            observation: observation
        ))

        XCTAssertEqual(presentation?.summary, "找到 2 条训练记录")
        XCTAssertEqual(
            presentation?.details,
            [
                "2026年8月3日 引体向上，5组 × 5次 · 自重，间歇 120 秒",
                "2026年8月3日 杠铃深蹲，2组 × 5次 · 30kg，间歇 60 秒"
            ]
        )
        XCTAssertEqual(presentation?.disclosureLabel, "展开")
        XCTAssertEqual(presentation?.defaultsCollapsed, true)
    }

    func testMutationSummaryHidesInternalRecordIdentifier() {
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "创建训练计划",
            name: "create_program",
            observation: "已创建训练计划 [id:888F4F29-7C5C-40DC-ACCB-A0AABC015F34]：基础力量训练。"
        ))

        XCTAssertEqual(presentation?.summary, "已创建训练计划：基础力量训练。")
        XCTAssertEqual(presentation?.details, [String]())
    }

    func testLongGenericResultShowsTextWithExpandDisclosure() {
        let observation = String(repeating: "完整结果", count: 60)
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "读取用户数据",
            name: "list_workouts",
            observation: observation
        ))

        XCTAssertEqual(presentation?.summary, observation)
        XCTAssertEqual(presentation?.details, [observation])
        XCTAssertEqual(presentation?.disclosureLabel, "展开")
        XCTAssertEqual(presentation?.defaultsCollapsed, true)
    }

    func testShortResultDoesNotShowExpandDisclosure() {
        let observation = "已记录训练：杠铃深蹲，4 组 × 8 次 · 60kg。"
        let presentation = AgentToolResultPresentation.make(for: toolItem(
            title: "记录训练",
            name: "create_workout",
            observation: observation
        ))

        XCTAssertEqual(presentation?.summary, observation)
        XCTAssertEqual(presentation?.details, [String]())
        XCTAssertNil(presentation?.disclosureLabel)
        XCTAssertEqual(presentation?.defaultsCollapsed, true)
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

    func testVisibleItemsKeepToolEventsWhenRecordReferencesExist() {
        let output = AgentTraceText.json(AgentToolResult.success(
            "已记录训练：杠铃硬拉。",
            recordRefs: [
                AgentRecordReference(
                    recordType: ConversationIntent.workout.rawValue,
                    recordID: 11,
                    title: "杠铃硬拉"
                )
            ],
            recordType: .workout
        ))
        let items = [
            AgentTurnItem(
                kind: .tool,
                status: .succeeded,
                title: "创建训练记录",
                output: output
            ),
            AgentTurnItem(
                kind: .text,
                status: .succeeded,
                text: "今天的下半身训练已经记下。"
            )
        ]

        XCTAssertEqual(
            AgentTurnVisibleItems.make(from: items).map(\.kind),
            [.tool, .text]
        )
        XCTAssertEqual(
            AgentTurnRecordReferences.make(from: items).map(\.recordID),
            [11]
        )
    }

    func testVisibleItemsKeepEveryWorkoutRecordReference() {
        let items = [Int64(21), 22].map { recordID in
            AgentTurnItem(
                kind: .tool,
                status: .succeeded,
                title: "创建训练记录",
                output: AgentTraceText.json(AgentToolResult.success(
                    "已记录",
                    recordRefs: [
                        AgentRecordReference(
                            recordType: ConversationIntent.workout.rawValue,
                            recordID: recordID,
                            title: "动作 \(recordID)"
                        )
                    ],
                    recordType: .workout
                ))
            )
        }

        XCTAssertEqual(
            AgentTurnRecordReferences.make(from: items).map(\.recordID),
            [21, 22]
        )
        XCTAssertEqual(
            AgentTurnVisibleItems.make(from: items).map(\.kind),
            [.tool, .tool]
        )
    }

    func testBatchCreateWorkoutMaterializesEveryRecordReference() {
        let refs = (Int64(1) ... 6).map { recordID in
            AgentRecordReference(
                recordType: ConversationIntent.workout.rawValue,
                recordID: recordID,
                title: "虚构动作 \(recordID)"
            )
        }
        let observation = """
        已记录 6 条训练。
        已记录训练：虚构硬拉，1组 × 5次 · 60kg
        已记录训练：虚构深蹲，3组 × 8次 · 40kg
        已记录训练：虚构卧推，3组 × 8次 · 30kg
        已记录训练：虚构引体，4组 × 6次 · 自重
        已记录训练：虚构划船，3组 × 10次 · 20kg
        已记录训练：虚构肩推，3组 × 8次 · 16kg
        """
        let items = [
            AgentTurnItem(
                kind: .tool,
                status: .succeeded,
                title: "搜索动作",
                input: #"{"name":"search_exercises","arguments":{"query":"硬拉"}}"#,
                output: AgentTraceText.json(AgentToolResult.success(
                    "找到 1 个动作。",
                    data: .object([
                        "items": .array([
                            .object([
                                "exercise_id": .number(11),
                                "name": .string("虚构硬拉")
                            ])
                        ])
                    ])
                ))
            ),
            AgentTurnItem(
                kind: .tool,
                status: .succeeded,
                title: "创建训练记录",
                input: #"{"name":"create_workout","arguments":{"workouts":[]}}"#,
                output: AgentTraceText.json(AgentToolResult.success(
                    observation,
                    recordRefs: refs,
                    recordType: .workout
                ))
            ),
            AgentTurnItem(
                kind: .text,
                status: .succeeded,
                text: "今天的训练已经记下。"
            )
        ]

        XCTAssertEqual(
            AgentTurnRecordReferences.make(from: items).map(\.recordID),
            [1, 2, 3, 4, 5, 6]
        )
        XCTAssertEqual(
            AgentTurnVisibleItems.make(from: items).map(\.kind),
            [.tool, .tool, .text]
        )

        let createPresentation = AgentToolResultPresentation.make(for: items[1])
        XCTAssertEqual(createPresentation?.summary, "已记录 6 条训练。")
        XCTAssertEqual(createPresentation?.details.count, 7)
        XCTAssertEqual(createPresentation?.disclosureLabel, "展开")
        XCTAssertEqual(createPresentation?.defaultsCollapsed, true)
        // ADR 0085：过程卡之后先出 6 张原位卡，最后才是收尾文字。
        XCTAssertEqual(
            AgentTurnTranscriptSegments.make(from: items).map(\.id),
            ["process-group:\(items[0].id.uuidString)"]
                + refs.map { "record:workout:\($0.recordID)" }
                + ["item:\(items[2].id.uuidString)"]
        )
    }

    func testSearchExerciseResultCollapsesToCountAndKeepsEachCall() {
        let items = (0 ..< 6).map { index in
            toolItem(
                title: "搜索动作",
                name: "search_exercises",
                observation: "找到 1 个动作。",
                data: .object([
                    "items": .array([
                        .object([
                            "exercise_id": .number(Double(index + 1)),
                            "name": .string("虚构动作\(index + 1)")
                        ])
                    ])
                ])
            )
        }

        XCTAssertEqual(AgentTurnVisibleItems.make(from: items).count, 6)
        for (index, item) in items.enumerated() {
            let presentation = AgentToolResultPresentation.make(for: item)
            XCTAssertEqual(presentation?.summary, "找到 1 个动作。")
            XCTAssertEqual(presentation?.details, ["虚构动作\(index + 1)"])
            XCTAssertEqual(presentation?.disclosureLabel, "展开")
            XCTAssertEqual(presentation?.defaultsCollapsed, true)
        }

        let segments = AgentTurnTranscriptSegments.make(from: items)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(
            AgentTurnTranscriptSegments.processSummary(for: items),
            "搜索动作 ×6"
        )
    }

    func testConsecutiveProcessCardsCollapseAroundTextAndErrors() {
        let search = toolItem(
            title: "搜索动作",
            name: "search_exercises",
            observation: "找到 1 个动作。"
        )
        let create = toolItem(
            title: "创建训练记录",
            name: "create_workout",
            observation: "已记录 6 条训练。"
        )
        let text = AgentTurnItem(
            kind: .text,
            status: .succeeded,
            text: "今天的训练已经记下。"
        )
        let failed = AgentTurnItem(
            kind: .tool,
            status: .failed,
            title: "搜索动作",
            errorMessage: "未找到动作"
        )

        let completed = AgentTurnTranscriptSegments.make(from: [search, search, create, text])
        XCTAssertEqual(completed.count, 2)
        XCTAssertEqual(
            AgentTurnTranscriptSegments.processSummary(for: [search, search, create]),
            "搜索动作 ×2 · 创建训练记录"
        )
        if case let .process(_, items) = completed[0] {
            XCTAssertEqual(items.map(\.title), ["搜索动作", "搜索动作", "创建训练记录"])
        } else {
            XCTFail("expected grouped process segment")
        }
        if case let .item(item) = completed[1] {
            XCTAssertEqual(item.kind, .text)
        } else {
            XCTFail("expected trailing text segment")
        }

        let interrupted = AgentTurnTranscriptSegments.make(from: [search, failed, create])
        XCTAssertEqual(interrupted.count, 3)
        if case let .item(item) = interrupted[1] {
            XCTAssertEqual(item.status, .failed)
        } else {
            XCTFail("failed tool must stay visible")
        }
    }

    func testRecordReferencesKeepDistinctTypesWithSameBusinessID() {
        let items = [
            AgentTurnItem(
                kind: .tool,
                status: .succeeded,
                title: "创建训练记录",
                output: AgentTraceText.json(AgentToolResult.success(
                    "已记录训练。",
                    recordRefs: [
                        AgentRecordReference(
                            recordType: ConversationIntent.workout.rawValue,
                            recordID: 1,
                            title: "虚构深蹲"
                        )
                    ],
                    recordType: .workout
                ))
            ),
            AgentTurnItem(
                kind: .tool,
                status: .succeeded,
                title: "创建饮食记录",
                output: AgentTraceText.json(AgentToolResult.success(
                    "已记录饮食。",
                    recordRefs: [
                        AgentRecordReference(
                            recordType: ConversationIntent.meal.rawValue,
                            recordID: 1,
                            title: "虚构午餐"
                        )
                    ],
                    recordType: .meal
                ))
            )
        ]

        XCTAssertEqual(
            AgentTurnRecordReferences.make(from: items).map(\.identityKey),
            ["workout:1", "meal:1"]
        )
    }

    /// ADR 0085：卡片跟在产生它的那一步之后，写入前后的文字保持原有顺序。
    func testRecordCardsFollowTheStepThatProducedThem() {
        let lead = AgentTurnItem(
            kind: .text,
            status: .succeeded,
            text: "我帮你识别到了以下食物信息。"
        )
        let create = AgentTurnItem(
            kind: .tool,
            status: .succeeded,
            title: "创建饮食记录",
            output: AgentTraceText.json(AgentToolResult.success(
                "已记录饮食。",
                recordRefs: [
                    AgentRecordReference(
                        recordType: ConversationIntent.meal.rawValue,
                        recordID: 7,
                        title: "虚构午餐"
                    )
                ],
                recordType: .meal
            ))
        )
        let review = AgentTurnItem(
            kind: .text,
            status: .succeeded,
            text: "这一餐蛋白偏低，下一餐可以补一份优质蛋白。"
        )

        XCTAssertEqual(
            AgentTurnTranscriptSegments.make(from: [lead, create, review]).map(\.id),
            [
                "item:\(lead.id.uuidString)",
                "process-single:\(create.id.uuidString)",
                "record:meal:7",
                "item:\(review.id.uuidString)"
            ]
        )
    }

    /// 同一条记录被多次引用时只出一张卡，避免重复写入被渲染成两份可编辑卡片。
    func testRepeatedReferenceRendersASingleCard() {
        let create = AgentTurnItem(
            kind: .tool,
            status: .succeeded,
            title: "创建饮食记录",
            output: AgentTraceText.json(AgentToolResult.success(
                "已记录饮食。",
                recordRefs: [
                    AgentRecordReference(
                        recordType: ConversationIntent.meal.rawValue,
                        recordID: 9,
                        title: "虚构午餐"
                    )
                ],
                recordType: .meal
            ))
        )
        let update = AgentTurnItem(
            kind: .tool,
            status: .succeeded,
            title: "更新饮食记录",
            output: AgentTraceText.json(AgentToolResult.success(
                "已更新饮食。",
                recordRefs: [
                    AgentRecordReference(
                        recordType: ConversationIntent.meal.rawValue,
                        recordID: 9,
                        title: "虚构午餐"
                    )
                ],
                recordType: .meal
            ))
        )

        let segments = AgentTurnTranscriptSegments.make(from: [create, update])
        XCTAssertEqual(
            segments.filter { $0.id.hasPrefix("record:") }.map(\.id),
            ["record:meal:9"]
        )
    }

    private func toolItem(
        title: String,
        name: String,
        scope: String? = nil,
        observation: String,
        data: AgentJSONValue? = nil
    ) -> AgentTurnItem {
        let scopeJSON = scope.map { #", "scope": "\#($0)""# } ?? ""
        return AgentTurnItem(
            kind: .tool,
            status: .succeeded,
            title: title,
            input: #"{"name":"\#(name)","arguments":{"placeholder":true\#(scopeJSON)}}"#,
            output: AgentTraceText.json(AgentToolResult.success(observation, data: data))
        )
    }
}
