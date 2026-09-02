@testable import Soma
import SwiftData
import XCTest

final class AgentBatchCreateToolTests: XCTestCase {
    func testExerciseAndWorkoutToolsAdvertiseSchemaFour() {
        for name in [
            AgentToolName.searchExercises,
            .createExercise,
            .updateExercise,
            .createWorkout,
            .updateWorkout
        ] {
            XCTAssertEqual(name.schemaVersion, 4)
        }
        XCTAssertEqual(AgentToolName.createExercise.supportedSchemaVersions, [1, 2, 3, 4])
        XCTAssertEqual(AgentToolName.createWorkout.supportedSchemaVersions, [1, 2, 3, 4])
        XCTAssertEqual(AgentToolName.searchExercises.supportedSchemaVersions, [1, 2, 4])
    }

    func testSchemaFourRequiresExplicitPairedEffortsForBothLaterality() throws {
        let valid: [String: Any] = [
            "workouts": [[
                "exercise_id": 7,
                "target_kind": "repetitions",
                "laterality": "both",
                "set_entries": [
                    [
                        "logical_set_index": 1,
                        "side": "left",
                        "target_kind": "repetitions",
                        "reps": 12,
                        "external_weight_kg": 0,
                        "rest_seconds": 30
                    ],
                    [
                        "logical_set_index": 1,
                        "side": "right",
                        "target_kind": "repetitions",
                        "reps": 12,
                        "external_weight_kg": 0,
                        "rest_seconds": 60
                    ]
                ]
            ]]
        ]
        try AgentToolSchemaValidator.validate(
            json(valid),
            for: .createWorkout,
            schemaVersion: 4
        )

        var conflict = valid
        var workouts = try XCTUnwrap(conflict["workouts"] as? [[String: Any]])
        workouts[0]["laterality"] = "none"
        conflict["workouts"] = workouts
        XCTAssertThrowsError(try AgentToolSchemaValidator.validate(
            json(conflict),
            for: .createWorkout,
            schemaVersion: 4
        ))
    }

    func testSchemaThreeCreateWorkoutRequiresWorkoutsAndRejectsRecordID() throws {
        try AgentToolSchemaValidator.validate(
            json(["exercise_names": ["虚构俯身飞鸟"]]),
            for: .createExercise,
            schemaVersion: 3
        )
        try AgentToolSchemaValidator.validate(
            json([
                "workouts": [[
                    "exercise_id": 7,
                    "set_entries": [["reps": 5, "external_weight_kg": 60]]
                ]]
            ]),
            for: .createWorkout,
            schemaVersion: 3
        )
        try AgentToolSchemaValidator.validate(
            json([
                "workouts": [[
                    "exercise_id": 8,
                    "set_entries": [["duration_seconds": 45, "external_weight_kg": 0]]
                ]]
            ]),
            for: .createWorkout,
            schemaVersion: 3
        )
        XCTAssertThrowsError(try AgentToolSchemaValidator.validate(
            json(["exercise_name": "虚构俯身飞鸟"]),
            for: .createExercise,
            schemaVersion: 3
        ))
        XCTAssertThrowsError(try AgentToolSchemaValidator.validate(
            json(["exercise_id": 7]),
            for: .createWorkout,
            schemaVersion: 3
        ))
        XCTAssertThrowsError(try AgentToolSchemaValidator.validate(
            json(["workouts": []]),
            for: .createWorkout,
            schemaVersion: 3
        ))
        XCTAssertThrowsError(try AgentToolSchemaValidator.validate(
            json([
                "workouts": [[
                    "exercise_id": 7,
                    "record_id": 99
                ]]
            ]),
            for: .createWorkout,
            schemaVersion: 3
        ))
    }

    func testWorkoutSetRejectsMixedRepetitionsAndDuration() {
        XCTAssertThrowsError(try AgentToolSchemaValidator.validate(
            json([
                "workouts": [[
                    "exercise_id": 7,
                    "set_entries": [["reps": 5, "duration_seconds": 45]]
                ]]
            ]),
            for: .createWorkout,
            schemaVersion: 3
        ))
    }

