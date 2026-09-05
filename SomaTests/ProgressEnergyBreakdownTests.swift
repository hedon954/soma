@testable import Soma
import XCTest

final class ProgressEnergyBreakdownTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testDailyIntakeListsOnlyMealsAndPreservesMissingEvidence() {
        let snapshot = make(.day, records: [
            record(5, .meal, "早餐", 400), record(5, .meal, "晚餐", nil),
            record(5, .workout, "虚构训练", 300)
        ])
        let rows = ProgressEnergyBreakdown(snapshot: snapshot, kind: .intake).rows
        XCTAssertEqual(rows.map(\.label), ["早餐", "晚餐", "已记录摄入"])
        XCTAssertEqual(rows[0].value, "400 kcal")
        XCTAssertEqual(rows[1].value, "0 kcal")
        XCTAssertEqual(snapshot.days.first?.intake.missingCount, 1)
        XCTAssertEqual(rows.last?.value, "400 kcal")
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }

    func testPeriodIntakeUsesSameCompletedRecordedDaysAsDashboard() {
        let snapshot = make(.month, records: [
            record(1, .meal, "A", 1000), record(2, .meal, "B", 2000),
            record(3, .meal, "缺项", nil), record(5, .meal, "今天", 500),
            record(6, .meal, "未来", 9000)
        ])
        let rows = ProgressEnergyBreakdown(snapshot: snapshot, kind: .intake).rows
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.last?.label, "日均摄入")
        XCTAssertEqual(rows.last?.value, "1,500 kcal")
        XCTAssertEqual(snapshot.averageIntake, 1500)
    }

    func testExpenditureComponentsAddUpWithoutAddingTrainingAgain() throws {
        let snapshot = make(.day, records: [record(5, .workout, "训练", 800)], hasProfile: true)
        let estimate = try XCTUnwrap(snapshot.days.first?.energy.estimate)
        let breakdown = ProgressEnergyBreakdown(snapshot: snapshot, kind: .expenditure)
        XCTAssertEqual(breakdown.rows.map(\.label), ["静息消耗", "活动等消耗", "活动系数", "预估总消耗"])
        XCTAssertEqual(breakdown.rows[0].value, "1,618 kcal")
        XCTAssertEqual(breakdown.rows[1].value, "647 kcal")
        XCTAssertEqual(breakdown.rows[2].value, "1.40")
        XCTAssertEqual(breakdown.rows.last?.value, estimate.totalKilocalories.formatted(.number.precision(.fractionLength(0))) + " kcal")
        XCTAssertFalse(breakdown.rows.contains { $0.label.contains("训练") })
    }

    func testPeriodExpenditureUsesSameEstimateDaysAndWeightedComponents() throws {
        let snapshot = make(.month, records: [], hasProfile: true)
        let rows = ProgressEnergyBreakdown(snapshot: snapshot, kind: .expenditure).rows
        XCTAssertEqual(snapshot.estimateDayCount, 4)
        XCTAssertEqual(rows.last?.label, "日均预估总消耗")
        XCTAssertEqual(rows.last?.value, try XCTUnwrap(snapshot.averageEstimate?.formatted(.number.precision(.fractionLength(0)))) + " kcal")
    }

    func testEmptyAndUnavailableHaveSmallHonestLists() {
        let snapshot = make(.day, records: [])
        let intake = ProgressEnergyBreakdown(snapshot: snapshot, kind: .intake)
        XCTAssertEqual(intake.rows.count, 1)
        XCTAssertEqual(intake.rows.first?.value, "0 kcal")
        let expenditure = ProgressEnergyBreakdown(snapshot: snapshot, kind: .expenditure)
        XCTAssertEqual(expenditure.rows.count, 1)
        XCTAssertEqual(expenditure.rows.first?.value, "缺少静息资料")
    }

    func testPeriodFactorUsesWeightedRestingAndSameDailyEstimates() throws {
        let weights = [
            ProgressHistoryRecord(activity: .init(id: UUID(), kind: .body, date: date(1), title: "A", detail: "", metric: nil), weight: 60),
            ProgressHistoryRecord(activity: .init(id: UUID(), kind: .body, date: date(2), title: "B", detail: "", metric: nil), weight: 90)
        ]
        let profile = ProgressProfileFacts(
            updatedAt: date(1), birthDate: calendar.date(from: DateComponents(year: 1996, month: 1, day: 1)),
            height: 170, biologicalSex: .male,
            baselines: [.init(effectiveFrom: date(2), factor: 1.8, label: "个人设置")]
        )
        let snapshot = ProgressHistoryProjection.build(
            window: ProgressPeriod.month.window(containing: date(5), calendar: calendar), records: weights,
            profile: profile, now: date(5), calendar: calendar
        )
        let rows = ProgressEnergyBreakdown(snapshot: snapshot, kind: .expenditure).rows
        let estimates = snapshot.days.filter(\.isCompleteDay).compactMap(\.energy.estimate)
        let ratio = estimates.reduce(0) { $0 + $1.totalKilocalories } / estimates.reduce(0) { $0 + $1.restingKilocalories }
        XCTAssertEqual(rows[2].value, ratio.formatted(.number.precision(.fractionLength(2))))
        XCTAssertEqual(rows.last?.value, try XCTUnwrap(snapshot.averageEstimate).formatted(.number.precision(.fractionLength(0))) + " kcal")
    }

    private func make(_ period: ProgressPeriod, records: [ProgressHistoryRecord], hasProfile: Bool = false) -> ProgressHistorySnapshot {
        let body = ProgressHistoryRecord(activity: .init(id: UUID(), kind: .body, date: date(1), title: "虚构体重", detail: "", metric: nil), weight: 70)
        let profile = ProgressProfileFacts(
            updatedAt: date(1), birthDate: calendar.date(from: DateComponents(year: 1996, month: 1, day: 1)),
            height: 170, biologicalSex: .male, baselines: []
        )
        return ProgressHistoryProjection.build(
            window: period.window(containing: date(5), calendar: calendar), records: records + (hasProfile ? [body] : []),
            profile: hasProfile ? profile : nil, now: date(5).addingTimeInterval(3600), calendar: calendar
        )
    }

    private func record(_ day: Int, _ kind: ProgressRecentActivity.Kind, _ title: String, _ calories: Double?) -> ProgressHistoryRecord {
        .init(activity: .init(id: UUID(), kind: kind, date: date(day), title: title, detail: "", metric: nil), calories: calories)
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }
}
