@testable import Soma
import XCTest

final class WorkoutRestPropagationTests: XCTestCase {
    func testFillsNonFinalGroupsFromWorkoutRest() {
        let entries = WorkoutRestPropagation.propagate(
            [
                WorkoutSetEvidence(logicalSetIndex: 1, reps: 12, externalWeightKG: 25, restSeconds: 0),
                WorkoutSetEvidence(logicalSetIndex: 2, reps: 12, externalWeightKG: 20)
            ],
            workoutRestSeconds: 120
        )
        XCTAssertEqual(entries.map(\.restSeconds), [120, nil])
    }

    func testMovesRestOffTheFinalGroup() {
        let entries = WorkoutRestPropagation.propagate(
            [
                WorkoutSetEvidence(logicalSetIndex: 1, reps: 12, externalWeightKG: 25),
                WorkoutSetEvidence(logicalSetIndex: 2, reps: 12, externalWeightKG: 20, restSeconds: 120)
            ],
            workoutRestSeconds: nil
        )
        XCTAssertEqual(entries.map(\.restSeconds), [120, nil])
    }

    func testKeepsExplicitPositiveSetRest() {
        let entries = WorkoutRestPropagation.propagate(
            [
                WorkoutSetEvidence(logicalSetIndex: 1, reps: 8, restSeconds: 90),
                WorkoutSetEvidence(logicalSetIndex: 2, reps: 8, restSeconds: 60),
                WorkoutSetEvidence(logicalSetIndex: 3, reps: 8)
            ],
            workoutRestSeconds: 120
        )
        XCTAssertEqual(entries.map(\.restSeconds), [90, 60, nil])
    }

    func testLeavesASingleGroupUnchanged() {
        let entries = [
            WorkoutSetEvidence(logicalSetIndex: 1, reps: 12, restSeconds: 0)
        ]
        XCTAssertEqual(
            WorkoutRestPropagation.propagate(entries, workoutRestSeconds: 120),
            entries
        )
    }
}
