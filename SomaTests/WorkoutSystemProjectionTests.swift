@testable import Soma
import XCTest

final class WorkoutSystemProjectionTests: XCTestCase {
    func testLegacyContentStateDecodesMissingProgressFields() throws {
        let payload = Data("""
        {
          "phaseRaw": "active",
          "completedSetCount": 0,
          "totalSetCount": 27
        }
        """.utf8)

        let state = try JSONDecoder().decode(
            SomaWorkoutActivityAttributes.ContentState.self,
            from: payload
        )
        XCTAssertEqual(state.phaseRaw, "active")
        XCTAssertEqual(state.completedSetCount, 0)
        XCTAssertEqual(state.totalSetCount, 27)
        XCTAssertEqual(state.progressFraction, 0)
        XCTAssertEqual(state.updateSequence, 0)
        XCTAssertNil(state.restEndAt)
    }

    @MainActor
    func testContentStateKeepsRestOnlyWhileActivelyResting() {
        let deadline = Date().addingTimeInterval(90)
        let resting = WorkoutSystemProjectionCoordinator.contentState(
            status: .active,
            guidedPhase: .resting,
            restTargetEndAt: deadline,
            completedSetCount: 3,
            totalSetCount: 27,
            progressFraction: 0.25,
            updateSequence: 4
        )
        XCTAssertEqual(resting.phaseRaw, "resting")
        XCTAssertEqual(resting.restEndAt, deadline)
        XCTAssertEqual(resting.progressFraction, 0.25)
        XCTAssertEqual(resting.updateSequence, 4)
    }

    func testPartialEffortAdvancesFractionWithoutCompletingTheSet() {
        let performanceID = UUID()
        let setID = UUID()
        let snapshot = GuidedWorkoutScreenSnapshot(
            session: GuidedWorkoutSessionSnapshot(
                id: UUID(),
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                endedAt: nil,
                statusRaw: WorkoutSessionStatus.active.rawValue,
                guidedPhaseRaw: GuidedWorkoutPhase.setInProgress.rawValue,
                currentPerformanceID: performanceID,
                currentSetID: setID,
                currentEffortID: nil,
                phaseStartedAt: nil,
                phaseDeadlineAt: nil,
                transitionRevision: 1,
                restTargetEndAt: nil,
                autoRecordingPolicyRaw: AutoRecordingPolicy.disabled.rawValue,
                queuedRecordingEffortID: nil,
                automaticRecordingPaused: false
            ),
            performances: [
                GuidedWorkoutPerformanceSnapshot(
                    id: performanceID,
                    exerciseID: UUID(),
                    exerciseName: "虚构推举",
                    order: 1,
                    statusRaw: ExercisePerformanceStatus.active.rawValue,
                    prescription: nil,
                    artwork: BundledExerciseCatalog.fallbackActionIllustration,
                    coachingNotes: ""
                )
            ],
            sets: [
                GuidedWorkoutSetSnapshot(
                    id: setID,
                    performanceID: performanceID,
                    order: 1,
                    kindRaw: WorkoutSetKind.working.rawValue,
                    statusRaw: WorkoutSetStatus.inProgress.rawValue,
                    plannedTargetKindRaw: WorkoutTargetKind.repetitions.rawValue,
                    plannedReps: 8,
                    plannedDurationSeconds: nil,
                    plannedWeightKG: 20,
                    plannedRestSeconds: 60,
                    restBetweenSidesSeconds: 15,
                    actualReps: nil,
                    actualDurationSeconds: nil,
                    actualWeightKG: nil,
                    actualRestSeconds: nil
                )
            ],
            efforts: [
                GuidedWorkoutEffortSnapshot(
                    id: UUID(),
                    workoutSetID: setID,
                    order: 1,
                    sideRaw: WorkoutEffortSide.left.rawValue,
                    targetKindRaw: WorkoutTargetKind.repetitions.rawValue,
                    plannedReps: 8,
                    plannedDurationSeconds: nil,
                    plannedWeightKG: 20,
                    actualReps: 8,
                    actualDurationSeconds: nil,
                    actualWeightKG: 20,
                    actualRestSeconds: nil,
                    statusRaw: WorkoutEffortStatus.completed.rawValue,
                    recordedVideoPath: nil
                ),
                GuidedWorkoutEffortSnapshot(
                    id: UUID(),
                    workoutSetID: setID,
                    order: 2,
                    sideRaw: WorkoutEffortSide.right.rawValue,
                    targetKindRaw: WorkoutTargetKind.repetitions.rawValue,
                    plannedReps: 8,
                    plannedDurationSeconds: nil,
                    plannedWeightKG: 20,
                    actualReps: nil,
                    actualDurationSeconds: nil,
                    actualWeightKG: nil,
                    actualRestSeconds: nil,
                    statusRaw: WorkoutEffortStatus.inProgress.rawValue,
                    recordedVideoPath: nil
                )
            ]
        )

        XCTAssertEqual(snapshot.completedSetCount, 0)
        XCTAssertEqual(
            WorkoutLiveActivityProgress.fraction(from: snapshot),
            0.5,
            accuracy: 0.001
        )
    }
}
