@testable import Soma
import XCTest

final class ProgressDetailTrendTests: XCTestCase {
    func testAnnualTrainingSumsLogicalSetsByMonthWithoutFutureZeros() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 3)))
        let records = [record(date, .workout, sets: 2), record(date.addingTimeInterval(86400), .workout, sets: 5)]
        let snapshot = ProgressHistoryProjection.build(window: ProgressPeriod.year.window(containing: date, calendar: calendar), records: records,
                                                       profile: nil, now: date.addingTimeInterval(86400 * 2), calendar: calendar)
        let sets = ProgressDetailTrend.points(snapshot: snapshot, metric: .sets)
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[1].value, 7)
        XCTAssertEqual(ProgressDetailTrend.points(snapshot: snapshot, metric: .trainingDays)[1].value, 2)
    }

    func testBodyUsesActualMeasurementTimesAndDoesNotCreateMissingMeasurements() {
        let date = Date(timeIntervalSince1970: 86400 * 20000)
        var first = record(date, .body)
        first.weight = 70
        first.bodyFat = 18
        var second = record(date.addingTimeInterval(3600), .body)
        second.weight = 69.9
        second.waist = 80
        let snapshot = ProgressHistoryProjection.build(window: ProgressPeriod.day.window(containing: date), records: [first, second], profile: nil,
                                                       now: date.addingTimeInterval(7200))
        let points = ProgressDetailTrend.points(snapshot: snapshot, metric: .weight)
        XCTAssertEqual(points.map(\.date), [first.activity.date, second.activity.date])
        XCTAssertEqual(points.map(\.value), [70, 69.9])
        XCTAssertEqual(ProgressDetailTrend.points(snapshot: snapshot, metric: .bodyFat).count, 1)
        XCTAssertEqual(ProgressDetailTrend.points(snapshot: snapshot, metric: .waist).first?.record?.id, second.activity.id)
    }

    func testFourPeriodsAndMetricChoicesMatchVisibleContract() {
        XCTAssertEqual(ProgressPeriod.allCases.map(\.title), ["日", "周", "月", "年"])
        XCTAssertEqual(ProgressDetailMetric.options(for: .workout), [.trainingDays, .sets, .volume, .duration])
        XCTAssertEqual(ProgressDetailMetric.options(for: .body), [.weight, .bodyFat, .waist])
    }

    func testAnnualBodyBucketsKeepMeasurementCountsAndSkipEmptyMonths() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 3)))
        var first = record(date, .body)
        first.weight = 70
        var second = record(date.addingTimeInterval(86400), .body)
        second.weight = 72
        let snapshot = ProgressHistoryProjection.build(window: ProgressPeriod.year.window(containing: date, calendar: calendar),
                                                       records: [first, second], profile: nil, now: date.addingTimeInterval(86400 * 2), calendar: calendar)
        let points = ProgressDetailTrend.points(snapshot: snapshot, metric: .weight)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.value, 71)
        XCTAssertEqual(points.first?.sampleCount, 2)
        XCTAssertNil(points.first?.record)
        XCTAssertFalse(ProgressDetailTrend.showsMiniChart(snapshot: snapshot, metric: .weight))
    }

    func testDaySummaryDoesNotRenderSingleBarOrWeightDot() {
        let date = Date(timeIntervalSince1970: 86400 * 20000)
        var body = record(date, .body)
        body.weight = 70
        let snapshot = ProgressHistoryProjection.build(window: ProgressPeriod.day.window(containing: date),
                                                       records: [body, record(date, .workout, sets: 5)], profile: nil, now: date.addingTimeInterval(7200))
        XCTAssertFalse(ProgressDetailTrend.showsMiniChart(snapshot: snapshot, metric: .sets))
        XCTAssertFalse(ProgressDetailTrend.showsMiniChart(snapshot: snapshot, metric: .weight))
    }

    func testMuscleGroupsPreservePrimaryAndSecondaryContributions() {
        var first = record(.now, .workout, sets: 3)
        first.primaryMuscles = ["股四头肌", "股四头肌"]
        first.secondaryMuscles = ["臀大肌"]
        var second = record(.now, .workout, sets: 2)
        second.primaryMuscles = ["臀大肌"]
        second.secondaryMuscles = ["股四头肌"]
        let totals = ProgressMuscleWorkload.aggregate([first, second])
        XCTAssertEqual(totals.first { $0.name == "股四头肌" }?.primarySets, 3)
        XCTAssertEqual(totals.first { $0.name == "股四头肌" }?.secondarySets, 2)
        XCTAssertEqual(totals.first { $0.name == "臀大肌" }?.primarySets, 2)
        XCTAssertEqual(totals.first { $0.name == "臀大肌" }?.secondarySets, 3)
    }

    private func record(_ date: Date, _ kind: ProgressRecentActivity.Kind, sets: Int = 0) -> ProgressHistoryRecord {
        .init(activity: .init(id: UUID(), kind: kind, date: date, title: "虚构记录", detail: "", metric: nil), logicalSets: sets)
    }
}
