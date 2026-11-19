@testable import Soma
import SwiftData
import XCTest

final class ExerciseMuscleRepairTests: XCTestCase {
    @MainActor
    func testRepairPreservesExistingAnnotationsAndUpdatesAnOldWorkoutShare() throws {
        let context = try makeContext()
        let row = try ExerciseLibraryStore.resolveOrCreateExact(canonicalName: "虚构绳索划船", in: context)
        let press = try ExerciseLibraryStore.resolveOrCreateExact(canonicalName: "虚构器械胸推", in: context)
        press.primaryMuscles = ["胸大肌"]
        let missing = try ExerciseLibraryStore.resolveOrCreateExact(canonicalName: "虚构待核对", in: context)
        let now = Date()
        let workout = WorkoutEntry(date: now, exercise: row.canonicalName, exerciseID: row.id, sets: 3, reps: 8)
        workout.exerciseDefinition = row
        context.insert(workout)
        try context.save()
        let plan = try ExerciseMuscleRepair(entries: [
            .init(id: XCTUnwrap(row.businessID), name: row.canonicalName, primary: [.upperBack], secondary: [.biceps]),
            .init(id: XCTUnwrap(press.businessID), name: press.canonicalName, primary: [.gluteal], secondary: [])
        ])

        XCTAssertTrue(try XCTUnwrap(WorkoutSharePosterBuilder.makeModel(forDay: now, in: context)).intensities.isEmpty)
        let preview = try plan.preview(in: context)
        XCTAssertEqual(preview.pending.map(\.name), [row.canonicalName])
        XCTAssertEqual(preview.unresolved, [missing.canonicalName])
        XCTAssertEqual(try plan.apply(preview, in: context), 1)
        XCTAssertEqual(press.primaryMuscles, ["胸大肌"])
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: row.primaryMusclesData), ["upper-back"])
        let poster = try XCTUnwrap(WorkoutSharePosterBuilder.makeModel(forDay: now, in: context))
        XCTAssertEqual(poster.intensities[.upperBack], 3)
        XCTAssertEqual(try XCTUnwrap(poster.intensities[.biceps]), 1.35, accuracy: 0.0001)
        XCTAssertThrowsError(try plan.apply(preview, in: context))
        XCTAssertTrue(try plan.preview(in: context).pending.isEmpty)
    }

    @MainActor
    func testRenameKeepsActionAndWorkoutIdentitiesAndSkipsNameCollision() throws {
        let context = try makeContext()
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(canonicalName: "虚构坐姿卷腹简称", in: context)
        let conflicting = try ExerciseLibraryStore.resolveOrCreateExact(canonicalName: "虚构同名候选", in: context)
        let actionID = exercise.id
        let businessID = try XCTUnwrap(exercise.businessID)
        let conflictingID = try XCTUnwrap(conflicting.businessID)
        let workout = WorkoutEntry(exercise: exercise.canonicalName, exerciseID: actionID, sets: 3, reps: 8, weight: 10)
        let workoutID = workout.id
        exercise.primaryMuscles = ["腹直肌"]
        let storedPrimary = exercise.primaryMusclesData
        workout.exerciseDefinition = exercise
        context.insert(workout)
        try context.save()

        let collision = ExerciseMuscleRepair(entries: [
            .init(id: conflictingID, name: conflicting.canonicalName, newName: exercise.canonicalName, primary: [], secondary: [])
        ])
        XCTAssertTrue(try collision.preview(in: context).pending.isEmpty)

        let plan = ExerciseMuscleRepair(entries: [
            .init(id: businessID, name: exercise.canonicalName, newName: "虚构坐姿抬腿卷腹", primary: [], secondary: [])
        ])
        let preview = try plan.preview(in: context)
        XCTAssertEqual(try plan.apply(preview, in: context), 1)
        XCTAssertEqual(exercise.id, actionID)
        XCTAssertEqual(exercise.businessID, businessID)
        XCTAssertEqual(exercise.primaryMusclesData, storedPrimary)
        XCTAssertEqual(workout.id, workoutID)
        XCTAssertEqual(workout.exerciseID, actionID)
        XCTAssertEqual(workout.exerciseDefinition?.businessID, businessID)
        XCTAssertEqual(workout.exercise, "虚构坐姿抬腿卷腹")
        XCTAssertEqual(workout.weight, 10)
        XCTAssertTrue(try plan.preview(in: context).pending.isEmpty)
    }

    @MainActor
    func testRepairMergesIntoRenamedTargetAndMigratesLinkedAndLegacyWorkouts() throws {
        let context = try makeContext()
        let source = try ExerciseLibraryStore.resolveOrCreateExact(canonicalName: "虚构弯举别名", in: context)
        let target = try ExerciseLibraryStore.resolveOrCreateExact(canonicalName: "虚构原弯举", in: context)
        let targetID = try XCTUnwrap(target.businessID)
        let linked = WorkoutEntry(exercise: source.canonicalName, exerciseID: source.id, sets: 3, reps: 8, weight: 10)
        let legacy = WorkoutEntry(exercise: source.canonicalName, sets: 2, reps: 6, weight: 8)
        let targetIDBefore = target.id
        let template = TemplateExercise(prescriptionGroupID: UUID(), exerciseID: source.id, order: 1)
        context.insert(linked)
        context.insert(legacy)
        context.insert(template)
        try context.save()
        let plan = try ExerciseMuscleRepair(entries: [
            .init(id: targetID, name: target.canonicalName, newName: "虚构规范弯举", primary: [.biceps], secondary: [])
        ], merges: [
            .init(sourceID: XCTUnwrap(source.businessID), sourceName: source.canonicalName, targetID: targetID, targetName: target.canonicalName)
        ])
        let preview = try plan.preview(in: context)
        XCTAssertEqual(preview.pendingMerges.count, 1)
        XCTAssertTrue(preview.unresolved.isEmpty)
        XCTAssertEqual(try plan.apply(preview, in: context), 2)
        XCTAssertEqual(ExerciseLibraryStore.activeDefinitions(in: context).map(\.id), [targetIDBefore])
        XCTAssertEqual(source.mergedIntoID, targetIDBefore)
        XCTAssertEqual(target.businessID, targetID)
        XCTAssertEqual(template.exerciseID, targetIDBefore)
        for workout in [linked, legacy] {
            XCTAssertEqual(workout.exerciseID, targetIDBefore)
            XCTAssertEqual(workout.exercise, "虚构规范弯举")
        }
        XCTAssertEqual(linked.weight, 10)
        XCTAssertEqual(legacy.weight, 8)
        XCTAssertEqual(try plan.preview(in: context).changeCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseMergeRecord>()), 1)
    }

    @MainActor
    func testAgentCreatesExerciseWithDurableIDsAndReadableLabels() throws {
        let context = try makeContext()
        let call = AgentToolCall(name: .createExercise, arguments: .init(exercises: [
            .init(exerciseName: "虚构划船变式", targetKind: .repetitions, laterality: .both,
                  primaryMuscleIDs: [.upperBack, .backDeltoids], secondaryMuscleIDs: [.biceps])
        ]))
        let result = ConversationRecorder.executeAgentTool(call, sourceText: "补一个虚构动作", mediaKind: .none, mediaPath: nil, in: context)
        XCTAssertTrue(result.ok, result.message)
        XCTAssertTrue(call.signature.contains("upper-back"))
        let reader = ModelContext(context.container)
        let definition = try XCTUnwrap(reader.fetch(FetchDescriptor<ExerciseDefinition>()).first)
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: definition.primaryMusclesData), ["upper-back", "back-deltoids"])
        XCTAssertEqual(definition.primaryMuscles, ["上背", "三角肌后束"])
        XCTAssertEqual(MuscleMapView.intensities(for: definition), [.upperBack: 1, .backDeltoids: 1, .biceps: 0.45])
        XCTAssertEqual(definition.laterality, .both)
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let suite = "ExerciseMuscleRepairTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        return try ModelContext(XCTUnwrap(spaces.personalContainer))
    }
}
