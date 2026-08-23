@testable import Soma
import SwiftData
import SwiftOpenAI
import XCTest

final class AgentPlanToolV3Tests: XCTestCase {
    func testOnlyCurrentPlanAndBatchWriteToolsAdvertiseSchemaThree() {
        XCTAssertEqual(AgentToolName.getProgram.schemaVersion, 3)
        XCTAssertEqual(AgentToolName.createProgram.schemaVersion, 3)
        XCTAssertEqual(AgentToolName.updateProgram.schemaVersion, 3)
        XCTAssertEqual(AgentToolName.createExercise.schemaVersion, 3)
        XCTAssertEqual(AgentToolName.createWorkout.schemaVersion, 3)
        XCTAssertEqual(AgentToolName.startProgram.schemaVersion, 2)
        XCTAssertEqual(AgentToolName.listPrograms.schemaVersion, 2)
        XCTAssertEqual(AgentToolName.createProgram.supportedSchemaVersions, [1, 2, 3])
        XCTAssertEqual(AgentToolName.createWorkout.supportedSchemaVersions, [1, 2, 3])
    }

    func testSchemaThreeDecodesIndependentBothSideAndDurationSets() throws {
        let resolved = try resolve([
            "program_name": "虚构逐组计划",
            "overview": "左右独立。",
            "template_exercises": [[
                "exercise_id": 42,
                "order": 1,
                "laterality": "both",
                "target_rest_seconds": 45,
                "rest_between_sides_seconds": 15,
                "set_prescriptions": [
                    [
                        "order": 1,
                        "kind": "warmup",
                        "target_kind": "repetitions",
                        "target_reps": 10,
                        "left_weight_kg": 8,
                        "right_weight_kg": 9
                    ],
                    [
                        "order": 2,
                        "kind": "working",
                        "target_kind": "duration",
                        "target_duration_seconds": 30,
                        "left_weight_kg": 10,
                        "right_weight_kg": 11
                    ]
                ]
            ]]
        ])

        XCTAssertEqual(resolved.local.name, .createProgram)
        XCTAssertEqual(resolved.local.arguments.overview, "左右独立。")
        let exercise = try XCTUnwrap(resolved.local.arguments.templateExercises?.first)
        XCTAssertEqual(exercise.laterality, .both)
        XCTAssertEqual(exercise.targetRestSeconds, 45)
        XCTAssertEqual(exercise.restBetweenSidesSeconds, 15)
        XCTAssertEqual(exercise.setPrescriptions?.count, 2)
        XCTAssertEqual(exercise.setPrescriptions?.last?.targetKind, .duration)
        XCTAssertEqual(exercise.setPrescriptions?.last?.targetDurationSeconds, 30)
        XCTAssertEqual(exercise.setPrescriptions?.first?.leftWeightKG, 8)
        XCTAssertEqual(exercise.setPrescriptions?.first?.rightWeightKG, 9)
    }

    func testSchemaThreeRejectsNestedUnknownRequiredTypeEnumRangeAndUnionFailures() throws {
        let invalid: [[String: Any]] = [
            arguments(set: validSet().merging(["hidden_guess": true]) { _, rhs in rhs }),
            arguments(set: [
                "order": 1,
                "kind": "working",
                "target_kind": "repetitions"
            ]),
            arguments(laterality: "alternating"),
            arguments(laterality: "none"),
            arguments(set: validSet().merging(["target_reps": 0]) { _, rhs in rhs }),
            arguments(set: validSet().merging(["target_duration_seconds": 30]) { _, rhs in rhs }),
            arguments(order: "1")
        ]

        for value in invalid {
            XCTAssertThrowsError(try resolve(value), "应拒绝：\(value)")
        }
    }

    func testSchemaTwoRecoveryValidatorAcceptsLegacyAndRejectsNestedUnknownFields() throws {
        let legacy: [String: Any] = [
            "program_name": "虚构旧计划",
            "goal": "旧 Job",
            "template_exercises": [[
                "exercise_id": 42,
                "order": 1,
                "target_sets": 3,
                "target_reps": 8,
                "target_weight_kg": 20,
                "target_rest_seconds": 90,
                "first_set_is_warmup": true
            ]]
        ]
        try AgentToolSchemaValidator.validate(
            JSONSerialization.data(withJSONObject: legacy),
            for: .createProgram,
            schemaVersion: 2
        )
        var invalid = legacy
        var exercises = try XCTUnwrap(invalid["template_exercises"] as? [[String: Any]])
        exercises[0]["set_prescriptions"] = []
        invalid["template_exercises"] = exercises
        XCTAssertThrowsError(try AgentToolSchemaValidator.validate(
            JSONSerialization.data(withJSONObject: invalid),
            for: .createProgram,
            schemaVersion: 2
        ))
    }

