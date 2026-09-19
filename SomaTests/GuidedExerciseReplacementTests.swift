@testable import Soma
import SwiftData
import XCTest

@MainActor
final class GuidedExerciseReplacementTests: XCTestCase {
    func testReplacementUsesNewExercisesLatestParametersAndRebuildsRuntimeTargets() async throws {
        let fixture = try GuidedWorkoutCoordinatorTests().makeFixture(firstSetIsWarmup: false, setCount: 3, recordingPolicy: .disabled)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let replacement = ExerciseDefinition(canonicalName: "虚构平板支撑")
        replacement.targetKind = .duration
        replacement.laterality = .none
        fixture.context.insert(replacement)
        fixture.context.insert(WorkoutEntry(
            date: fixture.now.addingTimeInterval(-100), exercise: replacement.canonicalName,
            exerciseID: replacement.id,
            setEntries: [.init(durationSeconds: 40, externalWeightKG: 0), .init(durationSeconds: 55, externalWeightKG: 0)],
            restSeconds: 45
        ))
        try fixture.context.save()
        let coordinator = GuidedWorkoutCoordinator(recorder: NoopWorkoutRecordingController(), cues: Cues(), now: { fixture.now })
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        let preview = try GuidedExerciseReplacementResolver.preview(
            exercise: replacement, excluding: fixture.session.id, in: fixture.context
        )
        try coordinator.replaceCurrentExercise(
            with: replacement, prescription: preview.prescription, in: fixture.context
        )
        let performanceID = fixture.performance.id
        let sets = try fixture.context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.performanceID == performanceID }, sortBy: [SortDescriptor(\.order)]
        ))
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets.map(\.plannedDurationSeconds), [40, 55])
        XCTAssertTrue(sets.allSatisfy { $0.plannedReps == nil && $0.plannedTargetKind == .duration })
        XCTAssertEqual(sets.map(\.plannedRestSeconds), [45, nil])
        XCTAssertEqual(fixture.performance.prescriptionSnapshot?.plannedSets.count, 2)
        XCTAssertEqual(fixture.session.currentSetID, sets.first?.id)
    }

    func testNoHistoryLeavesBlankTargetsAndDoesNotMutateCurrentExercise() throws {
        let fixture = try GuidedWorkoutCoordinatorTests().makeFixture(firstSetIsWarmup: false, setCount: 2)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let replacement = ExerciseDefinition(canonicalName: "虚构新动作")
        replacement.targetKind = .duration
        fixture.context.insert(replacement)
        try fixture.context.save()
        let oldName = fixture.performance.exerciseName
        let preview = try GuidedExerciseReplacementResolver.preview(
            exercise: replacement, excluding: fixture.session.id, in: fixture.context
        )
        XCTAssertNil(preview.sourceDate)
        XCTAssertEqual(preview.prescription.plannedSets.count, 1)
        XCTAssertNil(preview.prescription.plannedSets[0].targetDurationSeconds)
        XCTAssertNil(preview.prescription.plannedSets[0].targetReps)
        XCTAssertNil(preview.prescription.plannedSets[0].targetWeightKG)
        XCTAssertNil(preview.prescription.targetRestSeconds)
        XCTAssertEqual(fixture.performance.exerciseName, oldName)
        XCTAssertEqual(fixture.sets[0].plannedWeightKG, 20)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testLatestActualHistoryExcludesCurrentSessionAndPreservesMissingValues() throws {
        let fixture = try GuidedWorkoutCoordinatorTests().makeFixture(firstSetIsWarmup: false, setCount: 2)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let exercise = ExerciseDefinition(canonicalName: "虚构划船")
        fixture.context.insert(exercise)
        let records = [
            WorkoutEntry(date: fixture.now.addingTimeInterval(-300), exercise: exercise.canonicalName,
                         exerciseID: exercise.id, setEntries: [.init(reps: 12, externalWeightKG: 30)]),
            WorkoutEntry(date: fixture.now.addingTimeInterval(-100), exercise: exercise.canonicalName,
                         exerciseID: exercise.id, setEntries: [.init(reps: 9)]),
            WorkoutEntry(date: fixture.now, exercise: exercise.canonicalName,
                         exerciseID: exercise.id, setEntries: [.init(reps: 5, externalWeightKG: 99)],
                         sourceSessionID: fixture.session.id)
        ]
        for record in records {
            fixture.context.insert(record)
        }
        try fixture.context.save()
        let preview = try GuidedExerciseReplacementResolver.preview(
            exercise: exercise, excluding: fixture.session.id, in: fixture.context
        )
        XCTAssertEqual(preview.sourceDate, records[1].date)
        XCTAssertEqual(preview.prescription.plannedSets[0].targetReps, 9)
        XCTAssertNil(preview.prescription.plannedSets[0].targetWeightKG)
        XCTAssertNil(preview.prescription.targetRestSeconds)
    }

    func testBilateralHistoryRetainsDifferentWeightsAndRequiresConfirmationOfUnequalReps() throws {
        let fixture = try GuidedWorkoutCoordinatorTests().makeFixture(firstSetIsWarmup: false, setCount: 2)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let exercise = ExerciseDefinition(canonicalName: "虚构左右提举")
        exercise.laterality = .both
        fixture.context.insert(exercise)
        let record = WorkoutEntry(
            exercise: exercise.canonicalName, exerciseID: exercise.id,
            setEntries: [
                .init(logicalSetIndex: 1, side: .left, reps: 8, externalWeightKG: 10, restSeconds: 15),
                .init(logicalSetIndex: 1, side: .right, reps: 6, externalWeightKG: 12, restSeconds: 45),
                .init(logicalSetIndex: 2, side: .left, reps: 7, externalWeightKG: 9)
            ]
        )
        fixture.context.insert(record)
        try fixture.context.save()
        let preview = try GuidedExerciseReplacementResolver.preview(
            exercise: exercise, excluding: fixture.session.id, in: fixture.context
        )
        let sets = preview.prescription.plannedSets
        XCTAssertEqual(sets.count, 2)
        XCTAssertNil(sets[0].targetReps)
        XCTAssertEqual(sets[0].leftWeightKG, 10)
        XCTAssertEqual(sets[0].rightWeightKG, 12)
        XCTAssertNil(sets[0].targetWeightKG)
        XCTAssertNil(sets[1].targetReps)
        XCTAssertNil(sets[1].weight(for: .right))
        XCTAssertEqual(sets[1].leftWeightKG, 9)
        XCTAssertEqual(record.setEntries.count, 3)
        XCTAssertEqual(record.setEntries[0].reps, 8)
    }

    func testConfirmedEditsDriveNewRuntimeAndKeepOtherCompletedPerformance() async throws {
        let fixture = try GuidedWorkoutCoordinatorTests().makeFixture(firstSetIsWarmup: false, setCount: 2)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let exercise = ExerciseDefinition(canonicalName: "虚构左右划船")
        exercise.laterality = .both
        fixture.context.insert(exercise)
        let original = try XCTUnwrap(fixture.performance.prescriptionSnapshot)
        let completed = ExercisePerformance(
            sessionID: fixture.session.id, exerciseID: original.exerciseID,
            exerciseName: "此前完成的虚构动作", order: 0, prescriptionSnapshot: original,
            status: .completed
        )
        fixture.context.insert(completed)
        let doneSet = WorkoutSet(performanceID: completed.id, order: 1,
                                 actualReps: 11, actualWeightKG: 25, status: .completed)
        doneSet.performance = completed
        fixture.context.insert(doneSet)
        try fixture.context.save()
        let coordinator = GuidedWorkoutCoordinator(recorder: NoopWorkoutRecordingController(), cues: Cues(), now: { fixture.now })
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        var confirmed = try GuidedExerciseReplacementResolver.preview(
            exercise: exercise, excluding: fixture.session.id, in: fixture.context
        ).prescription
        confirmed.plannedSets = [.init(order: 1, targetReps: 10, leftWeightKG: 8, rightWeightKG: 9)]
        confirmed.restBetweenSidesSeconds = 20
        let oldEffortIDs = Set(fixture.efforts.map(\.id))
        try coordinator.replaceCurrentExercise(with: exercise, prescription: confirmed, in: fixture.context)
        let setID = try XCTUnwrap(fixture.session.currentSetID)
        let newEfforts = try fixture.context.fetch(FetchDescriptor<WorkoutEffort>(
            predicate: #Predicate { $0.workoutSetID == setID }, sortBy: [SortDescriptor(\.order)]
        ))
        XCTAssertEqual(newEfforts.map(\.side), [.left, .right])
        XCTAssertEqual(newEfforts.map(\.plannedReps), [10, 10])
        XCTAssertEqual(newEfforts.map(\.plannedWeightKG), [8, 9])
        XCTAssertTrue(newEfforts.allSatisfy { !oldEffortIDs.contains($0.id) })
        XCTAssertEqual(doneSet.actualReps, 11)
        XCTAssertEqual(doneSet.actualWeightKG, 25)
        XCTAssertEqual(doneSet.status, .completed)
        XCTAssertEqual(fixture.session.prescriptionSnapshot[0].exerciseID, exercise.id)
        XCTAssertEqual(fixture.session.prescriptionSnapshot[0].restBetweenSidesSeconds, 20)
    }

    func testSameExerciseParameterEditRebuildsPendingSetsWithoutChangingIdentity() async throws {
        let fixture = try GuidedWorkoutCoordinatorTests().makeFixture(
            firstSetIsWarmup: false,
            setCount: 2
        )
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let exercise = try XCTUnwrap(fixture.performance.exerciseDefinition)
        let coordinator = GuidedWorkoutCoordinator(
            recorder: NoopWorkoutRecordingController(),
            cues: Cues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        var confirmed = try XCTUnwrap(fixture.performance.prescriptionSnapshot)
        confirmed.plannedSets = [
            .init(order: 1, targetReps: 6, targetWeightKG: 18),
            .init(order: 2, targetReps: 6, targetWeightKG: 18),
            .init(order: 3, targetReps: 4, targetWeightKG: 22)
        ]
        confirmed.targetRestSeconds = 75
        try coordinator.replaceCurrentExercise(
            with: exercise,
            prescription: confirmed,
            in: fixture.context
        )
        let performanceID = fixture.performance.id
        let sets = try fixture.context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.performanceID == performanceID },
            sortBy: [SortDescriptor(\.order)]
        ))
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets.map(\.plannedReps), [6, 6, 4])
        XCTAssertEqual(sets.map(\.plannedWeightKG), [18, 18, 22])
        XCTAssertEqual(sets.map(\.plannedRestSeconds), [75, 75, nil])
        XCTAssertEqual(fixture.performance.exerciseID, exercise.id)
        XCTAssertEqual(fixture.performance.exerciseName, exercise.canonicalName)
    }

    func testReplacementRejectsStartedEvidenceAndInvalidTargetsWithoutMutation() async throws {
        let fixture = try GuidedWorkoutCoordinatorTests().makeFixture(firstSetIsWarmup: false, setCount: 2)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let exercise = ExerciseDefinition(canonicalName: "虚构新动作")
        fixture.context.insert(exercise)
        try fixture.context.save()
        let coordinator = GuidedWorkoutCoordinator(recorder: NoopWorkoutRecordingController(), cues: Cues(), now: { fixture.now })
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        let originalID = fixture.performance.exerciseID
        var confirmed = try GuidedExerciseReplacementResolver.preview(
            exercise: exercise, excluding: fixture.session.id, in: fixture.context
        ).prescription
        XCTAssertThrowsError(try coordinator.replaceCurrentExercise(
            with: exercise, prescription: confirmed, in: fixture.context
        ))
        confirmed.plannedSets[0].targetReps = 8
        fixture.efforts[0].actualReps = 3
        try fixture.context.save()
        XCTAssertThrowsError(try coordinator.replaceCurrentExercise(
            with: exercise, prescription: confirmed, in: fixture.context
        ))
        XCTAssertEqual(fixture.performance.exerciseID, originalID)
        XCTAssertEqual(fixture.efforts[0].actualReps, 3)
    }

    private final class Cues: WorkoutCueProviding {
        func announce(_: String) {}
        func success() {}
    }
}
