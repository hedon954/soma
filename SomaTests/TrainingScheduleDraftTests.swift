@testable import Soma
import SwiftData
import XCTest

final class TrainingScheduleDraftTests: XCTestCase {
    func testComposeKeepsSelectionAndSupplementAndSkipsBlankQuestions() {
        let text = ScheduleDraftAnswerText.compose([
            ScheduleDraftAnswerText.Item(
                question: "每周练几天？",
                selections: ["每周三次。"],
                supplement: "希望隔天"
            ),
            ScheduleDraftAnswerText.Item(question: "空的", selections: [], supplement: "  ")
        ])
        XCTAssertEqual(
            text,
            """
            关于这份训练计划：

            【每周练几天？】
            每周三次。
            我补充：希望隔天
            """
        )
        XCTAssertTrue(ScheduleDraftAnswerText.requiresSelection(userText: ScheduleDraftAnswerText.opening))
        XCTAssertTrue(try ScheduleDraftAnswerText.requiresSelection(userText: XCTUnwrap(text)))
        XCTAssertFalse(ScheduleDraftAnswerText.requiresSelection(userText: "今天练了深蹲"))
    }

    func testSingleSelectReplacesAndClearsWhileMultipleToggles() {
        let first = ScheduleDraftAnswerText.toggle(mode: .single, selected: [], optionID: "a")
        XCTAssertEqual(first, Set(["a"]))
        let replaced = ScheduleDraftAnswerText.toggle(mode: .single, selected: first, optionID: "b")
        XCTAssertEqual(replaced, Set(["b"]))
        XCTAssertTrue(ScheduleDraftAnswerText.toggle(mode: .single, selected: replaced, optionID: "b").isEmpty)
        let both = ScheduleDraftAnswerText.toggle(
            mode: .multiple,
            selected: ScheduleDraftAnswerText.toggle(mode: .multiple, selected: [], optionID: "a"),
            optionID: "b"
        )
        XCTAssertEqual(both, Set(["a", "b"]))
    }

    func testDraftQuestionsRequireSelectionWithoutActions() {
        let plain = AgentUserQuestion(
            id: "days",
            question: "这轮每周练几天？",
            options: [AgentQuestionOption(id: "three", text: "每周三次。")],
            allowsCustomInput: true
        )
        XCTAssertFalse(
            AgentUserQuestionsTool.result(
                questions: [plain],
                requiresSelection: true
            ).ok
        )
        var selected = plain
        selected.selection = .single
        XCTAssertTrue(
            AgentUserQuestionsTool.result(
                questions: [selected],
                requiresSelection: true
            ).ok
        )
        selected.allowsCustomInput = false
        XCTAssertFalse(AgentUserQuestionsTool.result(questions: [selected]).ok)
        selected.allowsCustomInput = true
        selected.options[0].action = AgentQuestionAction(
            toolName: .createBodyEntry,
            argumentsJSON: #"{"weight":70}"#
        )
        XCTAssertFalse(AgentUserQuestionsTool.result(questions: [selected]).ok)
        XCTAssertTrue(AgentUserQuestionsTool.result(questions: [plain]).ok)
    }

    @MainActor
    func testProposalDoesNotInsertAndRejectsIncompleteDrafts() throws {
        let context = try makeContext()
        let exercise = ExerciseDefinition(canonicalName: "虚构深蹲")
        context.insert(exercise)
        exercise.businessID = 4
        try context.save()
        let input = AgentTemplateExerciseInput(
            exerciseID: 4, order: 1, laterality: ExerciseLaterality.none,
            setPrescriptions: [.init(order: 1, kind: .working, targetKind: .repetitions, targetReps: 5)]
        )
        let slot = TrainingScheduleDraftSlotArgument(
            kind: "training", contents: [.init(kind: "exercise", exercises: [input])]
        )
        let result = TrainingScheduleDraftTool.propose(name: "虚构计划", anchorDate: nil, slots: [slot, .init(kind: "rest")], in: context)
        XCTAssertTrue(result.ok, result.message)
        let payload = try XCTUnwrap(TrainingScheduleDraftPayload.from(result))
        XCTAssertEqual(payload.slots.map(\.title), ["虚构深蹲", "休息"])
        XCTAssertEqual(payload.editorDraft().slots.count, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingSchedule>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingProgram>()), 0)
        XCTAssertFalse(TrainingScheduleDraftTool.propose(name: "", anchorDate: nil, slots: [slot], in: context).ok)
        XCTAssertFalse(TrainingScheduleDraftTool.propose(name: "计划", anchorDate: nil, slots: [.init(kind: "rest")], in: context).ok)
        XCTAssertFalse(TrainingScheduleDraftTool.propose(name: "计划", anchorDate: "2026-13-01", slots: [slot], in: context).ok)
        XCTAssertFalse(TrainingScheduleDraftTool.propose(name: "计划", anchorDate: nil, slots: Array(repeating: slot, count: 15), in: context).ok)
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema(SomaDataSchema.models)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
