@testable import Soma
import XCTest

final class TrainingPlanOverviewTests: XCTestCase {
    func testIndependentSetCountDrivesOverviewScale() {
        let summary = TrainingPlanOverview.summarize([
            .init(
                primaryMuscles: ["quadriceps"],
                secondaryMuscles: [],
                targetSets: 3
            ),
            .init(
                primaryMuscles: ["glutes"],
                secondaryMuscles: [],
                targetSets: 5
            )
        ])

        XCTAssertEqual(summary.exerciseCount, 2)
        XCTAssertEqual(summary.totalSets, 8)
        XCTAssertTrue(summary.overviewText.contains("共 8 组"))
    }

    func testPrimaryAndSecondaryRolesAreNotReclassifiedByAccumulatedIntensity() {
        let summary = TrainingPlanOverview.summarize([
            .init(
                primaryMuscles: ["胸大肌"],
                secondaryMuscles: ["肱三头肌"],
                targetSets: 2
            ),
            .init(
                primaryMuscles: ["股四头肌"],
                secondaryMuscles: ["肱三头肌"],
                targetSets: 2
            ),
            .init(
                primaryMuscles: ["臀大肌"],
                secondaryMuscles: ["肱三头肌"],
                targetSets: 2
            )
        ])

        XCTAssertEqual(
            Set(summary.primaryFocus),
            [.chest, .quadriceps, .gluteal]
        )
        XCTAssertEqual(summary.secondaryFocus, [.triceps])
        XCTAssertFalse(summary.primaryFocus.contains(.triceps))
        XCTAssertTrue(summary.intensities.keys.contains(.triceps))
    }

    func testMuscleUsedAsPrimaryIsNotRepeatedAsSecondaryFocus() {
        let summary = TrainingPlanOverview.summarize([
            .init(
                primaryMuscles: ["上背"],
                secondaryMuscles: ["肱二头肌"],
                targetSets: 3
            ),
            .init(
                primaryMuscles: ["肱二头肌"],
                secondaryMuscles: ["前臂"],
                targetSets: 1
            )
        ])

        XCTAssertTrue(summary.primaryFocus.contains(.biceps))
        XCTAssertFalse(summary.secondaryFocus.contains(.biceps))
        XCTAssertTrue(summary.secondaryFocus.contains(.forearm))
    }
}
