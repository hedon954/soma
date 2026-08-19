@testable import Soma
import XCTest

final class TemplateVersionDiffTests: XCTestCase {
    func testInitialVersionSummary() {
        let log = TemplateVersionDiff.changeLog(
            from: nil,
            to: [
                TemplateExercisePrescription(
                    exerciseID: UUID(),
                    exerciseName: "杠铃深蹲",
                    order: 1,
                    targetSets: 5,
                    targetReps: 5
                )
            ]
        )
        XCTAssertEqual(log.summary, "初始版本")
    }

    func testDetectsRemovedAndModifiedPrescriptions() {
        let squatID = UUID()
        let pullupID = UUID()
        let previous = [
            TemplateExercisePrescription(
                exerciseID: pullupID,
                exerciseName: "引体向上",
                order: 1,
                targetSets: 5,
                targetReps: 5
            ),
            TemplateExercisePrescription(
                exerciseID: squatID,
                exerciseName: "杠铃深蹲",
                order: 2,
                targetSets: 4,
                targetReps: 5,
                targetWeightKG: 50,
                targetRestSeconds: 60
            )
        ]
        let current = [
            TemplateExercisePrescription(
                exerciseID: squatID,
                exerciseName: "杠铃深蹲",
                order: 1,
                targetSets: 5,
                targetReps: 5,
                targetWeightKG: 50,
                targetRestSeconds: 60
            )
        ]

        let log = TemplateVersionDiff.changeLog(from: previous, to: current)
        XCTAssertTrue(log.summary.contains("移除 引体向上"))
        XCTAssertTrue(log.summary.contains("杠铃深蹲"))
        XCTAssertTrue(log.details.contains("组数 4→5") || log.summary.contains("组数"))
        XCTAssertTrue(log.details.contains("移除 引体向上"))
    }

    func testDetectsLateralityAndSecondSetOnlyChange() {
        let exerciseID = UUID()
        let old = TemplateExercisePrescription(
            exerciseID: exerciseID,
            exerciseName: "单臂划船",
            order: 1,
            laterality: .left,
            plannedSets: [
                TemplateSetPrescriptionValue(
                    order: 1,
                    targetReps: 10,
                    leftWeightKG: 12
                ),
                TemplateSetPrescriptionValue(
                    order: 2,
                    targetReps: 10,
                    leftWeightKG: 12
                )
            ]
        )
        let new = TemplateExercisePrescription(
            exerciseID: exerciseID,
            exerciseName: "单臂划船",
            order: 1,
            laterality: .both,
            plannedSets: [
                TemplateSetPrescriptionValue(
                    order: 1,
                    targetReps: 10,
                    leftWeightKG: 12,
                    rightWeightKG: 12
                ),
                TemplateSetPrescriptionValue(
                    order: 2,
                    targetKind: .duration,
                    targetDurationSeconds: 30,
                    leftWeightKG: 14,
                    rightWeightKG: 13
                )
            ]
        )

        let log = TemplateVersionDiff.changeLog(from: [old], to: [new])
        XCTAssertTrue(log.details.contains("侧别 只左边→左右分开"))
        XCTAssertTrue(log.details.contains("逐组处方已调整"))
    }

    func testEquivalentLegacyExpansionDoesNotReportSetChangeFromRandomIDs() {
        let exerciseID = UUID()
        let previous = TemplateExercisePrescription(
            exerciseID: exerciseID,
            exerciseName: "深蹲",
            order: 1,
            targetSets: 3,
            targetReps: 8
        )
        let current = TemplateExercisePrescription(
            exerciseID: exerciseID,
            exerciseName: "深蹲",
            order: 1,
            targetSets: 3,
            targetReps: 8
        )

        let log = TemplateVersionDiff.changeLog(
            from: [previous],
            to: [current]
        )
        XCTAssertFalse(log.details.contains("逐组处方已调整"))
    }
}
