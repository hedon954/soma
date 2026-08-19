@testable import Soma
import XCTest

final class WorkoutCalorieCalculatorTests: XCTestCase {
    func testIgnoresMistakenSetsRepsRestDuration() throws {
        // Agent mistake: 4 × 8 × 90 / 60 = 48
        XCTAssertTrue(WorkoutCalorieCalculator.isMistakenSetsRepsRestDuration(
            48,
            sets: 4,
            reps: 8,
            restSeconds: 90
        ))
        XCTAssertNil(WorkoutCalorieCalculator.sanitizedActualDurationMinutes(
            48,
            sets: 4,
            reps: 8,
            restSeconds: 90
        ))

        let estimate = try XCTUnwrap(WorkoutCalorieCalculator.estimate(
            exercise: "杠铃深蹲",
            intensity: "适中",
            durationMinutes: 48,
            sets: 4,
            reps: 8,
            restSeconds: 90,
            weightKG: 70
        ))
        XCTAssertEqual(estimate.durationMinutes, 398.0 / 60.0, accuracy: 0.001)
        XCTAssertTrue(estimate.durationWasEstimated)

        let entry = WorkoutEntry(
            date: .now,
            exercise: "杠铃深蹲",
            sets: 4,
            reps: 8,
            restSeconds: 90,
            durationMinutes: 48,
            notes: "",
            calorieDurationMinutes: 48,
            calorieDurationEstimated: false
        )
        XCTAssertTrue(WorkoutCalorieCalculator.sanitizeStoredDurationIfNeeded(
            entry,
            weightKG: 70
        ))
        XCTAssertNil(entry.durationMinutes)
        XCTAssertEqual(entry.calorieDurationMinutes ?? 0, 398.0 / 60.0, accuracy: 0.001)
        XCTAssertTrue(entry.calorieDurationEstimated)
    }

    func testGuidedDurationUsesActualSecondsAndActualRest() throws {
        let evidence = [
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: WorkoutEffortSide.none,
                targetKind: .duration,
                durationSeconds: 30,
                restSeconds: 20
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 2,
                side: WorkoutEffortSide.none,
                targetKind: .duration,
                durationSeconds: 40
            )
        ]

        let duration = try XCTUnwrap(
            WorkoutCalorieCalculator.guidedDuration(from: evidence)
        )
        XCTAssertEqual(duration.minutes, 1.5, accuracy: 0.001)
        XCTAssertFalse(duration.estimated)

        let estimate = try XCTUnwrap(
            WorkoutCalorieCalculator.estimateGuidedWorkout(
                exercise: "平板支撑",
                evidence: evidence,
                weightKG: 70
            )
        )
        XCTAssertEqual(estimate.durationMinutes, 1.5, accuracy: 0.001)
        XCTAssertFalse(estimate.durationWasEstimated)
    }

    func testGuidedRepetitionsUseFourSecondFallback() throws {
        let evidence = [
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: .left,
                targetKind: .repetitions,
                reps: 10,
                restSeconds: 15
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: .right,
                targetKind: .repetitions,
                reps: 10,
                restSeconds: 30
            )
        ]

        let duration = try XCTUnwrap(
            WorkoutCalorieCalculator.guidedDuration(from: evidence)
        )
        XCTAssertEqual(duration.minutes, 125.0 / 60.0, accuracy: 0.001)
        XCTAssertTrue(duration.estimated)
    }

    func testGuidedRepetitionsPreferActualElapsedDuration() throws {
        let evidence = [
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: .left,
                targetKind: .repetitions,
                reps: 10,
                durationSeconds: 22,
                restSeconds: 15
            ),
            WorkoutSetEvidence(
                logicalSetIndex: 1,
                side: .right,
                targetKind: .repetitions,
                reps: 10,
                durationSeconds: 28,
                restSeconds: 30
            )
        ]

        let duration = try XCTUnwrap(
            WorkoutCalorieCalculator.guidedDuration(from: evidence)
        )
        XCTAssertEqual(duration.minutes, 95.0 / 60.0, accuracy: 0.001)
        XCTAssertFalse(duration.estimated)
    }

    func testGuidedCaloriesStayUnknownWhenCompletedEvidenceHasNoTargetFact() {
        XCTAssertNil(WorkoutCalorieCalculator.estimateGuidedWorkout(
            exercise: "深蹲",
            evidence: [WorkoutSetEvidence(
                logicalSetIndex: 1,
                targetKind: .repetitions
            )],
            weightKG: 70
        ))
        XCTAssertNil(WorkoutCalorieCalculator.estimateGuidedWorkout(
            exercise: "深蹲",
            evidence: [WorkoutSetEvidence(
                logicalSetIndex: 1,
                targetKind: .repetitions,
                reps: 10
            )],
            weightKG: nil
        ))
    }
}
