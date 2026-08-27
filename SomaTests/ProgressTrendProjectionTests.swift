@testable import Soma
import XCTest

final class ProgressTrendProjectionTests: XCTestCase {
    func testDailySumKeepsThirtyDayWindowAndPartialTruth() throws {
        let (calendar, start, end) = try rangeFixture()
        let firstDay = start.addingTimeInterval(3600)
        let series = ProgressTrendProjection.dailySum(
            metric: .calorieIntake,
            samples: [
                ProgressTrendSample(date: firstDay, value: 500),
                ProgressTrendSample(date: firstDay.addingTimeInterval(3600), value: nil),
                ProgressTrendSample(date: firstDay.addingTimeInterval(7200), value: 300),
                ProgressTrendSample(date: start.addingTimeInterval(-1), value: 999)
            ],
            start: start,
            end: end,
            calendar: calendar
        )

        XCTAssertEqual(series.metric, .calorieIntake)
        XCTAssertEqual(series.points.count, 1)
        XCTAssertEqual(series.points[0].value, 800)
        XCTAssertEqual(series.points[0].itemCount, 3)
        XCTAssertTrue(series.points[0].isPartial)
    }

    func testDailyLatestUsesLastMeasurementOfEachDay() throws {
        let (calendar, start, end) = try rangeFixture()
        let day = start.addingTimeInterval(3600)
        let series = ProgressTrendProjection.dailyLatest(
            metric: .weight,
            samples: [
                ProgressTrendSample(date: day, value: 70.5),
                ProgressTrendSample(date: day.addingTimeInterval(3600), value: 70.1)
            ],
            start: start,
            end: end,
            calendar: calendar
        )

        XCTAssertEqual(series.points.count, 1)
        XCTAssertEqual(series.points[0].value, 70.1)
        XCTAssertEqual(series.points[0].itemCount, 2)
    }

    private func rangeFixture() throws -> (Calendar, Date, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 29
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 27,
            hour: 23
        )))
        return (calendar, start, end)
    }
}
