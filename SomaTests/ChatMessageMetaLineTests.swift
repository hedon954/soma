import Foundation
@testable import Soma
import XCTest

final class ChatMessageMetaLineTests: XCTestCase {
    func testAssistantMetaLineIsLeadingAlignedRegardlessOfStreamingLifecycle() {
        XCTAssertEqual(
            ChatMessageMetaLine.horizontalAlignment(isFromCoach: true),
            .leading,
            "AI 回复开始、流式中和完成后都必须固定在左下角"
        )
    }

    func testUserMetaLineRemainsTrailingAligned() {
        XCTAssertEqual(
            ChatMessageMetaLine.horizontalAlignment(isFromCoach: false),
            .trailing
        )
    }

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

    func testTimeZoneControlsBothClockAndYearBoundary() throws {
        let shanghai = fixedCalendar
        var utc = shanghai
        utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(shanghai.date(from: DateComponents(
            year: 2026, month: 1, day: 1, hour: 1, minute: 8
        )))
        let now = try XCTUnwrap(shanghai.date(from: DateComponents(
            year: 2026, month: 1, day: 2, hour: 12
        )))

        XCTAssertEqual(
            ChatMessageMetaLine.timeText(for: date, now: now, calendar: shanghai),
            "1月1日 01:08"
        )
        XCTAssertEqual(
            ChatMessageMetaLine.timeText(for: date, now: now, calendar: utc),
            "2025年12月31日 17:08"
        )
        XCTAssertEqual(
            ChatMessageMetaLine.timeText(for: date, now: now, calendar: shanghai),
            "1月1日 01:08",
            "切换时区不能污染后续格式化"
        )
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }
}
