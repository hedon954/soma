import CryptoKit
@testable import Soma
import SwiftData
import XCTest

final class TrainingDomainV5Tests: XCTestCase {
    func testPrescriptionDraftOnlyPersistsWeightsForSelectedLaterality() throws {
        let exerciseID = UUID()
        let set = TrainingSetPrescriptionDraft(
            order: 1,
            reps: "10",
            weight: "20",
            leftWeight: "11",
            rightWeight: "12"
        )

        func value(for laterality: ExerciseLaterality) throws
            -> TemplateSetPrescriptionValue
        {
            let draft = TrainingPrescriptionDraft(
                exerciseID: exerciseID,
                laterality: laterality,
                plannedSets: [set]
            )
            return try XCTUnwrap(
                draft.prescription(
                    order: 1,
                    names: [exerciseID: "虚构动作"]
                ).plannedSets.first
            )
        }

        let none = try value(for: .none)
        XCTAssertEqual(none.targetWeightKG, 20)
        XCTAssertNil(none.leftWeightKG)
        XCTAssertNil(none.rightWeightKG)

        let both = try value(for: .both)
        XCTAssertNil(both.targetWeightKG)
        XCTAssertEqual(both.leftWeightKG, 11)
        XCTAssertEqual(both.rightWeightKG, 12)

        let left = try value(for: .left)
        XCTAssertNil(left.targetWeightKG)
        XCTAssertEqual(left.leftWeightKG, 11)
        XCTAssertNil(left.rightWeightKG)

        let right = try value(for: .right)
        XCTAssertNil(right.targetWeightKG)
        XCTAssertNil(right.leftWeightKG)
        XCTAssertEqual(right.rightWeightKG, 12)
    }

    func testLegacyPrescriptionSnapshotDecodesAsNoneLateralityAndIndependentSets() throws {
        let exerciseID = UUID()
        let legacy: [String: Any] = [
            "id": UUID().uuidString,
            "exerciseID": exerciseID.uuidString,
            "exerciseName": "虚构深蹲",
            "order": 1,
            "targetSets": 3,
            "targetReps": 8,
            "targetWeightKG": 30,
            "targetRestSeconds": 60,
            "firstSetIsWarmup": true,
            "notes": ""
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(
            TemplateExercisePrescription.self,
            from: data
        )

        XCTAssertEqual(decoded.laterality, .none)
        XCTAssertEqual(decoded.plannedSets.count, 3)
        XCTAssertEqual(decoded.plannedSets.map(\.kind), [.warmup, .working, .working])
        XCTAssertEqual(decoded.plannedSets.first?.restAfterSetSeconds, 60)
        XCTAssertNil(decoded.plannedSets.last?.restAfterSetSeconds)
    }

    @MainActor
    func testIndependentSetsCompileBothSidesIntoOrderedEfforts() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构单侧推举",
            in: fixture.context
        )
        let program = try TrainingPlanStore.createProgram(
            name: "左右独立",
            goal: "逐侧训练",
            prescriptions: [
                TemplateExercisePrescription(
                    exerciseID: exercise.id,
                    exerciseName: exercise.canonicalName,
                    order: 1,
                    targetSets: 2,
                    targetReps: nil,
                    laterality: .both,
                    plannedSets: [
                        TemplateSetPrescriptionValue(
                            order: 1,
                            kind: .warmup,
                            targetKind: .repetitions,
                            targetReps: 10,
                            leftWeightKG: 8,
                            rightWeightKG: 9,
                            restBetweenSidesSeconds: 15,
                            restAfterSetSeconds: 45
                        ),
                        TemplateSetPrescriptionValue(
                            order: 2,
                            targetKind: .duration,
                            targetDurationSeconds: 30,
                            leftWeightKG: 10,
                            rightWeightKG: 11
                        )
                    ]
                )
            ],
            in: fixture.context
        )
        try TrainingPlanStore.updateOverview(
            "  左右重量独立。  ",
            for: program,
            in: fixture.context
        )
        XCTAssertEqual(program.overview, "左右重量独立。")
        XCTAssertEqual(program.goal, program.overview)

