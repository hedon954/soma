@testable import Soma
import XCTest

final class TrainingPlanOverviewTests: XCTestCase {
    func testSummarizeAggregatesMusclesWeightedBySets() {
        let summary = TrainingPlanOverview.summarize([
            .init(
                primaryMuscles: ["股四头肌", "臀大肌"],
                secondaryMuscles: ["腘绳肌"],
                targetSets: 5
            ),
            .init(
                primaryMuscles: ["胸大肌"],
                secondaryMuscles: ["肱三头肌"],
                targetSets: 3
            )
        ])

        XCTAssertEqual(summary.exerciseCount, 2)
        XCTAssertEqual(summary.totalSets, 8)
        XCTAssertEqual(summary.intensities[.quadriceps], 1.0)
        XCTAssertEqual(summary.intensities[.gluteal], 1.0)
        XCTAssertEqual(summary.intensities[.chest], 0.6)
        XCTAssertTrue(summary.primaryFocus.contains(.quadriceps))
        XCTAssertTrue(summary.overviewText.contains("2 个动作"))
        XCTAssertTrue(summary.overviewText.contains("共 8 组"))
    }

    func testSummarizeWithoutMappedMusclesExplainsMissingData() {
        let summary = TrainingPlanOverview.summarize([
            .init(primaryMuscles: [], secondaryMuscles: [], targetSets: nil)
        ])

        XCTAssertTrue(summary.intensities.isEmpty)
        XCTAssertTrue(summary.overviewText.contains("肌群标注"))
    }

    func testSummarizeIsDeterministicForSameInput() {
        let inputs: [TrainingPlanOverview.ExerciseInput] = [
            .init(
                primaryMuscles: ["背阔肌"],
                secondaryMuscles: ["肱二头肌", "前臂"],
                targetSets: 4
            ),
            .init(
                primaryMuscles: ["臀大肌", "腘绳肌"],
                secondaryMuscles: ["竖脊肌"],
                targetSets: 4
            )
        ]

        let first = TrainingPlanOverview.summarize(inputs)
        let second = TrainingPlanOverview.summarize(inputs)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.overviewText, second.overviewText)
    }
}
