@testable import Soma
import XCTest

/// PRD 033：饮食记录的时间是钟点，不是当天零点；餐次按记录发生时刻推断。
final class MealOccurrenceTimeTests: XCTestCase {
    private let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try XCTUnwrap(calendar().date(from: components))
    }

    func testDefaultOccurredAtKeepsSendClockTimeOnTheBusinessDay() throws {
        let turnSentAt = try date(2026, 8, 20, 12, 41)
        let businessDate = try date(2026, 8, 20, 0, 0)

        let resolved = BusinessDateResolver.defaultOccurredAt(
            turnSentAt: turnSentAt,
            businessDate: businessDate,
            timeZone: timeZone
        )

        let components = calendar().dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: resolved
        )
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 41)
        XCTAssertEqual(components.day, 20)
    }

    /// 夜里补记昨天午餐时，钟点跟着业务日，餐次不能被现在的时间带成夜宵。
    func testBackdatedRecordKeepsClockTimeAndInfersMealTypeFromIt() throws {
        let turnSentAt = try date(2026, 8, 20, 12, 30)
        let businessDate = try date(2026, 8, 19, 0, 0)

        let resolved = BusinessDateResolver.defaultOccurredAt(
            turnSentAt: turnSentAt,
            businessDate: businessDate,
            timeZone: timeZone
        )

        let components = calendar().dateComponents(
            [.day, .hour, .minute],
            from: resolved
        )
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 30)
    }

    @MainActor
    func testInferredMealTypeFollowsRecordTimeNotWallClock() throws {
        XCTAssertEqual(
            try ConversationRecorder.inferredMealType(at: date(2026, 8, 20, 8, 0)),
            .breakfast
        )
        XCTAssertEqual(
            try ConversationRecorder.inferredMealType(at: date(2026, 8, 20, 12, 30)),
            .lunch
        )
        XCTAssertEqual(
            try ConversationRecorder.inferredMealType(at: date(2026, 8, 20, 19, 15)),
            .dinner
        )
        XCTAssertEqual(
            try ConversationRecorder.inferredMealType(at: date(2026, 8, 20, 23, 40)),
            .snack
        )
    }
}