        let snapshot = try XCTUnwrap(
            TrainingPlanStore.prescriptions(for: program, in: fixture.context).first
        )
        XCTAssertEqual(snapshot.laterality, .both)
        XCTAssertEqual(snapshot.plannedSets.map(\.targetKind), [.repetitions, .duration])
        let storedSets = try fixture.context.fetch(
            FetchDescriptor<TemplateSetPrescription>()
        )
        XCTAssertEqual(storedSets.count, 2)
        XCTAssertTrue(storedSets.allSatisfy { $0.businessID != nil })
        XCTAssertTrue(storedSets.allSatisfy { $0.templateExercise != nil })
        let storedExercise = try XCTUnwrap(program.templateExercises.first)
        XCTAssertEqual(storedExercise.program?.id, program.id)
        XCTAssertEqual(
            Set(storedExercise.setPrescriptions.map(\.id)),
            Set(storedSets.map(\.id))
        )

        let session = try TrainingPlanStore.startSession(
            program: program,
            in: fixture.context
        )
        let logicalSets = try fixture.context.fetch(FetchDescriptor<WorkoutSet>())
            .sorted { $0.order < $1.order }
        let efforts = try fixture.context.fetch(FetchDescriptor<WorkoutEffort>())
            .sorted {
                if $0.workoutSetID == $1.workoutSetID {
                    return $0.order < $1.order
                }
                return $0.workoutSetID.uuidString < $1.workoutSetID.uuidString
            }
        XCTAssertEqual(logicalSets.count, 2)
        XCTAssertEqual(efforts.count, 4)
        XCTAssertEqual(Set(efforts.map(\.side)), [.left, .right])
        XCTAssertEqual(
            efforts.filter { $0.workoutSetID == logicalSets[0].id }
                .sorted { $0.order < $1.order }
                .map(\.plannedWeightKG),
            [8, 9]
        )
        XCTAssertEqual(logicalSets[1].plannedTargetKind, .duration)
        XCTAssertEqual(logicalSets[1].plannedDurationSeconds, 30)
        XCTAssertEqual(session.currentSetID, logicalSets.first?.id)
        XCTAssertNotNil(session.currentEffortID)
        XCTAssertTrue(efforts.allSatisfy { $0.businessID != nil })
        XCTAssertTrue(efforts.allSatisfy { $0.workoutSet != nil })
        let performance = try XCTUnwrap(session.performances.first)
        XCTAssertEqual(performance.session?.id, session.id)
        XCTAssertEqual(
            Set(performance.workoutSets.map(\.id)),
            Set(logicalSets.map(\.id))
        )
        XCTAssertTrue(logicalSets.allSatisfy { !$0.efforts.isEmpty })
    }

    @MainActor
    func testTrainingCompositionRelationshipsCascadeWithinOwnedGraphs() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构硬拉",
            in: fixture.context
        )
        let program = try TrainingPlanStore.createProgram(
            name: "关系计划",
            prescriptions: [TemplateExercisePrescription(
                exerciseID: exercise.id,
                exerciseName: exercise.canonicalName,
                order: 1,
                plannedSets: [TemplateSetPrescriptionValue(
                    order: 1,
                    targetReps: 5
                )]
            )],
            in: fixture.context
        )
        let session = try TrainingPlanStore.startSession(
            program: program,
            in: fixture.context
        )

        fixture.context.delete(program)
        try fixture.context.save()
        XCTAssertTrue(try fixture.context.fetch(
            FetchDescriptor<TemplateExercise>()
        ).isEmpty)
        XCTAssertTrue(try fixture.context.fetch(
            FetchDescriptor<TemplateSetPrescription>()
        ).isEmpty)
        XCTAssertEqual(try fixture.context.fetch(
            FetchDescriptor<WorkoutSession>()
        ).map(\.id), [session.id])

        fixture.context.delete(session)
        try fixture.context.save()
        XCTAssertTrue(try fixture.context.fetch(
            FetchDescriptor<ExercisePerformance>()
        ).isEmpty)
        XCTAssertTrue(try fixture.context.fetch(
            FetchDescriptor<WorkoutSet>()
        ).isEmpty)
        XCTAssertTrue(try fixture.context.fetch(
            FetchDescriptor<WorkoutEffort>()
        ).isEmpty)
    }

    @MainActor
    func testProjectionUsesEffortEvidenceDateWeightAndUniqueRelationship() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构深蹲",
            in: fixture.context
        )
        let sessionDate = Date(timeIntervalSince1970: 10000)
        fixture.context.insert(BodyEntry(
            date: Date(timeIntervalSince1970: 9000),
            weight: 60
        ))
        fixture.context.insert(BodyEntry(
            date: Date(timeIntervalSince1970: 11000),
            weight: 100
        ))
        let prescription = TemplateExercisePrescription(
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            targetSets: 1,
            laterality: .both,
            plannedSets: [
                TemplateSetPrescriptionValue(
                    order: 1,
                    targetKind: .repetitions,
                    targetReps: 5,
                    leftWeightKG: 20,
                    rightWeightKG: 22
                )
            ]
        )
        let session = WorkoutSession(
            startedAt: sessionDate,
            prescriptionSnapshot: [prescription],
            status: .active
        )
        let performance = ExercisePerformance(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            prescriptionSnapshot: prescription,
            status: .completed
        )
        performance.exerciseDefinition = exercise
        let set = WorkoutSet(
            performanceID: performance.id,
            order: 1,
            laterality: ExerciseLaterality.both.rawValue,
            actualRestSeconds: 30,
            status: .completed
        )
        set.performance = performance
        let left = WorkoutEffort(
            workoutSetID: set.id,
            order: 1,
            side: .left,
            actualReps: 5,
            actualWeightKG: 20,
            status: .completed,
            recordedVideoPath: "fictional-left.mov"
        )
        let right = WorkoutEffort(
            workoutSetID: set.id,
            order: 2,
            side: .right,
            targetKind: .duration,
            actualDurationSeconds: 20,
            actualWeightKG: 22,
            status: .completed,
            recordedVideoPath: "fictional-right.mov"
        )
        left.workoutSet = set
        right.workoutSet = set
        fixture.context.insert(session)
        fixture.context.insert(performance)
        fixture.context.insert(set)
        fixture.context.insert(left)
        fixture.context.insert(right)

        let entry = try XCTUnwrap(GuidedWorkoutRecordStore.materialize(
            performance: performance,
            session: session,
            in: fixture.context
        ))
        try fixture.context.save()
        let replay = try XCTUnwrap(GuidedWorkoutRecordStore.materialize(
            performance: performance,
            session: session,
            in: fixture.context
        ))

        XCTAssertEqual(replay.id, entry.id)
        XCTAssertNotNil(entry.businessID)
        XCTAssertEqual(entry.exerciseDefinition?.id, exercise.id)
        XCTAssertEqual(entry.sourcePerformance?.id, performance.id)
        XCTAssertEqual(performance.projectedWorkout?.id, entry.id)
        XCTAssertEqual(entry.setCount, 1)
        XCTAssertEqual(entry.setEntries.map(\.side), [.left, .right])
        XCTAssertEqual(entry.setEntries.map(\.recordedVideoPath), [
            "fictional-left.mov",
            "fictional-right.mov"
        ])
        // 5 reps × 4s fallback + 20 actual seconds + 30 rest = 70s.
        XCTAssertEqual(entry.calorieDurationMinutes ?? 0, 70.0 / 60.0, accuracy: 0.001)
        XCTAssertTrue(entry.calorieDurationEstimated)
        XCTAssertNotNil(entry.estimatedCalories)
    }

    @MainActor
    func testProjectionClosesCompletedAndFailedSetsButSkipsAllFailedPerformance() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构划船",
            in: fixture.context
        )
        let prescription = TemplateExercisePrescription(
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            plannedSets: [
                TemplateSetPrescriptionValue(order: 1, targetReps: 8),
                TemplateSetPrescriptionValue(order: 2, targetReps: 8)
            ]
        )
        let session = WorkoutSession(
            prescriptionSnapshot: [prescription],
            status: .completed
        )
        fixture.context.insert(session)

        let mixed = ExercisePerformance(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            prescriptionSnapshot: prescription,
            status: .completed
        )
        mixed.exerciseDefinition = exercise
        mixed.session = session
        let completedSet = WorkoutSet(
            performanceID: mixed.id,
            order: 1,
            actualReps: 8,
            actualWeightKG: 20,
            status: .completed
        )
        completedSet.performance = mixed
        let completedEffort = WorkoutEffort(
            workoutSetID: completedSet.id,
            order: 1,
            actualReps: 8,
            actualWeightKG: 20,
            status: .completed
        )
        completedEffort.workoutSet = completedSet
        let failedSet = WorkoutSet(
            performanceID: mixed.id,
            order: 2,
            status: .failed
        )
        failedSet.performance = mixed
        let failedEffort = WorkoutEffort(
            workoutSetID: failedSet.id,
            order: 1,
            status: .failed
        )
        failedEffort.workoutSet = failedSet
        fixture.context.insert(mixed)
        fixture.context.insert(completedSet)
        fixture.context.insert(completedEffort)
        fixture.context.insert(failedSet)
        fixture.context.insert(failedEffort)

        let mixedProjection = try XCTUnwrap(GuidedWorkoutRecordStore.materialize(
            performance: mixed,
            session: session,
            in: fixture.context
        ))
        XCTAssertEqual(mixedProjection.setEntries.count, 1)
        XCTAssertEqual(mixedProjection.setEntries.first?.logicalSetIndex, 1)

        let failedOnly = ExercisePerformance(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 2,
            prescriptionSnapshot: prescription,
            status: .skipped
        )
        failedOnly.exerciseDefinition = exercise
        failedOnly.session = session
        let onlySet = WorkoutSet(
            performanceID: failedOnly.id,
            order: 1,
            status: .failed
        )
        onlySet.performance = failedOnly
        let onlyEffort = WorkoutEffort(
            workoutSetID: onlySet.id,
            order: 1,
            status: .failed
        )
        onlyEffort.workoutSet = onlySet
        fixture.context.insert(failedOnly)
        fixture.context.insert(onlySet)
        fixture.context.insert(onlyEffort)

        XCTAssertNil(try GuidedWorkoutRecordStore.materialize(
            performance: failedOnly,
            session: session,
            in: fixture.context
        ))
        XCTAssertNil(failedOnly.projectedWorkout)
    }

    @MainActor
    func testProjectionCarriesSkippedSideRestIntoCompletedSideCalories() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构单侧训练",
            in: fixture.context
        )
        let date = Date(timeIntervalSince1970: 50000)
        fixture.context.insert(BodyEntry(
            date: date.addingTimeInterval(-60),
            weight: 60
        ))
        let prescription = TemplateExercisePrescription(
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            laterality: .both,
            plannedSets: [TemplateSetPrescriptionValue(
                order: 1,
                targetKind: .duration,
                targetDurationSeconds: 20
            )]
        )
        let session = WorkoutSession(
            startedAt: date,
            prescriptionSnapshot: [prescription],
            status: .completed
        )
        let performance = ExercisePerformance(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            prescriptionSnapshot: prescription,
            status: .completed
        )
        performance.exerciseDefinition = exercise
        performance.session = session
        let set = WorkoutSet(
            performanceID: performance.id,
            order: 1,
            laterality: ExerciseLaterality.both.rawValue,
            plannedTargetKind: .duration,
            status: .partial
        )
        set.performance = performance
        let skippedLeft = WorkoutEffort(
            workoutSetID: set.id,
            order: 1,
            side: .left,
            targetKind: .duration,
            actualRestSeconds: 15,
            status: .skipped
        )
        skippedLeft.workoutSet = set
        let completedRight = WorkoutEffort(
            workoutSetID: set.id,
            order: 2,
            side: .right,
            targetKind: .duration,
            actualDurationSeconds: 20,
            status: .completed
        )
        completedRight.workoutSet = set
        fixture.context.insert(session)
        fixture.context.insert(performance)
        fixture.context.insert(set)
        fixture.context.insert(skippedLeft)
        fixture.context.insert(completedRight)

        let entry = try XCTUnwrap(GuidedWorkoutRecordStore.materialize(
            performance: performance,
            session: session,
            in: fixture.context
        ))
        XCTAssertEqual(entry.setEntries.count, 1)
        XCTAssertEqual(entry.setEntries.first?.side, .right)
        XCTAssertEqual(entry.setEntries.first?.restSeconds, 15)
        XCTAssertEqual(
            entry.calorieDurationMinutes ?? 0,
            35.0 / 60.0,
            accuracy: 0.001
        )
        XCTAssertEqual(entry.calorieDurationEstimated, false)
    }

    @MainActor
    func testSummaryUsesCanonicalProjectionAndDoesNotReviveSuppressedDuplicates() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "虚构汇总动作",
            in: fixture.context
        )
        let prescription = TemplateExercisePrescription(
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            plannedSets: [TemplateSetPrescriptionValue(order: 1, targetReps: 5)]
        )
        let session = WorkoutSession(
            prescriptionSnapshot: [prescription],
            status: .completed
        )
        fixture.context.insert(session)

        func makePerformance(order: Int) -> (ExercisePerformance, WorkoutSet) {
            let performance = ExercisePerformance(
                sessionID: session.id,
                exerciseID: exercise.id,
                exerciseName: "\(exercise.canonicalName) \(order)",
                order: order,
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
                status: .completed
            )
            set.performance = performance
            fixture.context.insert(performance)
            fixture.context.insert(set)
            return (performance, set)
        }

        let first = makePerformance(order: 1)
        let second = makePerformance(order: 2)
        let canonicalFirst = WorkoutEntry(
            exercise: first.0.exerciseName,
            exerciseID: exercise.id,
            setEntries: [WorkoutSetEvidence(reps: 5, externalWeightKG: 10)],
            estimatedCalories: 10,
            sourceWorkoutSessionID: session.id,
            sourcePerformanceID: first.0.id,
            projectionKey: SomaDataMigration.projectionKey(for: first.0.id)
        )
        canonicalFirst.sourcePerformance = first.0
        first.0.projectedWorkout = canonicalFirst
        let staleDuplicate = WorkoutEntry(
            exercise: first.0.exerciseName,
            exerciseID: exercise.id,
            setEntries: [WorkoutSetEvidence(reps: 100, externalWeightKG: 100)],
            estimatedCalories: 999,
            sourceWorkoutSessionID: session.id,
            sourcePerformanceID: first.0.id
        )
        let canonicalSecond = WorkoutEntry(
            exercise: second.0.exerciseName,
            exerciseID: exercise.id,
            setEntries: [WorkoutSetEvidence(reps: 5, externalWeightKG: 10)],
            estimatedCalories: nil,
            sourceWorkoutSessionID: session.id,
            sourcePerformanceID: second.0.id,
            projectionKey: SomaDataMigration.projectionKey(for: second.0.id)
        )
        canonicalSecond.sourcePerformance = second.0
        second.0.projectedWorkout = canonicalSecond
        fixture.context.insert(canonicalFirst)
        fixture.context.insert(staleDuplicate)
        fixture.context.insert(canonicalSecond)
        try fixture.context.save()

        var summary = TrainingPlanStore.summary(for: session.id, in: fixture.context)
        XCTAssertNil(summary.estimatedCalories)
        XCTAssertEqual(summary.exercises.first?.completedVolume, 50)
        XCTAssertEqual(summary.completedVolume, 100)

        canonicalSecond.estimatedCalories = 5
        summary = TrainingPlanStore.summary(for: session.id, in: fixture.context)
        XCTAssertEqual(summary.estimatedCalories, 15)

        first.0.workoutProjectionSuppressed = true
        summary = TrainingPlanStore.summary(for: session.id, in: fixture.context)
        XCTAssertNil(summary.estimatedCalories)
        XCTAssertEqual(summary.exercises.first?.completedVolume, 0)
        XCTAssertEqual(summary.completedVolume, 50)
    }
}