    func testSchemaTwoRecoveryStillAcceptsSingleCreateShapes() throws {
        try AgentToolSchemaValidator.validate(
            json(["exercise_name": "虚构俯身飞鸟"]),
            for: .createExercise,
            schemaVersion: 2
        )
        try AgentToolSchemaValidator.validate(
            json([
                "exercise_id": 7,
                "set_entries": [["reps": 8, "external_weight_kg": 20]]
            ]),
            for: .createWorkout,
            schemaVersion: 2
        )
        XCTAssertThrowsError(try AgentToolSchemaValidator.validate(
            json([
                "exercise_id": 7,
                "record_id": 3
            ]),
            for: .createWorkout,
            schemaVersion: 2
        ))
        XCTAssertThrowsError(try AgentToolSchemaValidator.validate(
            json(["exercise_names": ["虚构俯身飞鸟"]]),
            for: .createExercise,
            schemaVersion: 2
        ))
    }

    func testWorkoutBatchSignaturePreservesItemOrder() {
        let first = AgentWorkoutCreateInput(
            exerciseID: 1,
            setEntries: [AgentWorkoutSetInput(reps: 5, externalWeightKG: 60)]
        )
        let second = AgentWorkoutCreateInput(
            exerciseID: 2,
            setEntries: [AgentWorkoutSetInput(reps: 8, externalWeightKG: 20)]
        )
        let ordered = AgentToolCall(
            name: .createWorkout,
            arguments: .init(workouts: [first, second])
        ).signature
        let reversed = AgentToolCall(
            name: .createWorkout,
            arguments: .init(workouts: [second, first])
        ).signature
        XCTAssertNotEqual(ordered, reversed)
        XCTAssertTrue(ordered.contains("exercise_id"))
        XCTAssertFalse(ordered.contains("record_id"))
    }

