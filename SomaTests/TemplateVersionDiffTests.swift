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
}
