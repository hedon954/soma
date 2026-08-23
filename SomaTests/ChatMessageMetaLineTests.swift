import Foundation
@testable import Soma
import XCTest

final class ChatMessageMetaLineTests: XCTestCase {
    func testSameDayStillIncludesDateAndTime() throws {
        let calendar = fixedCalendar
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 22,
            hour: 18
        )))
        let messageDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 22,
            hour: 16,
            minute: 35
        )))

        let content = ChatMessageMetaLine.make(
            date: messageDate,
            locationName: nil,
            isFromCoach: true,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content.text, "8月22日 16:35")
        XCTAssertEqual(content.accessibilityLabel, "回复于 8月22日 16:35")
    }

    func testDifferentYearIncludesYearAndLocation() throws {
        let calendar = fixedCalendar
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 2
        )))
        let messageDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2025,
            month: 12,
            day: 31,
            hour: 9,
            minute: 8
        )))

        let content = ChatMessageMetaLine.make(
            date: messageDate,
            locationName: "演示健身房",
            isFromCoach: false,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content.text, "2025年12月31日 09:08 · 演示健身房")
        XCTAssertEqual(
            content.accessibilityLabel,
            "发送于 2025年12月31日 09:08，位置 演示健身房"
        )
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }
}
