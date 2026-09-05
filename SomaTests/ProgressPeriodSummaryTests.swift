@testable import Soma
import XCTest

final class ProgressPeriodSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testDayUsesRecordsWithoutPeriodSummary() {
        XCTAssertNil(ProgressPeriodSummary.make(snapshot: snapshot(.day, []), calendar: calendar))
    }

    func testWeekCountsTrainingDaysNotWorkoutsOrSetsInChart() throws {
        let result = try summary(.week, [workout(9, 1, sets: 3), workout(9, 1, sets: 5), workout(9, 3, sets: 2)])
        XCTAssertEqual(result.training.value, "训练 2 天 · 10 组")
        XCTAssertEqual(result.training.metric, .trainingDays)
        XCTAssertEqual(result.training.points.map(\.value).reduce(0, +), 2)
        XCTAssertTrue(result.training.points.allSatisfy { $0.value <= 1 })
    }

    func testMonthGroupsVolumeByClippedCalendarWeeksAndExcludesFuture() throws {
        let result = try summary(.month, [workout(9, 1, volume: 1000), workout(9, 2, volume: 2000), workout(9, 8, volume: 9000)])
        XCTAssertEqual(result.training.value, "总容量 3,000 kg")
        XCTAssertEqual(result.training.metric, .volume)
        XCTAssertEqual(result.training.points.count, 1)
        XCTAssertEqual(result.training.points.first?.date, date(9, 1))
        XCTAssertEqual(result.training.points.first?.value, 3000)
        XCTAssertEqual(result.training.detail, "训练 2 天 · 6 组")
    }

    func testYearShowsActiveMonthsAndMonthlyTrainingDays() throws {
        let result = try summary(.year, [workout(1, 2), workout(1, 2), workout(8, 3), workout(9, 2)])
        XCTAssertEqual(result.training.value, "累计训练 3 天")
        XCTAssertEqual(result.training.detail, "3 个月有训练")
        XCTAssertEqual(result.training.points.map(\.value).reduce(0, +), 3)
        XCTAssertEqual(result.training.points.count, 9)
    }

    func testMonthlyWeeksNeverIncludeAdjacentMonthRecords() throws {
        let facts = ProgressHistoryProjection.build(
            window: ProgressPeriod.month.window(containing: date(9, 5), calendar: calendar),
            records: [workout(8, 31, volume: 9000), workout(9, 1, volume: 100), workout(9, 7, volume: 200),
                      workout(9, 30, volume: 300), workout(10, 1, volume: 9000)],
            profile: nil, now: date(9, 30, hour: 18), calendar: calendar
        )
        let result = try XCTUnwrap(ProgressPeriodSummary.make(snapshot: facts, calendar: calendar))
        XCTAssertEqual(result.training.points.map(\.value), [100, 200, 0, 0, 300])
        XCTAssertEqual(result.training.points.last?.end, date(10, 1))
        XCTAssertEqual(result.training.points.map(\.value).reduce(0, +), facts.volume)
    }

    func testDetailDefaultsMatchPeriodFocus() {
        XCTAssertEqual(ProgressPeriodSummary.defaultTrainingMetric(for: .week), .trainingDays)
        XCTAssertEqual(ProgressPeriodSummary.defaultTrainingMetric(for: .month), .volume)
        XCTAssertEqual(ProgressPeriodSummary.defaultTrainingMetric(for: .year), .trainingDays)
    }

    func testWeekMeanUsesLatestValidWeightEachDayWithoutCarryingOldWeight() throws {
        let result = try summary(.week, [weight(8, 20, 90), weight(9, 1, 74), weight(9, 1, 72, hour: 12), weight(9, 3, 70)])
        XCTAssertEqual(result.body.value, "周均体重 71 kg")
        XCTAssertEqual(result.body.detail, "2 天有测量")
        XCTAssertEqual(result.body.points.map(\.value), [72, 70])
    }

    func testMonthShowsLatestWeightAndWithinMonthChangeOnlyWithTwoDays() throws {
        let result = try summary(.month, [weight(9, 1, 72), weight(9, 3, 70), weight(9, 8, 66)])
        XCTAssertEqual(result.body.value, "最新体重 70 kg")
        XCTAssertEqual(result.body.detail, "月内变化 −2 kg")
        XCTAssertNil(try summary(.month, [weight(9, 1, 72)]).body.detail)
        XCTAssertEqual(try summary(.month, []).body.value, "未记录体重")
    }

    func testYearShowsChangeBetweenObservedMonthlyMeansAndSkipsMissingMonths() throws {
        let result = try summary(.year, [weight(1, 2, 72), weight(1, 3, 74), weight(9, 2, 70)])
        XCTAssertEqual(result.body.value, "最新月均体重 70 kg")
        XCTAssertEqual(result.body.detail, "月均变化 −3 kg")
        XCTAssertEqual(result.body.points.map(\.value), [73, 70])
        XCTAssertNil(try summary(.year, [weight(9, 1, 72)]).body.detail)
    }

    private func summary(_ period: ProgressPeriod, _ records: [ProgressHistoryRecord]) throws -> ProgressPeriodSummary {
        try XCTUnwrap(ProgressPeriodSummary.make(snapshot: snapshot(period, records), calendar: calendar))
    }

    private func snapshot(_ period: ProgressPeriod, _ records: [ProgressHistoryRecord]) -> ProgressHistorySnapshot {
        ProgressHistoryProjection.build(window: period.window(containing: date(9, 5), calendar: calendar), records: records,
                                        profile: nil, now: date(9, 5, hour: 18), calendar: calendar)
    }

    private func workout(_ month: Int, _ day: Int, sets: Int = 3, volume: Double? = nil) -> ProgressHistoryRecord {
        .init(activity: .init(id: UUID(), kind: .workout, date: date(month, day), title: "虚构训练", detail: "", metric: nil),
              volume: volume, logicalSets: sets)
    }

    private func weight(_ month: Int, _ day: Int, _ value: Double, hour: Int = 0) -> ProgressHistoryRecord {
        .init(activity: .init(id: UUID(), kind: .body, date: date(month, day, hour: hour), title: "虚构测量", detail: "", metric: nil), weight: value)
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
}
