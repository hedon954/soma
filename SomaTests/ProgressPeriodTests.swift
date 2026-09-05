@testable import Soma
import XCTest

final class ProgressPeriodTests: XCTestCase {
    func testWeekStartsMondayAndUsesHalfOpenBoundaryAcrossYear() throws {
        let calendar = try calendar("Asia/Shanghai")
        let window = ProgressPeriod.week.window(containing: date(2027, 1, 1, calendar), calendar: calendar)
        XCTAssertEqual(window.start, date(2026, 12, 28, calendar))
        XCTAssertEqual(window.end, date(2027, 1, 4, calendar))
        XCTAssertTrue(window.contains(window.start))
        XCTAssertFalse(window.contains(window.end))
        XCTAssertEqual(window.buckets(calendar: calendar).count, 7)
    }

    func testLeapMonthAndYearHaveNaturalBuckets() throws {
        let calendar = try calendar("Asia/Shanghai")
        let february = ProgressPeriod.month.window(containing: date(2028, 2, 20, calendar), calendar: calendar)
        XCTAssertEqual(february.buckets(calendar: calendar).count, 29)
        let year = ProgressPeriod.year.window(containing: date(2028, 2, 20, calendar), calendar: calendar)
        XCTAssertEqual(year.buckets(calendar: calendar).count, 12)
        XCTAssertEqual(year.buckets(calendar: calendar)[1].end, date(2028, 3, 1, calendar))
    }

    func testDayUsesCalendarDurationAcrossDaylightSaving() throws {
        let calendar = try calendar("America/New_York")
        let spring = ProgressPeriod.day.window(containing: date(2026, 3, 8, calendar), calendar: calendar)
        let autumn = ProgressPeriod.day.window(containing: date(2026, 11, 1, calendar), calendar: calendar)
        XCTAssertEqual(spring.end.timeIntervalSince(spring.start), 23 * 3600)
        XCTAssertEqual(autumn.end.timeIntervalSince(autumn.start), 25 * 3600)
    }

    func testMonthNavigationDoesNotSkipFebruaryFromJanuary31() throws {
        let calendar = try calendar("Asia/Shanghai")
        let january = ProgressPeriod.month.window(containing: date(2026, 1, 31, calendar), calendar: calendar)
        let february = january.shifted(by: 1, calendar: calendar)
        XCTAssertEqual(february.start, date(2026, 2, 1, calendar))
        XCTAssertEqual(february.shifted(by: -1, calendar: calendar), january)
    }

    func testNextPeriodGuardUsesCurrentPeriodNotTimeOfDay() throws {
        let calendar = try calendar("Asia/Shanghai")
        let now = date(2026, 9, 5, calendar)
        let month = ProgressPeriod.month.window(containing: now, calendar: calendar)
        XCTAssertFalse(month.canMoveForward(now: now, calendar: calendar))
        XCTAssertTrue(month.shifted(by: -1, calendar: calendar).canMoveForward(now: now, calendar: calendar))
    }

    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
