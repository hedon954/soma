@testable import Soma
import SwiftData
import XCTest

final class AgentWorkoutCaloriesTests: XCTestCase {
    func testBatchSignatureDistinguishesCaloriesFromOmissionAndOtherValues() throws {
        let signatures = try [nil, 0, 432, 433].map { calories in
            var item: [String: Any] = ["exercise_id": 7]
            if let calories {
                item["calories"] = calories
            }
            let data = try JSONSerialization.data(withJSONObject: ["workouts": [item]])
            return try AgentToolCallSignature.canonical(
                name: .createWorkout,
                arguments: JSONDecoder().decode(AgentToolArguments.self, from: data)
            )
        }
        XCTAssertEqual(Set(signatures).count, 4)
    }

    func testLegacyCreatePreservesExplicitCalories() throws {
        let input = try XCTUnwrap(AgentWorkoutCreateInput.fromLegacyCreate(
            AgentToolArguments(exerciseID: 7, calories: 432)
        ))
        XCTAssertEqual(input.toolArguments().calories, 432)
    }

    @MainActor
    func testCreateUsesExplicitCalories() throws {
        try checkWorkoutTool(.createWorkout, calories: 432)
    }

    @MainActor
    func testCreateWithoutCaloriesUsesMET() throws {
        try checkWorkoutTool(.createWorkout, calories: nil)
    }

    @MainActor
    func testUpdateUsesExplicitCalories() throws {
        try checkWorkoutTool(.updateWorkout, calories: 432)
    }

    @MainActor
    func testUpdateWithoutCaloriesRecalculatesMET() throws {
        try checkWorkoutTool(.updateWorkout, calories: nil)
    }

    @MainActor
    func testExplicitZeroIsNotTreatedAsMissing() throws {
        try checkWorkoutTool(.createWorkout, calories: 0)
        try checkWorkoutTool(.updateWorkout, calories: 0)
    }

    @MainActor
    func testExplicitCaloriesDoNotRequireBodyWeight() throws {
        try checkWorkoutTool(.createWorkout, calories: 432, weight: nil)
        try checkWorkoutTool(.updateWorkout, calories: 432, weight: nil)
    }

    @MainActor
    private func checkWorkoutTool(
        _ name: AgentToolName,
        calories: Int?,
        weight: Double? = 68
    ) throws {
        let suite = "AgentWorkoutCaloriesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        let container = try XCTUnwrap(spaces.personalContainer)
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        if let weight {
            context.insert(BodyEntry(date: date.addingTimeInterval(-60), weight: weight))
        }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构跑步",
            in: context
        )
        let exerciseID = try XCTUnwrap(exercise.businessID)
        var fields: [String: Any] = [
            "target_kind": "duration",
            "laterality": "none"
        ]
        if let calories {
            fields["calories"] = calories
        }
        let object: [String: Any]
        if name == .createWorkout {
            fields["exercise_id"] = exerciseID
            fields["set_entries"] = [[
                "logical_set_index": 1,
                "side": "none",
                "target_kind": "duration",
                "duration_seconds": 1200,
                "external_weight_kg": 0
            ]]
            object = ["workouts": [fields]]
        } else {
            let existing = WorkoutEntry(
                date: date,
                exercise: exercise.canonicalName,
                exerciseID: exercise.id,
                durationMinutes: 20,
                notes: "虚构训练",
                estimatedCalories: 321,
                calorieScope: .metGross
            )
            context.insert(existing)
            existing.exerciseDefinition = exercise
            try BusinessIDAllocator.assign(existing, namespace: "workout", in: context)
            fields["record_id"] = try XCTUnwrap(existing.businessID)
            object = fields
        }
        try context.save()
        let data = try JSONSerialization.data(withJSONObject: object)
        try AgentToolSchemaValidator.validate(data, for: name, schemaVersion: name.schemaVersion)
        let arguments = try JSONDecoder().decode(AgentToolArguments.self, from: data)
        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(name: name, arguments: arguments),
            sourceText: "虚构训练测试",
            sourceDate: date,
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        XCTAssertTrue(result.ok, result.message)
        let persisted = try ModelContext(container).fetch(FetchDescriptor<WorkoutEntry>())
        XCTAssertEqual(persisted.count, 1, "修改必须更新原记录")
        let entry = try XCTUnwrap(persisted.first)
        let expected: Int
        if let calories {
            expected = calories
        } else {
            expected = try XCTUnwrap(WorkoutCalorieCalculator.estimate(
                exercise: exercise.canonicalName,
                intensity: nil,
                durationMinutes: 20,
                sets: nil,
                reps: nil,
                restSeconds: nil,
                weightKG: weight
            )).calories
            XCTAssertNotEqual(expected, 321)
        }
        XCTAssertEqual(entry.estimatedCalories, expected)
        XCTAssertTrue(result.message.replacingOccurrences(of: " ", with: "").contains("\(expected)kcal"), result.message)
        if calories != nil {
            XCTAssertFalse(result.message.contains("MET"), result.message)
        }
    }
}
