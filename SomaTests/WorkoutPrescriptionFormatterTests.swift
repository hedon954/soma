@testable import Soma
import XCTest

final class WorkoutPrescriptionFormatterTests: XCTestCase {
    func testUniformRepetitionPrescriptionUsesEverySetSummary() {
        let prescription = TemplateExercisePrescription(
            exerciseID: UUID(),
            exerciseName: "深蹲",
            order: 1,
            laterality: .none,
            plannedSets: (1 ... 3).map {
                TemplateSetPrescriptionValue(
                    order: $0,
                    targetKind: .repetitions,
                    targetReps: 10
                )
            }
        )

        XCTAssertEqual(
            WorkoutPrescriptionFormatter.exerciseAnnouncement(
                name: "深蹲",
                prescription: prescription
            ),
            "接下来，深蹲，共 3 组，每组 10 次"
        )
    }

    func testHeterogeneousDurationPrescriptionEnumeratesEachSet() {
        let prescription = TemplateExercisePrescription(
            exerciseID: UUID(),
            exerciseName: "平板支撑",
            order: 1,
            laterality: .none,
            plannedSets: [20, 30, 40].enumerated().map { index, seconds in
                TemplateSetPrescriptionValue(
                    order: index + 1,
                    targetKind: .duration,
                    targetDurationSeconds: seconds
                )
            }
        )

        XCTAssertEqual(
            WorkoutPrescriptionFormatter.exerciseAnnouncement(
                name: "平板支撑",
                prescription: prescription
            ),
            "接下来，平板支撑，共 3 组：20 秒、30 秒、40 秒"
        )
    }

    func testWarmupAndWorkingClustersStayCompactInAnnouncementAndSummary() {
        let prescription = TemplateExercisePrescription(
            exerciseID: UUID(),
            exerciseName: "深蹲",
            order: 1,
            targetRestSeconds: 90,
            laterality: .none,
            plannedSets: [
                TemplateSetPrescriptionValue(
                    order: 1,
                    kind: .warmup,
                    targetKind: .repetitions,
                    targetReps: 8,
                    targetWeightKG: 60
                )
            ] + (2 ... 5).map {
                TemplateSetPrescriptionValue(
                    order: $0,
                    targetKind: .repetitions,
                    targetReps: 8,
                    targetWeightKG: 80
                )
            }
        )

        XCTAssertEqual(
            WorkoutPrescriptionFormatter.exerciseAnnouncement(
                name: "深蹲",
                prescription: prescription
            ),
            "接下来，深蹲，热身 1 组 8 次，工作 4 组每组 8 次"
        )
        XCTAssertEqual(
            WorkoutPrescriptionFormatter.exerciseSummary(prescription),
            "热身 1×8次 60kg · 工作 4×8次 80kg · 组间歇90秒"
        )
    }

    func testUniformWorkingSummaryOmitsKindAndNoneLaterality() {
        let prescription = TemplateExercisePrescription(
            exerciseID: UUID(),
            exerciseName: "卧推",
            order: 1,
            laterality: .none,
            plannedSets: (1 ... 3).map {
                TemplateSetPrescriptionValue(
                    order: $0,
                    targetKind: .repetitions,
                    targetReps: 10,
                    targetWeightKG: 60
                )
            }
        )

        XCTAssertEqual(
            WorkoutPrescriptionFormatter.exerciseSummary(prescription),
            "3×10次 60kg"
        )
    }

    func testBothLateralityAnnouncesExecutionOrder() {
        let prescription = TemplateExercisePrescription(
            exerciseID: UUID(),
            exerciseName: "单臂划船",
            order: 1,
            laterality: .both,
            plannedSets: [
                TemplateSetPrescriptionValue(
                    order: 1,
                    targetKind: .repetitions,
                    targetReps: 8
                )
            ]
        )

        XCTAssertEqual(
            WorkoutPrescriptionFormatter.exerciseAnnouncement(
                name: "单臂划船",
                prescription: prescription
            ),
            "接下来，单臂划船，共 1 组，每组 8 次，左右各做，左侧先开始"
        )
    }

    func testEffortTargetUsesSideDurationAndWeight() {
        let set = WorkoutSet(
            performanceID: UUID(),
            order: 2,
            plannedTargetKind: .duration,
            plannedDurationSeconds: 30
        )
        let effort = WorkoutEffort(
            workoutSetID: set.id,
            order: 2,
            side: .right,
            targetKind: .duration,
            plannedDurationSeconds: 30,
            plannedWeightKG: 12.5
        )

        XCTAssertEqual(
            WorkoutPrescriptionFormatter.setTarget(set: set, effort: effort),
            "右侧 · 12.5 kg · 30 秒"
        )
    }
}
