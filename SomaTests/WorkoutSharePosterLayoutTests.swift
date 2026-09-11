@testable import Soma
import XCTest

final class WorkoutSharePosterLayoutTests: XCTestCase {
    func testMetricsTightenUntilSevenExercisesThenStayCompact() {
        let one = WorkoutSharePosterLayout.metrics(exerciseCount: 1)
        let four = WorkoutSharePosterLayout.metrics(exerciseCount: 4)
        let six = WorkoutSharePosterLayout.metrics(exerciseCount: 6)
        let seven = WorkoutSharePosterLayout.metrics(exerciseCount: 7)
        let many = WorkoutSharePosterLayout.metrics(exerciseCount: 16)

        XCTAssertGreaterThan(one.rowVerticalPadding, four.rowVerticalPadding)
        XCTAssertGreaterThan(four.rowVerticalPadding, six.rowVerticalPadding)
        XCTAssertGreaterThan(six.rowVerticalPadding, seven.rowVerticalPadding)
        XCTAssertGreaterThan(one.muscleMapHeight, seven.muscleMapHeight)
        XCTAssertGreaterThan(one.sectionSpacing, seven.sectionSpacing)
        XCTAssertEqual(seven, many)
        XCTAssertEqual(seven.minBodyHeight, WorkoutShareCanvas.height - seven.outerTop - seven.outerBottom)
    }
}
