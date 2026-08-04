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
}
