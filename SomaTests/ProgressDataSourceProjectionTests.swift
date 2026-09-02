@testable import Soma
import XCTest

final class ProgressDataSourceProjectionTests: XCTestCase {
    func testIntakeSourceListsEveryRecordWithoutRepeatingTheOuterTotal() {
        let rows = ProgressMetricSource.intake(
            [
                ProgressMetricBreakdownItem(label: "早餐 · 燕麦", value: "320 kcal"),
                ProgressMetricBreakdownItem(label: "午餐 · 米饭", value: "未记录")
            ]
        ).rows

        XCTAssertEqual(rows.map(\.label), ["早餐 · 燕麦", "午餐 · 米饭"])
        XCTAssertEqual(rows.map(\.value), ["320 kcal", "未记录"])
    }

    func testDailyTotalSourceShowsPartsWithoutRepeatingTheOuterTotal() {
        let projection = DailyEnergyProjectionResult(
            dailyTotalKilocalories: 2200,
            projectedRestingKilocalories: 1700,
            projectedActiveKilocalories: 500,
            elapsedDayFraction: 0.5,
            originalFormula: "原始公式",
            substitutedFormula: "代入公式"
        )

        XCTAssertEqual(
            ProgressMetricSource.dailyTotal(projection).rows,
            [
                ProgressSourceRow(label: "全天静息预估", value: "1700 kcal"),
                ProgressSourceRow(label: "全天活动预估", value: "500 kcal")
            ]
        )
    }

    func testCurrentTotalDistinguishesHealthActivityFromWorkoutEstimate() {
        XCTAssertEqual(
            ProgressMetricSource.currentTotal(
                resting: 1200,
                active: 480,
                activeUsesHealth: true
            ).rows,
            [
                ProgressSourceRow(label: "截至当前静息消耗", value: "1200 kcal"),
                ProgressSourceRow(label: "截至当前活动消耗", value: "480 kcal")
            ]
        )
        XCTAssertEqual(
            ProgressMetricSource.currentTotal(
                resting: 1200,
                active: 180,
                activeUsesHealth: false
            ).rows.last,
            ProgressSourceRow(label: "已记录训练消耗", value: "180 kcal")
        )
    }

    func testRestingSourceBreaksFormulaIntoRealUserTerms() {
        let input = RestingEnergyFormulaInput(
            weightKG: 70,
            heightCM: 175,
            age: 30,
            biologicalSex: .male,
            dailyKilocalories: 1648.75
        )

        let rows = ProgressMetricSource.resting(
            usesHealth: false,
            components: [],
            formula: input
        ).rows

        XCTAssertEqual(rows[0].value, "700 kcal")
        XCTAssertEqual(rows[1].value, "1094 kcal")
        XCTAssertEqual(rows[2].value, "−150 kcal")
        XCTAssertEqual(rows[3].value, "+5 kcal")
        XCTAssertEqual(rows[4].value, "1649 kcal")
        XCTAssertEqual(rows.count, 5)
    }
}
