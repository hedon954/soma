@testable import Soma
import XCTest

final class ProgressHistoryProjectionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testRecordedTotalKeepsUnknownAndRealZeroDistinct() {
        let total = ProgressRecordedTotal([120, nil, 80, 0, -.infinity])
        XCTAssertEqual(total.value, 200)
        XCTAssertEqual(total.knownCount, 3)
        XCTAssertEqual(total.missingCount, 2)
        XCTAssertEqual(ProgressRecordedTotal([]).value, 0)
        XCTAssertEqual(ProgressRecordedTotal([nil]).value, 0)
        XCTAssertEqual(ProgressRecordedTotal([nil]).missingCount, 1)
    }

    func testYearWeightsByRecordedDaysNotMonthlyMeans() throws {
        let records = [meal(date(1, 1), 1000), meal(date(2, 1), 2000), meal(date(2, 2), 2000)]
        let snapshot = build(.year, date(6, 1), records, now: date(7, 1))
        XCTAssertEqual(try XCTUnwrap(snapshot.averageIntake), 5000 / 3, accuracy: 0.001)
        XCTAssertEqual(snapshot.intakeDayCount, 3)
        XCTAssertEqual(snapshot.energyBuckets[0].intake, 1000)
        XCTAssertEqual(snapshot.energyBuckets[1].intake, 2000)
        XCTAssertEqual(snapshot.energyBuckets[1].intakeDayCount, 2)
    }

    func testCurrentDayIsVisibleButExcludedFromPeriodMeanAndFutureIsEmpty() {
        let snapshot = build(.month, date(9, 5), [meal(date(9, 4), 2000), meal(date(9, 5), 100), meal(date(9, 6), 9000)], now: date(9, 5, hour: 12))
        XCTAssertEqual(snapshot.averageIntake, 2000)
        XCTAssertEqual(snapshot.energyBuckets[4].intake, 100)
        XCTAssertNil(snapshot.energyBuckets[5].intake)
        XCTAssertTrue(snapshot.days[5].isFuture)
        XCTAssertEqual(snapshot.days[5].records.count, 0)
    }

    func testUnknownRecordDoesNotBecomeZeroChartPointOrCalibratingDay() {
        let snapshot = build(.week, date(9, 5), [meal(date(9, 4), nil)], now: date(9, 5))
        let day = snapshot.days.first { $0.date == date(9, 4) }
        XCTAssertEqual(day?.intake.value, 0)
        XCTAssertEqual(day?.intake.missingCount, 1)
        XCTAssertNil(snapshot.energyBuckets.first { $0.start == date(9, 4) }?.intake)
        XCTAssertEqual(snapshot.intakeDayCount, 0)
    }

    func testHistoryUsesPriorWeightInsteadOfLaterMeasurement() {
        let before = ProgressHistoryRecord(activity: activity(date(8, 30), .body), weight: 70)
        let after = ProgressHistoryRecord(activity: activity(date(9, 7), .body), weight: 90)
        let profile = ProgressProfileFacts(
            updatedAt: date(8, 1), birthDate: calendar.date(from: DateComponents(year: 1996, month: 1, day: 1)),
            height: 170, biologicalSex: .male,
            baselines: [.init(effectiveFrom: date(8, 1), factor: 1.4, label: "本人确认")]
        )
        let snapshot = ProgressHistoryProjection.build(
            window: ProgressPeriod.day.window(containing: date(9, 4), calendar: calendar),
            records: [before, after], profile: profile, now: date(9, 8), calendar: calendar
        )
        XCTAssertEqual(snapshot.days.first?.restingFormula?.weightKG, 70)
        XCTAssertEqual(snapshot.days.first?.restingFormula?.age, 30)
        XCTAssertEqual(snapshot.days.first?.records.count, 0)
        XCTAssertNotNil(snapshot.days.first?.energy.estimate)
    }

    func testTrainingCaloriesAreNotAddedToEstimatedExpenditure() {
        let before = ProgressHistoryRecord(activity: activity(date(8, 30), .body), weight: 70)
        let workout = ProgressHistoryRecord(activity: activity(date(9, 4), .workout), calories: 500, logicalSets: 5)
        let profile = ProgressProfileFacts(
            updatedAt: date(8, 1), birthDate: calendar.date(from: DateComponents(year: 1996, month: 1, day: 1)),
            height: 170, biologicalSex: .male,
            baselines: [.init(effectiveFrom: date(8, 1), factor: 1.4, label: "本人确认")]
        )
        let snapshot = ProgressHistoryProjection.build(
            window: ProgressPeriod.day.window(containing: date(9, 4), calendar: calendar),
            records: [before, workout], profile: profile, now: date(9, 8), calendar: calendar
        )
        XCTAssertEqual(snapshot.days.first?.trainingCalories.value, 500)
        XCTAssertEqual(snapshot.averageEstimate, (700 + 1062.5 - 150 + 5) * 1.4)
        XCTAssertEqual(snapshot.logicalSets, 5)
    }

    private func build(_ period: ProgressPeriod, _ anchor: Date, _ records: [ProgressHistoryRecord], now: Date) -> ProgressHistorySnapshot {
        ProgressHistoryProjection.build(window: period.window(containing: anchor, calendar: calendar), records: records, profile: nil, now: now, calendar: calendar)
    }

    private func meal(_ date: Date, _ calories: Double?) -> ProgressHistoryRecord {
        .init(activity: activity(date, .meal), calories: calories)
    }

    private func activity(_ date: Date, _ kind: ProgressRecentActivity.Kind) -> ProgressRecentActivity {
        .init(id: UUID(), kind: kind, date: date, title: "虚构记录", detail: "", metric: nil)
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
}
