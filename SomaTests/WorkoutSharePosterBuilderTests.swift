@testable import Soma
import SwiftData
import XCTest

final class WorkoutSharePosterBuilderTests: XCTestCase {
    private struct Fixture {
        var context: ModelContext
        var defaults: UserDefaults
        var suite: String
        var session: WorkoutSession
        var performances: [ExercisePerformance]
    }

    func testEvidenceSummaryKeepsBothSidesAndDuration() {
        let summary = WorkoutSharePosterBuilder.evidenceLoadSummary([
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: .left,
                targetKind: .repetitions,
                reps: 8,
                externalWeightKG: 12
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: .right,
                targetKind: .repetitions,
                reps: 8,
                externalWeightKG: 10
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 2,
                side: .left,
                targetKind: .duration,
                durationSeconds: 30,
                externalWeightKG: 12
            )
        ])

        XCTAssertEqual(
            summary,
            "左 12kg × 8 / 右 10kg × 8 · 左 12kg · 30秒"
        )
    }

    func testExerciseSummaryCollapsesUniformBodyweightSets() {
        let sets = (1 ... 5).map { order in
            WorkoutSet(
                performanceID: UUID(),
                order: order,
                plannedReps: 5,
                actualReps: 5,
                actualWeightKG: nil,
                status: .completed
            )
        }
        XCTAssertEqual(
            WorkoutSharePosterBuilder.exerciseSummary(for: sets),
            "5组 · 自重 × 5"
        )
    }

    func testExerciseSummaryCollapsesUniformLoadedSets() {
        let sets = (1 ... 2).map { order in
            WorkoutSet(
                performanceID: UUID(),
                order: order,
                plannedReps: 5,
                plannedWeightKG: 30,
                actualReps: 5,
                actualWeightKG: 30,
                status: .completed
            )
        }
        XCTAssertEqual(
            WorkoutSharePosterBuilder.exerciseSummary(for: sets),
            "2组 · 30kg × 5"
        )
    }

    func testExerciseSummaryJoinsVariedSetsAndTruncates() {
        let weights: [Double] = [30, 35, 40, 45, 50]
        let sets = weights.enumerated().map { index, weight in
            WorkoutSet(
                performanceID: UUID(),
                order: index + 1,
                plannedReps: 5,
                actualReps: 5,
                actualWeightKG: weight,
                status: .completed
            )
        }
        XCTAssertEqual(
            WorkoutSharePosterBuilder.exerciseSummary(for: sets),
            "5组 · 30kg × 5 · 35kg × 5 · 40kg × 5 · 45kg × 5 等"
        )
    }

    @MainActor
    func testProgramDisplayNameUsesSessionSnapshotName() throws {
        let session = WorkoutSession(
            programID: UUID(),
            programNameSnapshot: "基础力量训练",
            status: .completed
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutSession.self,
            configurations: configuration
        )
        let name = WorkoutSharePosterBuilder.programDisplayName(
            for: session,
            in: container.mainContext
        )
        XCTAssertEqual(name, "基础力量训练")
    }

    @MainActor
    func testProgramDisplayNameUsesCurrentProgramName() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutSession.self,
            TrainingProgram.self,
            configurations: configuration
        )
        let context = container.mainContext
        let program = TrainingProgram(name: "推日", status: .active)
        context.insert(program)
        let session = WorkoutSession(
            programID: program.id,
            status: .completed
        )
        context.insert(session)
        try context.save()

        XCTAssertEqual(
            TrainingPlanStore.programSourceLabel(for: session, in: context),
            "推日"
        )
        XCTAssertEqual(
            WorkoutSharePosterBuilder.programDisplayName(for: session, in: context),
            "推日"
        )
    }

    @MainActor
    func testPosterUsesCanonicalRelationshipInsteadOfStaleSourceIDDuplicate() throws {
        let fixture = try makePosterFixture(calories: [12])
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
        }
        let performance = try XCTUnwrap(fixture.performances.first)
        let staleDuplicate = WorkoutEntry(
            exercise: performance.exerciseName,
            exerciseID: performance.exerciseID,
            setEntries: [WorkoutSetEvidence(
                logicalSetIndex: 1,
                reps: 100,
                externalWeightKG: 100
            )],
            estimatedCalories: 999,
            sourceWorkoutSessionID: fixture.session.id,
            sourcePerformanceID: performance.id
        )
        fixture.context.insert(staleDuplicate)
        try fixture.context.save()

        let model = WorkoutSharePosterBuilder.makeModel(
            session: fixture.session,
            in: fixture.context
        )

        XCTAssertEqual(model.estimatedCalories, 12)
        XCTAssertEqual(model.volumeValue, "50")
        XCTAssertEqual(model.exercises.first?.loadSummary, "10kg × 5")
    }

    @MainActor
    func testPosterIgnoresSuppressedCanonicalProjection() throws {
        let fixture = try makePosterFixture(calories: [33])
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
        }
        let performance = try XCTUnwrap(fixture.performances.first)
        performance.workoutProjectionSuppressed = true
        try fixture.context.save()

        let model = WorkoutSharePosterBuilder.makeModel(
            session: fixture.session,
            in: fixture.context
        )

        XCTAssertNil(model.estimatedCalories)
        XCTAssertEqual(model.volumeValue, "—")
    }

    @MainActor
    func testPosterDoesNotSumCaloriesWhenAnyCanonicalProjectionIsMissingThem() throws {
        let fixture = try makePosterFixture(calories: [12, nil])
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
        }

        let model = WorkoutSharePosterBuilder.makeModel(
            session: fixture.session,
            in: fixture.context
        )

        XCTAssertNil(model.estimatedCalories)
        XCTAssertEqual(model.exerciseCount, 2)
    }

    @MainActor
    func testPosterDoesNotShowPartialCaloriesWhenCanonicalProjectionIsMissing() throws {
        let fixture = try makePosterFixture(calories: [12, 21])
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
        }
        let missingPerformance = try XCTUnwrap(fixture.performances.last)
        let missingProjection = try XCTUnwrap(
            missingPerformance.projectedWorkout
        )
        fixture.context.delete(missingProjection)
        try fixture.context.save()

        let model = WorkoutSharePosterBuilder.makeModel(
            session: fixture.session,
            in: fixture.context
        )

        XCTAssertNil(model.estimatedCalories)
        XCTAssertEqual(model.exerciseCount, 2)
    }

    @MainActor
    func testPosterSumsCaloriesOnlyWhenEveryProjectionIsCanonical() throws {
        let fixture = try makePosterFixture(calories: [12, 21])
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
        }

        let model = WorkoutSharePosterBuilder.makeModel(
            session: fixture.session,
            in: fixture.context
        )

        XCTAssertEqual(model.estimatedCalories, 33)
        XCTAssertEqual(model.exerciseCount, 2)
        XCTAssertEqual(model.volumeValue, "100")
    }

    @MainActor
    private func makePosterFixture(
        calories: [Int?]
    ) throws -> Fixture {
        let suite = "WorkoutSharePosterBuilderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let container = try XCTUnwrap(spaces.personalContainer)
        let context = ModelContext(container)
        let startedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let session = WorkoutSession(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(120),
            status: .completed,
            guidedPhase: .completed
        )
        context.insert(session)

        var performances: [ExercisePerformance] = []
        for (index, calories) in calories.enumerated() {
            let exercise = ExerciseDefinition(
                canonicalName: "虚构分享动作 \(index + 1)"
            )
            let prescription = TemplateExercisePrescription(
                exerciseID: exercise.id,
                exerciseName: exercise.canonicalName,
                order: index + 1,
                plannedSets: [TemplateSetPrescriptionValue(
                    order: 1,
                    targetReps: 5,
                    targetWeightKG: 10
                )]
            )
            let performance = ExercisePerformance(
                sessionID: session.id,
                exerciseID: exercise.id,
                exerciseName: exercise.canonicalName,
                order: index + 1,
                prescriptionSnapshot: prescription,
                status: .completed
            )
            performance.session = session
            performance.exerciseDefinition = exercise
            let set = WorkoutSet(
                performanceID: performance.id,
                order: 1,
                actualReps: 5,
                actualWeightKG: 10,
                status: .completed,
                completedAt: startedAt.addingTimeInterval(
                    TimeInterval(30 + index)
                )
            )
            set.performance = performance
            let projection = WorkoutEntry(
                date: startedAt,
                exercise: exercise.canonicalName,
                exerciseID: exercise.id,
                setEntries: [WorkoutSetEvidence(
                    logicalSetIndex: 1,
                    reps: 5,
                    externalWeightKG: 10
                )],
                estimatedCalories: calories,
                sourceWorkoutSessionID: session.id,
                sourcePerformanceID: performance.id,
                projectionKey: SomaDataMigration.projectionKey(
                    for: performance.id
                )
            )
            projection.sourcePerformance = performance
            performance.projectedWorkout = projection
            context.insert(exercise)
            context.insert(performance)
            context.insert(set)
            context.insert(projection)
            performances.append(performance)
        }
        try context.save()
        return Fixture(
            context: context,
            defaults: defaults,
            suite: suite,
            session: session,
            performances: performances
        )
    }
}