extension TrainingDomainV5Tests {
    @MainActor
    func testLaunchMigrationExpandsLegacyRowsAndIsIdempotent() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let exercise = ExerciseDefinition(canonicalName: "虚构旧动作")
        let program = TrainingProgram(name: "旧计划", goal: "旧概览")
        let templateExercise = TemplateExercise(
            prescriptionGroupID: program.prescriptionGroupID ?? program.id,
            exerciseID: exercise.id,
            order: 1,
            targetSets: 2,
            targetReps: 8,
            targetRestSeconds: 60
        )
        templateExercise.program = program
        let snapshot = TemplateExercisePrescription(
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            targetSets: 2,
            targetReps: 8,
            targetRestSeconds: 60
        )
        let session = WorkoutSession(
            prescriptionSnapshot: [snapshot],
            status: .completed
        )
        let performance = ExercisePerformance(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            prescriptionSnapshot: snapshot,
            status: .completed
        )
        let first = WorkoutSet(
            performanceID: performance.id,
            order: 1,
            plannedReps: 8,
            plannedRestSeconds: 60,
            actualReps: 8,
            actualRestSeconds: 50,
            status: .completed
        )
        let second = WorkoutSet(
            performanceID: performance.id,
            order: 2,
            plannedReps: 8,
            plannedRestSeconds: 70,
            actualReps: 8,
            actualRestSeconds: 55,
            status: .completed
        )
        fixture.context.insert(exercise)
        fixture.context.insert(program)
        fixture.context.insert(templateExercise)
        fixture.context.insert(session)
        fixture.context.insert(performance)
        fixture.context.insert(first)
        fixture.context.insert(second)
        fixture.context.insert(DataMigrationMarker(schemaVersion: 4))
        try fixture.context.save()

