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
}
