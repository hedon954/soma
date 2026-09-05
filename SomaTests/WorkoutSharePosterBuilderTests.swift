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
            "左 12kg · 8次 / 右 10kg · 8次 × 1组；左 12kg · 30秒 × 1组"
        )
    }

    func testEvidenceSummaryCompressesConsecutiveSetsIgnoringRest() {
        let evidence = (1 ... 5).map { index in
            WorkoutSetEvidence(logicalSetIndex: index, reps: 5, externalWeightKG: 60, restSeconds: index * 10)
        }
        XCTAssertEqual(WorkoutSharePosterBuilder.evidenceLoadSummary(evidence), "60kg · 5次 × 5组")
    }

    func testEvidenceSummaryKeepsEveryDifferentRunInOriginalOrder() {
        let weights: [Double] = [60, 60, 50, 60, 40, 30, 20]
        let evidence = weights.enumerated().map { index, weight in
            WorkoutSetEvidence(logicalSetIndex: 10 - index, reps: 5, externalWeightKG: weight)
        }
        XCTAssertEqual(
            WorkoutSharePosterBuilder.evidenceLoadSummary(evidence),
            "60kg · 5次 × 2组；50kg · 5次 × 1组；60kg · 5次 × 1组；40kg · 5次 × 1组；30kg · 5次 × 1组；20kg · 5次 × 1组"
        )
    }

    func testEvidenceSummaryKeepsLegacySetsAndMissingWeightDistinctFromBodyweight() {
        let evidence = [
            WorkoutSetEvidence(reps: 12),
            WorkoutSetEvidence(reps: 12),
            WorkoutSetEvidence(reps: 12, externalWeightKG: 0)
        ]
        XCTAssertEqual(
            WorkoutSharePosterBuilder.evidenceLoadSummary(evidence),
            "重量未记录 · 12次 × 2组；自重 · 12次 × 1组"
        )
        XCTAssertEqual(WorkoutSharePosterBuilder.evidenceLoadSummary([]), "—")
    }

    func testEvidenceSummaryCompressesMatchingSidesAndDuration() {
        let paired = (1 ... 3).flatMap { index in
            [WorkoutEffortSide.left, .right].map { side in
                WorkoutSetEvidence(logicalSetIndex: index, side: side, reps: 12, externalWeightKG: 0)
            }
        }
        XCTAssertEqual(WorkoutSharePosterBuilder.evidenceLoadSummary(paired), "左右各 自重 · 12次 × 3组")
        let timed = (1 ... 3).map { index in
            WorkoutSetEvidence(logicalSetIndex: index, targetKind: .duration, durationSeconds: 30, externalWeightKG: 0)
        }
        XCTAssertEqual(WorkoutSharePosterBuilder.evidenceLoadSummary(timed), "自重 · 30秒 × 3组")
    }

    func testEvidenceSummaryDoesNotMergeSetKindsOrDifferentReps() {
        let evidence = [
            WorkoutSetEvidence(logicalSetIndex: 1, kind: .warmup, reps: 5, externalWeightKG: 20),
            WorkoutSetEvidence(logicalSetIndex: 2, kind: .working, reps: 5, externalWeightKG: 20),
            WorkoutSetEvidence(logicalSetIndex: 3, kind: .working, reps: 3, externalWeightKG: 20)
        ]
        XCTAssertEqual(
            WorkoutSharePosterBuilder.evidenceLoadSummary(evidence),
            "热身组 20kg · 5次 × 1组；20kg · 5次 × 1组；20kg · 3次 × 1组"
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
        XCTAssertEqual(model.exercises.first?.loadSummary, "10kg · 5次 × 1组")
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
