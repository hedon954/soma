@testable import Soma
import XCTest

final class WorkoutHistoryQueryTests: XCTestCase {
    func testDateFilterYearInterval() throws {
        let calendar = Calendar(identifier: .gregorian)
        let interval = WorkoutHistoryDateFilter.year(2026).dateInterval(calendar: calendar)

        XCTAssertEqual(
            try calendar.dateComponents([.year, .month, .day], from: XCTUnwrap(interval?.start)),
            DateComponents(year: 2026, month: 1, day: 1)
        )
        XCTAssertEqual(
            try calendar.dateComponents([.year, .month, .day], from: XCTUnwrap(interval?.end)),
            DateComponents(year: 2027, month: 1, day: 1)
        )
    }

    func testDateFilterYearMonthAndDayIntervals() throws {
        let calendar = Calendar(identifier: .gregorian)
        let month = try XCTUnwrap(WorkoutHistoryDateFilter.yearMonth(year: 2026, month: 8)
            .dateInterval(calendar: calendar))
        let day = try XCTUnwrap(WorkoutHistoryDateFilter.day(year: 2026, month: 8, day: 4)
            .dateInterval(calendar: calendar))

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: month.start),
            DateComponents(year: 2026, month: 8, day: 1)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: month.end),
            DateComponents(year: 2026, month: 9, day: 1)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: day.start),
            DateComponents(year: 2026, month: 8, day: 4)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: day.end),
            DateComponents(year: 2026, month: 8, day: 5)
        )
    }

    func testFilterChoicesDerivedFromActualWorkoutDates() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dates = try [
            XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 4))),
            XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))),
            XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 12))),
            XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 12, day: 31)))
        ]

        let choices = WorkoutHistoryQuery.filterChoices(from: dates, calendar: calendar)

        XCTAssertEqual(choices.years, [2026, 2024])
        XCTAssertEqual(choices.monthsByYear[2026], [8, 3])
        XCTAssertEqual(choices.daysByYearMonth[2026]?[8], [4, 1])
        XCTAssertNil(choices.monthsByYear[2025])
        XCTAssertEqual(choices.monthsByYear[2024], [12])
    }

    func testGroupedByDayOrdersNewestFirst() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayA = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 20)))
        let dayB = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10)))
        let laterSameDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 21)))

        let older = WorkoutEntry(
            date: dayA,
            exercise: "深蹲",
            notes: ""
        )
        let newest = WorkoutEntry(
            date: laterSameDay,
            exercise: "卧推",
            notes: ""
        )
        let previousDay = WorkoutEntry(
            date: dayB,
            exercise: "硬拉",
            notes: ""
        )

        let groups = WorkoutHistoryQuery.groupedByDay(
            [older, previousDay, newest],
            calendar: calendar
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].workouts.map(\.exercise), ["卧推", "深蹲"])
        XCTAssertEqual(groups[1].workouts.map(\.exercise), ["硬拉"])
        XCTAssertTrue(groups[0].title.contains("8月4日"))
        XCTAssertEqual(groups[0].actionCountText, "2 个动作")
        XCTAssertEqual(groups[1].actionCountText, "1 个动作")
        XCTAssertNil(groups[0].totalKnownVolumeKG)
    }

    func testWorkoutDaySummaryAddsCompleteVolumeOnly() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 20)))
        let complete = WorkoutEntry(
            date: day,
            exercise: "深蹲",
            sets: 4,
            reps: 5,
            weight: 60,
            notes: ""
        )
        let missingWeight = WorkoutEntry(
            date: day,
            exercise: "引体向上",
            sets: 3,
            reps: 8,
            notes: ""
        )
        let group = WorkoutHistoryQuery.groupedByDay(
            [complete, missingWeight],
            calendar: calendar
        )[0]

        XCTAssertEqual(group.actionCountText, "2 个动作")
        XCTAssertEqual(group.totalKnownVolumeKG, 1200)
    }

    func testMealDaySummaryAddsKnownCaloriesOnly() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 12)))
        let lunch = MealEntry(date: day, mealType: .lunch, title: "午饭", calories: 450)
        let snack = MealEntry(date: day, mealType: .snack, title: "加餐")
        let group = MealHistoryQuery.groupedByDay([lunch, snack], calendar: calendar)[0]

        XCTAssertEqual(group.mealCountText, "2 餐")
        XCTAssertEqual(group.totalKnownCalories, 450)
    }

    func testMealHistoryGroupsByDayNewestFirst() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayA = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 12)))
        let laterSameDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 18)))
        let previousDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 8)))

        let lunch = MealEntry(date: dayA, mealType: .lunch, title: "午饭")
        let dinner = MealEntry(date: laterSameDay, mealType: .dinner, title: "晚饭")
        let earlier = MealEntry(date: previousDay, mealType: .breakfast, title: "早饭")

        let groups = MealHistoryQuery.groupedByDay(
            [lunch, earlier, dinner],
            calendar: calendar
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].meals.map(\.title), ["晚饭", "午饭"])
        XCTAssertEqual(groups[1].meals.map(\.title), ["早饭"])
        XCTAssertTrue(groups[0].title.contains("8月20日"))
    }

    func testMonthFilterChipsPutAllFirstAndCollapseSameYear() throws {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        let current = try XCTUnwrap(calendar.date(from: components))
        let choices = try WorkoutHistoryQuery.filterChoices(
            from: [
                current,
                XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
            ],
            calendar: calendar
        )
        let chips = HistoryMonthFilterChips.chips(
            from: choices,
            calendar: calendar,
            now: current
        )

        XCTAssertEqual(chips.first?.filter, .all)
        XCTAssertEqual(chips.map(\.title), ["全部", "8月", "7月"])
    }
}
