@testable import Soma
import SwiftData
import XCTest

final class TrainingVolumeAnalyticsTests: XCTestCase {
    func testWorkoutVolume() {
        let workout = WorkoutEntry(exercise: "深蹲", sets: 4, reps: 8, weight: 60, restSeconds: 90)
        XCTAssertEqual(workout.estimatedVolume, 1920)
    }

    func testWorkoutVolumeUsesOrderedPerSetEvidence() {
        let workout = WorkoutEntry(
            exercise: "深蹲",
            setEntries: [
                WorkoutSetEvidence(reps: 10, externalWeightKG: 10),
                WorkoutSetEvidence(reps: 10, externalWeightKG: 20),
                WorkoutSetEvidence(reps: 12, externalWeightKG: 14)
            ]
        )

        XCTAssertEqual(workout.setCount, 3)
        XCTAssertEqual(workout.estimatedVolume, 468)
        XCTAssertNil(workout.representativeReps)
        XCTAssertNil(workout.representativeWeight)
    }

    func testWorkoutCalorieUsesExplicitDurationAndMET() throws {
        let estimate = try XCTUnwrap(WorkoutCalorieCalculator.estimate(
            exercise: "杠铃深蹲",
            intensity: "适中",
            durationMinutes: 30,
            weightKG: 70
        ))

        XCTAssertEqual(estimate.met, 5.0)
        XCTAssertEqual(estimate.durationMinutes, 30)
        XCTAssertFalse(estimate.durationWasEstimated)
        XCTAssertEqual(estimate.calories, 175)
    }

    func testWorkoutCalorieCanEstimateResistanceDurationWithoutFillingActualDuration() throws {
        let duration = try XCTUnwrap(WorkoutCalorieCalculator.estimatedResistanceDuration(
            sets: 4,
            reps: 8,
            restSeconds: 90
        ))
        let estimate = try XCTUnwrap(WorkoutCalorieCalculator.estimate(
            exercise: "杠铃深蹲",
            intensity: "适中",
            durationMinutes: nil,
            sets: 4,
            reps: 8,
            restSeconds: 90,
            weightKG: 70
        ))

        XCTAssertEqual(duration, 398.0 / 60.0, accuracy: 0.001)
        XCTAssertEqual(estimate.durationMinutes, duration, accuracy: 0.001)
        XCTAssertTrue(estimate.durationWasEstimated)
        XCTAssertEqual(estimate.calories, 39)
    }

    func testWorkoutCalorieDoesNotGuessMissingWeightOrRest() {
        XCTAssertNil(WorkoutCalorieCalculator.estimate(
            exercise: "卧推",
            intensity: nil,
            durationMinutes: 30,
            weightKG: nil
        ))
        XCTAssertNil(WorkoutCalorieCalculator.estimate(
            exercise: "卧推",
            intensity: nil,
            durationMinutes: nil,
            sets: 4,
            reps: 8,
            restSeconds: nil,
            weightKG: 70
        ))
    }

    func testTrainingVolumeAggregatesByDayAndSkipsIncompleteRecords() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let firstDay = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 26, hour: 9))
        )
        let sameDay = try XCTUnwrap(calendar.date(byAdding: .hour, value: 3, to: firstDay))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let workouts = [
            WorkoutEntry(date: firstDay, exercise: "深蹲", sets: 4, reps: 8, weight: 60),
            WorkoutEntry(date: sameDay, exercise: "卧推", sets: 3, reps: 10, weight: 40),
            WorkoutEntry(date: nextDay, exercise: "俯卧撑", sets: 4, reps: 12),
            WorkoutEntry(date: nextDay, exercise: "空杆", sets: 3, reps: 10, weight: 0)
        ]

        let points = TrainingVolumeAnalytics.dailyPoints(from: workouts, calendar: calendar)

        XCTAssertEqual(points.count, 1)
        let dayStart = calendar.startOfDay(for: firstDay)
        XCTAssertEqual(points.first?.date, dayStart)
        XCTAssertEqual(points.first?.volume, 3120)
        let followingDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: dayStart))
        XCTAssertEqual(
            TrainingVolumeAnalytics.total(in: dayStart ..< followingDay, points: points),
            3120
        )

        workouts[0].weight = 65
        let refreshedPoints = TrainingVolumeAnalytics.dailyPoints(from: workouts, calendar: calendar)
        XCTAssertEqual(refreshedPoints.first?.volume, 3280)
    }
}
