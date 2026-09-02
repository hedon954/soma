@testable import Soma
import SwiftData
import XCTest

final class GuidedWorkoutScreenSnapshotTests: XCTestCase {
    @MainActor
    func testDiskSnapshotLoadsOnlyScalarIDGraphForRequestedSession() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuidedSnapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let schema = Schema(SomaDataSchema.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                "GuidedSnapshot",
                schema: schema,
                url: directory.appendingPathComponent("snapshot.store"),
                cloudKitDatabase: .none
            )]
        )
        let context = container.mainContext
        let first = try insertSession(
            name: "虚构左侧动作",
            order: 1,
            side: .left,
            in: context
        )
        _ = try insertSession(
            name: "虚构右侧动作",
            order: 2,
            side: .right,
            in: context
        )
        try context.save()

        let snapshot = try GuidedWorkoutScreenSnapshotLoader.load(
            sessionID: first.session.id,
            from: container
        )

        XCTAssertEqual(snapshot.session.id, first.session.id)
        XCTAssertEqual(snapshot.performances.map(\.id), [first.performance.id])
        XCTAssertEqual(snapshot.sets.map(\.id), [first.set.id])
        XCTAssertEqual(snapshot.efforts.map(\.id), [first.effort.id])
        XCTAssertEqual(snapshot.currentPerformance?.exerciseName, "虚构左侧动作")
        XCTAssertEqual(snapshot.currentEffort?.side, .left)
        XCTAssertEqual(snapshot.completedSetCount, 0)
        XCTAssertEqual(snapshot.progressExercises.count, 1)
    }

    @MainActor
    func testSnapshotKeepsLastKnownValuesIndependentFromLaterModelMutation() throws {
        let container = try ModelContainer(
            for: Schema(SomaDataSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let fixture = try insertSession(
            name: "虚构稳定动作",
            order: 1,
            side: .none,
            in: container.mainContext
        )
        try container.mainContext.save()
        let original = try GuidedWorkoutScreenSnapshotLoader.load(
            sessionID: fixture.session.id,
            from: container
        )

        fixture.performance.exerciseName = "虚构已变化动作"
        fixture.effort.actualReps = 99
        try container.mainContext.save()

        XCTAssertEqual(original.currentPerformance?.exerciseName, "虚构稳定动作")
        XCTAssertEqual(original.currentEffort?.actualReps, nil)
        let refreshed = try GuidedWorkoutScreenSnapshotLoader.load(
            sessionID: fixture.session.id,
            from: container
        )
        XCTAssertEqual(refreshed.currentPerformance?.exerciseName, "虚构已变化动作")
        XCTAssertEqual(refreshed.currentEffort?.actualReps, 99)
    }

    @MainActor
    func testReplacementChoicesAreImmutableAndExcludeArchivedExercises() throws {
        let container = try ModelContainer(
            for: Schema(SomaDataSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let visible = ExerciseDefinition(canonicalName: "虚构可替换动作")
        let archived = ExerciseDefinition(canonicalName: "虚构已归档动作")
        archived.archivedAt = Date(timeIntervalSince1970: 100)
        container.mainContext.insert(visible)
        container.mainContext.insert(archived)
        try container.mainContext.save()

        let choices = try GuidedWorkoutScreenSnapshotLoader
            .replacementChoices(from: container)
        visible.canonicalName = "虚构已修改名称"

        XCTAssertEqual(choices.map(\.id), [visible.id])
        XCTAssertEqual(choices.map(\.name), ["虚构可替换动作"])
    }

    @MainActor
    func testRecordProjectionUsesMatchingScalarSessionAndPerformanceIDs() throws {
        let container = try ModelContainer(
            for: Schema(SomaDataSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let matching = try insertSession(
            name: "虚构标量投影动作",
            order: 1,
            side: .none,
            in: container.mainContext
        )
        let other = try insertSession(
            name: "虚构其他训练动作",
            order: 2,
            side: .none,
            in: container.mainContext
        )
        matching.performance.status = .completed
        matching.set.status = .completed
        matching.effort.status = .completed
        matching.effort.actualReps = 12
        matching.effort.actualWeightKG = 0
        try container.mainContext.save()

        XCTAssertThrowsError(try GuidedWorkoutRecordStore.materialize(
            performanceID: matching.performance.id,
            sessionID: other.session.id,
            in: container.mainContext
        )) { error in
            XCTAssertEqual(error as? GuidedWorkoutError, .missingPerformance)
        }
        let entry = try XCTUnwrap(GuidedWorkoutRecordStore.materialize(
            performanceID: matching.performance.id,
            sessionID: matching.session.id,
            in: container.mainContext
        ))
        XCTAssertEqual(entry.sourcePerformanceID, matching.performance.id)
        XCTAssertEqual(entry.sourceWorkoutSessionID, matching.session.id)
    }

    @MainActor
    private func insertSession(
        name: String,
        order: Int,
        side: WorkoutEffortSide,
        in context: ModelContext
    ) throws -> (
        session: WorkoutSession,
        performance: ExercisePerformance,
        set: WorkoutSet,
        effort: WorkoutEffort
    ) {
        let exercise = ExerciseDefinition(canonicalName: name)
        let prescription = TemplateExercisePrescription(
            exerciseID: exercise.id,
            exerciseName: name,
            order: 1,
            targetSets: 1,
            targetReps: 12,
            targetWeightKG: 0,
            targetRestSeconds: 60,
            laterality: side == .none ? .none : .both
        )
        let session = WorkoutSession(
            startedAt: Date(timeIntervalSince1970: 1_788_280_000 + Double(order)),
            prescriptionSnapshot: [prescription],
            status: .active,
            guidedPhase: .setInProgress
        )
        let performance = ExercisePerformance(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: name,
            order: 1,
            prescriptionSnapshot: prescription,
            status: .active
        )
        let set = WorkoutSet(
            performanceID: performance.id,
            order: 1,
            plannedReps: 12,
            plannedWeightKG: 0,
            plannedRestSeconds: 60,
            status: .inProgress
        )
        let effort = WorkoutEffort(
            workoutSetID: set.id,
            order: 1,
            side: side,
            plannedReps: 12,
            plannedWeightKG: 0,
            status: .inProgress
        )
        session.currentPerformanceID = performance.id
        session.currentSetID = set.id
        session.currentEffortID = effort.id
        context.insert(exercise)
        context.insert(session)
        context.insert(performance)
        context.insert(set)
        context.insert(effort)
        return (session, performance, set, effort)
    }
}