    @MainActor
    func testV3WritesIndependentSetsAndV2LegacyExpandsDeterministically() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构单侧划船",
            in: fixture.context
        )
        let exerciseID = try XCTUnwrap(exercise.businessID)
        let v3 = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createProgram,
                arguments: AgentToolArguments(
                    programName: "V3 计划",
                    overview: "左右重量不同。",
                    templateExercises: [AgentTemplateExerciseInput(
                        exerciseID: exerciseID,
                        order: 1,
                        targetRestSeconds: 60,
                        restBetweenSidesSeconds: 15,
                        laterality: .both,
                        setPrescriptions: [
                            AgentTemplateSetPrescriptionInput(
                                order: 1,
                                kind: .working,
                                targetKind: .duration,
                                targetDurationSeconds: 30,
                                leftWeightKG: 12,
                                rightWeightKG: 14
                            )
                        ]
                    )]
                )
            ),
            sourceText: "创建虚构逐组计划",
            mediaKind: .none,
            mediaPath: nil,
            in: fixture.context
        )
        XCTAssertTrue(v3.ok, v3.message)
        let v3Program = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<TrainingProgram>())
                .first { $0.name == "V3 计划" }
        )
        XCTAssertEqual(v3Program.overview, "左右重量不同。")
        let v3Prescription = try XCTUnwrap(
            TrainingPlanStore.prescriptions(for: v3Program, in: fixture.context).first
        )
        XCTAssertEqual(v3Prescription.laterality, .both)
        XCTAssertEqual(v3Prescription.plannedSets.first?.targetKind, .duration)
        XCTAssertEqual(v3Prescription.plannedSets.first?.leftWeightKG, 12)
        XCTAssertEqual(v3Prescription.plannedSets.first?.rightWeightKG, 14)
        XCTAssertEqual(v3Prescription.targetRestSeconds, 60)
        XCTAssertEqual(v3Prescription.restBetweenSidesSeconds, 15)

        let legacy = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createProgram,
                arguments: AgentToolArguments(
                    programName: "V2 恢复计划",
                    goal: "旧 Job",
                    templateExercises: [AgentTemplateExerciseInput(
                        exerciseID: exerciseID,
                        order: 1,
                        targetSets: 3,
                        targetReps: 8,
                        targetWeightKG: 20,
                        targetRestSeconds: 90,
                        firstSetIsWarmup: true
                    )]
                )
            ),
            sourceText: "恢复排队任务",
            mediaKind: .none,
            mediaPath: nil,
            in: fixture.context
        )
        XCTAssertTrue(legacy.ok, legacy.message)
        let legacyProgram = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<TrainingProgram>())
                .first { $0.name == "V2 恢复计划" }
        )
        let legacyPrescription = try XCTUnwrap(
            TrainingPlanStore.prescriptions(for: legacyProgram, in: fixture.context).first
        )
        XCTAssertEqual(legacyPrescription.laterality, .none)
        XCTAssertEqual(legacyPrescription.plannedSets.count, 3)
        XCTAssertEqual(
            legacyPrescription.plannedSets.map(\.kind),
            [.warmup, .working, .working]
        )

        let detail = try ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .getProgram,
                arguments: AgentToolArguments(programID: XCTUnwrap(v3Program.businessID))
            ),
            sourceText: "",
            mediaKind: .none,
            mediaPath: nil,
            in: fixture.context
        )
        let detailJSON = try XCTUnwrap(
            try String(data: JSONEncoder().encode(XCTUnwrap(detail.data)), encoding: .utf8)
        )
        XCTAssertTrue(detailJSON.contains("set_prescriptions"))
        XCTAssertTrue(detailJSON.contains("target_duration_seconds"))
        XCTAssertTrue(detailJSON.contains("left_weight_kg"))
    }

    private func resolve(
        _ arguments: [String: Any]
    ) throws -> (native: ToolCall, local: AgentToolCall) {
        let data = try JSONSerialization.data(
            withJSONObject: arguments,
            options: [.sortedKeys]
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        var accumulator = AgentStreamingToolCall()
        accumulator.append(ToolCall(
            index: 0,
            id: "call-plan-v3",
            function: FunctionCall(arguments: text, name: AgentToolName.createProgram.rawValue)
        ))
        return try accumulator.resolved(fallbackID: "fallback")
    }

    private func arguments(
        laterality: String = "both",
        order: Any = 1,
        set: [String: Any]? = nil
    ) -> [String: Any] {
        let set = set ?? validSet()
        return [
            "program_name": "虚构计划",
            "template_exercises": [[
                "exercise_id": 42,
                "order": order,
                "laterality": laterality,
                "target_rest_seconds": 90,
                "rest_between_sides_seconds": 15,
                "set_prescriptions": [set]
            ]]
        ]
    }

    private func validSet() -> [String: Any] {
        [
            "order": 1,
            "kind": "working",
            "target_kind": "repetitions",
            "target_reps": 8,
            "left_weight_kg": 20,
            "right_weight_kg": 22
        ]
    }

    @MainActor
    private func makeContext() throws -> (
        context: ModelContext,
        defaults: UserDefaults,
        suite: String
    ) {
        let suite = "AgentPlanToolV3Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        return try (ModelContext(XCTUnwrap(spaces.personalContainer)), defaults, suite)
    }
}
