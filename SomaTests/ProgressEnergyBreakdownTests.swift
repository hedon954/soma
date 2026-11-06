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
        XCTAssertEqual(rows.map(\.label), ["餐次未记录 · 早餐", "餐次未记录 · 晚餐"])
        XCTAssertEqual(rows[0].value, "400 kcal")
        XCTAssertEqual(rows[1].value, "未估算")
        XCTAssertEqual(snapshot.days.first?.intake.missingCount, 1)
        XCTAssertFalse(rows.contains { $0.id == "summary" })
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }

    func testMealTypesHaveExplicitPrefixesAndDistinctTones() {
        let records = MealType.allCases.enumerated().map { index, type in
            ProgressHistoryRecord(activity: .init(id: UUID(), kind: .meal, date: date(5).addingTimeInterval(Double(index)),
                                                  title: "虚构餐食", detail: type.rawValue, metric: nil), calories: 100)
        }
        let rows = ProgressEnergyBreakdown(snapshot: make(.day, records: records), kind: .intake).rows
        XCTAssertEqual(rows.map(\.label), MealType.allCases.map { $0.rawValue + " · 虚构餐食" })
        XCTAssertEqual(rows.map(\.tone), MealType.allCases.map { .mealType($0) })
    }

    func testPeriodIntakeUsesSameCompletedRecordedDaysAsDashboard() {
        let snapshot = make(.month, records: [
            record(1, .meal, "A", 1000), record(2, .meal, "B", 2000),
            record(3, .meal, "缺项", nil), record(5, .meal, "今天", 500),
            record(6, .meal, "未来", 9000)
        ])
        let rows = ProgressEnergyBreakdown(snapshot: snapshot, kind: .intake).rows
        XCTAssertEqual(rows.map(\.value), ["1,000 kcal", "2,000 kcal"])
        XCTAssertFalse(rows.contains { $0.label.contains("日均") })
        XCTAssertEqual(snapshot.averageIntake, 1500)
    }

    func testExpenditureShowsEffectiveFactorAndTrainingAfterTimeReplacement() {
        let snapshot = make(.day, records: [record(5, .workout, "训练", 800, calorieMET: 5)], hasProfile: true)
        let breakdown = ProgressEnergyBreakdown(snapshot: snapshot, kind: .expenditure)
        XCTAssertEqual(breakdown.rows.map(\.label), ["静息消耗", "基准额外消耗", "活动消耗"])
        XCTAssertEqual(breakdown.rows[0].value, "1,618 kcal")
        XCTAssertEqual(breakdown.rows[1].value, "647 kcal")
        XCTAssertEqual(breakdown.rows[2].value, "640 kcal")
        XCTAssertEqual(breakdown.rows[2].tone, .activity)
        XCTAssertFalse(breakdown.rows.contains { $0.label.contains("预估总消耗") })
    }

    func testDailyExpenditureListsEachWorkoutRecord() {
        let snapshot = make(.day, records: [
            record(5, .workout, "深蹲", 350),
            record(5, .workout, "跑步", nil)
        ])
        let rows = ProgressEnergyBreakdown(snapshot: snapshot, kind: .expenditure).rows
        XCTAssertEqual(rows.map(\.label), ["预估总消耗", "深蹲", "跑步"])
        XCTAssertEqual(rows[1].value, "350 kcal")
        XCTAssertEqual(rows[2].value, "未估算")
        XCTAssertEqual(rows.suffix(2).map(\.tone), [.workout, .workout])
    }

    func testPeriodExpenditureUsesSameEstimateDaysAndWeightedComponents() {
        let snapshot = make(.month, records: [], hasProfile: true)
        let rows = ProgressEnergyBreakdown(snapshot: snapshot, kind: .expenditure).rows
        XCTAssertEqual(snapshot.estimateDayCount, 4)
        XCTAssertEqual(rows.map(\.label), ["日均静息消耗", "日均基准额外消耗", "日均活动消耗"])
        XCTAssertEqual(rows[2].value, "未记录")
        XCTAssertFalse(rows.contains { $0.label.contains("预估总消耗") })
    }

    func testEmptyAndUnavailableHaveSmallHonestLists() {
        let snapshot = make(.day, records: [])
        let intake = ProgressEnergyBreakdown(snapshot: snapshot, kind: .intake)
        XCTAssertTrue(intake.rows.isEmpty)
        let expenditure = ProgressEnergyBreakdown(snapshot: snapshot, kind: .expenditure)
        XCTAssertEqual(expenditure.rows.count, 1)
        XCTAssertEqual(expenditure.rows.first?.value, "缺少静息资料")
        let protein = ProgressEnergyBreakdown(snapshot: snapshot, kind: .protein)
        XCTAssertTrue(protein.rows.isEmpty)
    }

    func testDailyProteinListsMealGramsAndPreservesMissingEvidence() {
        let snapshot = make(.day, records: [
            record(5, .meal, "早餐", 400, protein: 38),
            record(5, .meal, "晚餐", 500),
            record(5, .workout, "虚构训练", 300, protein: 99)
        ])
        let rows = ProgressEnergyBreakdown(snapshot: snapshot, kind: .protein).rows
        XCTAssertEqual(rows.map(\.label), ["餐次未记录 · 早餐", "餐次未记录 · 晚餐"])
        XCTAssertEqual(rows[0].value, "38 g")
        XCTAssertEqual(rows[1].value, "未记录")
        XCTAssertEqual(rows.map(\.tone), [.protein, .protein])
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }

    func testDailyCarbsAndFatUseTheirOwnSummaries() {
        let snapshot = make(.day, records: [
            record(5, .meal, "午餐", 600, carbs: 72, fat: 18)
        ])
        let carbs = ProgressEnergyBreakdown(snapshot: snapshot, kind: .carbs).rows
        XCTAssertEqual(carbs.map(\.label), ["餐次未记录 · 午餐"])
        XCTAssertEqual(carbs[0].value, "72 g")
        XCTAssertEqual(carbs.map(\.tone), [.carbs])
        let fat = ProgressEnergyBreakdown(snapshot: snapshot, kind: .fat).rows
        XCTAssertEqual(fat.map(\.label), ["餐次未记录 · 午餐"])
        XCTAssertEqual(fat[0].value, "18 g")
        XCTAssertEqual(fat.map(\.tone), [.fat])
    }

    func testPeriodProteinUsesSameCompletedRecordedDaysAsDashboard() {
        let snapshot = make(.month, records: [
            record(1, .meal, "A", 1000, protein: 40),
            record(2, .meal, "B", 2000, protein: 80),
            record(3, .meal, "缺项", nil),
            record(5, .meal, "今天", 500, protein: 20),
            record(6, .meal, "未来", 9000, protein: 999)
        ])
        let rows = ProgressEnergyBreakdown(snapshot: snapshot, kind: .protein).rows
        XCTAssertEqual(rows.map(\.value), ["40 g", "80 g"])
        XCTAssertFalse(rows.contains { $0.label.contains("日均") })
        XCTAssertEqual(rows.map(\.tone), [.protein, .protein])
    }

    func testPeriodFactorUsesWeightedRestingAndSameDailyEstimates() {
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
        let components = snapshot.days.filter(\.isCompleteDay).compactMap(\.energy.estimate?.components)
        let count = Double(components.count)
        let resting = components.reduce(0) { $0 + $1.restingKilocalories } / count
        let extra = components.reduce(0) { $0 + $1.baselineExtraKilocalories } / count
        let activity = components.reduce(0) { $0 + $1.activityKilocalories } / count
        XCTAssertEqual(components.map(\.coefficient), Array(repeating: ResidualEnergyCoefficient.initialFallback, count: components.count))
        XCTAssertEqual(resting + extra + activity, components.reduce(0) { $0 + $1.totalKilocalories } / count, accuracy: 0.001)
        XCTAssertEqual(rows.map(\.label), ["日均静息消耗", "日均基准额外消耗", "日均活动消耗"])
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

    private func record(
        _ day: Int,
        _ kind: ProgressRecentActivity.Kind,
        _ title: String,
        _ calories: Double?,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        calorieMET: Double? = nil
    ) -> ProgressHistoryRecord {
        .init(
            activity: .init(id: UUID(), kind: kind, date: date(day), title: title, detail: "", metric: nil),
            calories: calories,
            calorieMET: calorieMET,
            protein: protein,
            carbs: carbs,
            fat: fat,
            durationSeconds: calorieMET == nil ? nil : 3600
        )
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }
}