        try SomaDataMigration.migrateIfNeeded(
            container: fixture.container,
            dataSpace: .personal
        )
        try SomaDataMigration.migrateIfNeeded(
            container: fixture.container,
            dataSpace: .personal
        )

        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<TemplateSetPrescription>()).count,
            2
        )
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<WorkoutEffort>()).count,
            2
        )
        let migratedSets = try fixture.context.fetch(FetchDescriptor<WorkoutSet>())
            .filter { $0.performanceID == performance.id }
            .sorted { $0.order < $1.order }
        XCTAssertEqual(migratedSets[0].plannedRestSeconds, 70)
        XCTAssertEqual(migratedSets[0].actualRestSeconds, 55)
        XCTAssertNil(migratedSets[1].plannedRestSeconds)
        XCTAssertNil(migratedSets[1].actualRestSeconds)
        XCTAssertEqual(program.overview, "旧概览")
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<DataMigrationMarker>())
                .first?.schemaVersion,
            6
        )
    }

    @MainActor
    func testCompletedV5MarkerStillRepairsNilProjectionKeys() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let names = ["虚构旧深蹲", "虚构旧卧推", "虚构旧硬拉"]
        for name in names {
            let workout = WorkoutEntry(exercise: name)
            workout.projectionKey = nil
            fixture.context.insert(workout)
            try fixture.context.save()
        }
        fixture.context.insert(DataMigrationMarker(schemaVersion: 5))
        try fixture.context.save()

        try SomaDataMigration.migrateIfNeeded(
            container: fixture.container,
            dataSpace: .personal
        )

        let workouts = try fixture.context.fetch(FetchDescriptor<WorkoutEntry>())
        XCTAssertEqual(workouts.count, 3)
        let keys = workouts.compactMap(\.projectionKey)
        XCTAssertEqual(keys.count, 3)
        XCTAssertEqual(Set(keys).count, 3)
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<DataMigrationMarker>())
                .first?.schemaVersion,
            6
        )
    }

    func testStorePreflightFormatsUUIDBlobHexAsEntryKey() {
        XCTAssertEqual(
            SomaStorePreflight.entryKey(
                fromUUIDBlobHex: "A1B2C3D4E5F60718293A4B5C6D7E8F90"
            ),
            "entry:a1b2c3d4-e5f6-0718-293a-4b5c6d7e8f90"
        )
        XCTAssertNil(SomaStorePreflight.entryKey(fromUUIDBlobHex: "zz"))
    }

    @MainActor
    func testStorePreflightRepairsNilProjectionKeysOnDiskBeforeLaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SomaPreflight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("legacy.store")
        let expectedIDs: [UUID]
        do {
            let schema = Schema(SomaDataSchema.models)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(
                    "PreflightSource",
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: .none
                )]
            )
            var ids: [UUID] = []
            for name in ["虚构预修复深蹲", "虚构预修复卧推", "虚构预修复硬拉"] {
                let workout = WorkoutEntry(exercise: name)
                workout.projectionKey = nil
                container.mainContext.insert(workout)
                try container.mainContext.save()
                ids.append(workout.id)
            }
            container.mainContext.insert(DataMigrationMarker(schemaVersion: 5))
            try container.mainContext.save()
            expectedIDs = ids
        }

        try SomaStorePreflight.repairProjectionKeysIfNeeded(at: storeURL)

        let schema = Schema(SomaDataSchema.models)
        let repaired = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                "PreflightRepaired",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )]
        )
        try SomaDataMigration.migrateIfNeeded(
            container: repaired,
            dataSpace: .personal
        )
        let workouts = try repaired.mainContext.fetch(FetchDescriptor<WorkoutEntry>())
        XCTAssertEqual(workouts.count, 3)
        let keys = Set(workouts.compactMap(\.projectionKey))
        XCTAssertEqual(keys.count, 3)
        XCTAssertEqual(
            Set(expectedIDs.map(SomaDataMigration.entryKey(for:))),
            keys
        )
    }

    @MainActor
    func testMissingTargetRepsRemainsNilAndBlocksSessionStart() throws {
        let fixture = try makeContext()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let exercise = ExerciseDefinition(canonicalName: "虚构缺次数动作")
        let program = TrainingProgram(name: "缺次数计划", overview: "虚构概览")
        let prescriptionGroupID = program.prescriptionGroupID ?? program.id
        program.prescriptionGroupID = prescriptionGroupID
        let templateExercise = TemplateExercise(
            prescriptionGroupID: prescriptionGroupID,
            exerciseID: exercise.id,
            order: 1
        )
        templateExercise.program = program
        let first = TemplateSetPrescription(
            templateExerciseID: templateExercise.id,
            order: 1,
            targetReps: nil
        )
        let second = TemplateSetPrescription(
            templateExerciseID: templateExercise.id,
            order: 2,
            targetReps: nil
        )
        fixture.context.insert(exercise)
        fixture.context.insert(program)
        fixture.context.insert(templateExercise)
        fixture.context.insert(first)
        fixture.context.insert(second)
        try fixture.context.save()

        let fetchedProgram = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<TrainingProgram>()).first
        )
        let prescription = try XCTUnwrap(
            TrainingPlanStore.prescriptions(for: fetchedProgram, in: fixture.context).first
        )
        XCTAssertEqual(prescription.plannedSets.count, 2)
        XCTAssertTrue(prescription.plannedSets.allSatisfy { $0.targetReps == nil })
        XCTAssertTrue(TrainingPlanStore.readiness(
            prescriptions: [prescription],
            autoRecordingPolicy: .disabled,
            in: fixture.context
        ).contains {
            $0.severity == .blocking && $0.message.contains("目标次数")
        })
        XCTAssertThrowsError(try TrainingPlanStore.startSession(
            program: fetchedProgram,
            in: fixture.context
        )) { error in
            XCTAssertEqual(error as? TrainingPlanError, .invalidValue("目标次数"))
        }
    }

    @MainActor
    private func makeContext() throws -> (
        context: ModelContext,
        container: ModelContainer,
        defaults: UserDefaults,
        suite: String
    ) {
        let suite = "TrainingDomainV5Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let container = try XCTUnwrap(spaces.personalContainer)
        return (ModelContext(container), container, defaults, suite)
    }
}