    @MainActor
    func testBatchCreateExerciseReturnsIDsAndReusesExistingNames() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let existing = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构硬拉",
            in: fixture.context
        )
        let existingID = try XCTUnwrap(existing.businessID)

        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createExercise,
                arguments: .init(exerciseNames: [
                    "虚构硬拉",
                    "  虚构弹力带抗旋  ",
                    "虚构硬拉"
                ])
            ),
            sourceText: "补两个动作",
            mediaKind: .none,
            mediaPath: nil,
            in: fixture.context
        )

        XCTAssertTrue(result.ok, result.message)
        XCTAssertTrue(result.message.contains("[exercise_id:\(existingID)]"))
        guard case let .object(data) = result.data,
              case let .array(items) = data["items"]
        else {
            return XCTFail("应返回 items")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(exerciseID(in: items[0]), existingID)
        let createdID = try XCTUnwrap(exerciseID(in: items[1]))
        XCTAssertNotEqual(createdID, existingID)
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<ExerciseDefinition>())
                .filter { !$0.isArchived }
                .count,
            2
        )
    }

    @MainActor
    func testBatchCreateWorkoutWritesIndependentRecordsWithoutCallerIDs() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let deadlift = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构硬拉",
            in: fixture.context
        )
        let antiRotation = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构弹力带抗旋",
            in: fixture.context
        )
        let deadliftID = try XCTUnwrap(deadlift.businessID)
        let antiRotationID = try XCTUnwrap(antiRotation.businessID)
        let occurredAt = "2026-08-17T20:47:00+08:00"
        let occurredDate = try XCTUnwrap(ISO8601DateFormatter().date(from: occurredAt))
        let turnID = UUID()

        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createWorkout,
                arguments: .init(workouts: [
                    AgentWorkoutCreateInput(
                        exerciseID: deadliftID,
                        occurredAt: occurredAt,
                        setEntries: [
                            AgentWorkoutSetInput(reps: 5, externalWeightKG: 60)
                        ],
                        restSeconds: 120
                    ),
                    AgentWorkoutCreateInput(
                        exerciseID: antiRotationID,
                        setEntries: [
                            AgentWorkoutSetInput(reps: 12, externalWeightKG: 0)
                        ]
                    )
                ])
            ),
            sourceText: "记录今晚训练",
            sourceDate: Date(timeIntervalSince1970: 1_787_000_000),
            sourceTurnID: turnID,
            mediaKind: .none,
            mediaPath: nil,
            in: fixture.context
        )

        XCTAssertTrue(result.ok, result.message)
        XCTAssertEqual(result.recordRefs?.count, 2)
        let workouts = try fixture.context.fetch(FetchDescriptor<WorkoutEntry>())
            .sorted { $0.exercise < $1.exercise }
        XCTAssertEqual(workouts.count, 2)
        XCTAssertEqual(Set(workouts.map(\.exercise)), ["虚构弹力带抗旋", "虚构硬拉"])
        let deadliftEntry = try XCTUnwrap(workouts.first { $0.exercise == "虚构硬拉" })
        let antiRotationEntry = try XCTUnwrap(
            workouts.first { $0.exercise == "虚构弹力带抗旋" }
        )
        XCTAssertEqual(deadliftEntry.date, occurredDate)
        XCTAssertEqual(deadliftEntry.restSeconds, 120)
        XCTAssertEqual(deadliftEntry.setEntries.first?.reps, 5)
        XCTAssertEqual(deadliftEntry.setEntries.first?.externalWeightKG, 60)
        XCTAssertEqual(antiRotationEntry.setEntries.first?.reps, 12)
        XCTAssertNotEqual(deadliftEntry.businessID, antiRotationEntry.businessID)
        XCTAssertEqual(
            Set(result.recordRefs?.compactMap(\.recordID) ?? []),
            Set(workouts.compactMap(\.businessID))
        )
    }

    @MainActor
    func testBothLateralityPersistsPairedEffortsAndBackfillsExercise() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let splitSquat = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构保加利亚分腿蹲",
            in: fixture.context
        )
        let exerciseID = try XCTUnwrap(splitSquat.businessID)
        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createWorkout,
                arguments: .init(workouts: [AgentWorkoutCreateInput(
                    exerciseID: exerciseID,
                    targetKind: .repetitions,
                    laterality: .both,
                    setEntries: [
                        AgentWorkoutSetInput(
                            logicalSetIndex: 1,
                            side: .left,
                            targetKind: .repetitions,
                            reps: 12,
                            externalWeightKG: 0,
                            restSeconds: 30
                        ),
                        AgentWorkoutSetInput(
                            logicalSetIndex: 1,
                            side: .right,
                            targetKind: .repetitions,
                            reps: 12,
                            externalWeightKG: 0,
                            restSeconds: 60
                        )
                    ]
                )])
            ),
            sourceText: "左右各 12 次",
            mediaKind: .none,
            mediaPath: nil,
            in: fixture.context
        )

        XCTAssertTrue(result.ok, result.message)
        let workout = try XCTUnwrap(
            fixture.context.fetch(FetchDescriptor<WorkoutEntry>()).first
        )
        XCTAssertEqual(workout.setCount, 1)
        XCTAssertEqual(Set(workout.setEntries.compactMap(\.side)), [.left, .right])
        XCTAssertEqual(workout.setEntries.map(\.logicalSetIndex), [1, 1])
        XCTAssertEqual(splitSquat.laterality, .both)
        XCTAssertEqual(splitSquat.targetKind, .repetitions)
    }

    @MainActor
    func testLegacySingleCreateWorkoutStillWritesOneRecord() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let squat = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构深蹲",
            in: fixture.context
        )
        let squatID = try XCTUnwrap(squat.businessID)

        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createWorkout,
                arguments: .init(
                    exerciseID: squatID,
                    setEntries: [AgentWorkoutSetInput(reps: 8, externalWeightKG: 60)]
                )
            ),
            sourceText: "记录深蹲",
            mediaKind: .none,
            mediaPath: nil,
            in: fixture.context
        )

        XCTAssertTrue(result.ok, result.message)
        XCTAssertEqual(result.recordRefs?.count, 1)
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<WorkoutEntry>()).count,
            1
        )
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func exerciseID(in item: AgentJSONValue) -> Int64? {
        guard case let .object(object) = item,
              case let .number(value) = object["exercise_id"]
        else {
            return nil
        }
        return Int64(value)
    }

    @MainActor
    private func makeContext() throws -> (
        context: ModelContext,
        defaults: UserDefaults,
        suite: String
    ) {
        let suite = "AgentBatchCreateToolTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        return try (ModelContext(XCTUnwrap(spaces.personalContainer)), defaults, suite)
    }
}
