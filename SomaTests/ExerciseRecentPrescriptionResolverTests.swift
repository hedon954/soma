@testable import Soma
import XCTest

final class ExerciseRecentPrescriptionResolverTests: XCTestCase {
    func testLatestUsesNewestCompletedExerciseRecord() {
        let exerciseID = UUID()
        let older = WorkoutEntry(
            date: Date(timeIntervalSince1970: 100),
            exercise: "测试动作",
            exerciseID: exerciseID,
            setEntries: [
                .init(reps: 8, externalWeightKG: 20),
                .init(reps: 8, externalWeightKG: 20)
            ],
            restSeconds: 60
        )
        let newer = WorkoutEntry(
            date: Date(timeIntervalSince1970: 200),
            exercise: "测试动作",
            exerciseID: exerciseID,
            setEntries: [
                .init(reps: 5, externalWeightKG: 30),
                .init(reps: 5, externalWeightKG: 30),
                .init(reps: 5, externalWeightKG: 30)
            ],
            restSeconds: 120
        )

        let value = ExerciseRecentPrescriptionResolver.latest(
            exerciseID: exerciseID,
            workouts: [older, newer],
            sessions: [],
            performances: [],
            sets: []
        )

        XCTAssertEqual(value?.setCount, 3)
        XCTAssertEqual(value?.reps, 5)
        XCTAssertEqual(value?.weightKG, 30)
        XCTAssertEqual(value?.restSeconds, 120)
        XCTAssertNil(value?.firstSetIsWarmup)
    }

    func testGuidedHistoryUsesUniformWorkingSetsAndWarmupFlag() {
        let exerciseID = UUID()
        let session = WorkoutSession(
            startedAt: Date(timeIntervalSince1970: 300),
            status: .completed
        )
        let prescription = TemplateExercisePrescription(
            exerciseID: exerciseID,
            exerciseName: "测试动作",
            order: 1,
            targetSets: 3,
            firstSetIsWarmup: true
        )
        let performance = ExercisePerformance(
            sessionID: session.id,
            exerciseID: exerciseID,
            exerciseName: "测试动作",
            order: 1,
            prescriptionSnapshot: prescription,
            status: .completed
        )
        let sets = [
            WorkoutSet(
                performanceID: performance.id,
                order: 1,
                kind: .warmup,
                actualReps: 8,
                actualWeightKG: 10,
                actualRestSeconds: 90,
                status: .completed
            ),
            WorkoutSet(
                performanceID: performance.id,
                order: 2,
                actualReps: 5,
                actualWeightKG: 30,
                actualRestSeconds: 90,
                status: .completed
            ),
            WorkoutSet(
                performanceID: performance.id,
                order: 3,
                actualReps: 5,
                actualWeightKG: 30,
                actualRestSeconds: 90,
                status: .completed
            )
        ]
        let projected = WorkoutEntry(
            date: session.startedAt,
            exercise: "测试动作",
            exerciseID: exerciseID,
            setEntries: [
                .init(reps: 8, externalWeightKG: 10),
                .init(reps: 5, externalWeightKG: 30),
                .init(reps: 5, externalWeightKG: 30)
            ],
            restSeconds: 90,
            sourceWorkoutSessionID: session.id,
            sourcePerformanceID: performance.id
        )

        let value = ExerciseRecentPrescriptionResolver.latest(
            exerciseID: exerciseID,
            workouts: [projected],
            sessions: [session],
            performances: [performance],
            sets: sets
        )

        XCTAssertEqual(value?.setCount, 3)
        XCTAssertEqual(value?.reps, 5)
        XCTAssertEqual(value?.weightKG, 30)
        XCTAssertEqual(value?.restSeconds, 90)
        XCTAssertEqual(value?.firstSetIsWarmup, true)
    }

    func testNonUniformFieldsRemainMissing() {
        let exerciseID = UUID()
        let session = WorkoutSession(
            startedAt: Date(timeIntervalSince1970: 300),
            status: .completed
        )
        let prescription = TemplateExercisePrescription(
            exerciseID: exerciseID,
            exerciseName: "测试动作",
            order: 1,
            targetSets: 2
        )
        let performance = ExercisePerformance(
            sessionID: session.id,
            exerciseID: exerciseID,
            exerciseName: "测试动作",
            order: 1,
            prescriptionSnapshot: prescription,
            status: .completed
        )
        let sets = [
            WorkoutSet(
                performanceID: performance.id,
                order: 1,
                actualReps: 5,
                actualWeightKG: 30,
                actualRestSeconds: 60,
                status: .completed
            ),
            WorkoutSet(
                performanceID: performance.id,
                order: 2,
                actualReps: 4,
                actualWeightKG: 35,
                actualRestSeconds: 90,
                status: .completed
            )
        ]

        let value = ExerciseRecentPrescriptionResolver.latest(
            exerciseID: exerciseID,
            workouts: [],
            sessions: [session],
            performances: [performance],
            sets: sets
        )

        XCTAssertEqual(value?.setCount, 2)
        XCTAssertNil(value?.reps)
        XCTAssertNil(value?.weightKG)
        XCTAssertNil(value?.restSeconds)
    }
}
