import Foundation
import SwiftData

enum WorkoutHistoryDateFilter: Equatable, Sendable {
    case all
    case year(Int)
    case yearMonth(year: Int, month: Int)
    case day(year: Int, month: Int, day: Int)

    var label: String {
        switch self {
        case .all:
            "全部"
        case let .year(year):
            "\(year)年"
        case let .yearMonth(year, month):
            "\(year)年\(month)月"
        case let .day(year, month, day):
            "\(year)年\(month)月\(day)日"
        }
    }

    func dateInterval(calendar: Calendar = .current) -> (start: Date, end: Date)? {
        switch self {
        case .all:
            return nil
        case let .year(year):
            guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start)
            else {
                return nil
            }
            return (start, end)
        case let .yearMonth(year, month):
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start)
            else {
                return nil
            }
            return (start, end)
        case let .day(year, month, day):
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  let end = calendar.date(byAdding: .day, value: 1, to: start)
            else {
                return nil
            }
            return (start, end)
        }
    }
}

struct WorkoutHistoryDayGroup: Identifiable {
    let day: Date
    let workouts: [WorkoutEntry]

    var id: Date {
        day
    }

    var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: day)
    }
}

enum WorkoutHistoryQuery {
    static let pageSize = 50

    /// Years / months / days that actually contain workouts, newest first.
    static func filterChoices(
        from dates: [Date],
        calendar: Calendar = .current
    ) -> (
        years: [Int],
        monthsByYear: [Int: [Int]],
        daysByYearMonth: [Int: [Int: [Int]]]
    ) {
        var yearSet = Set<Int>()
        var monthsByYear: [Int: Set<Int>] = [:]
        var daysByYearMonth: [Int: [Int: Set<Int>]] = [:]

        for date in dates {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day else {
                continue
            }
            yearSet.insert(year)
            monthsByYear[year, default: []].insert(month)
            daysByYearMonth[year, default: [:]][month, default: []].insert(day)
        }

        let years = yearSet.sorted(by: >)
        let months = monthsByYear.mapValues { $0.sorted(by: >) }
        let days = daysByYearMonth.mapValues { monthMap in
            monthMap.mapValues { $0.sorted(by: >) }
        }
        return (years, months, days)
    }

    static func groupedByDay(
        _ workouts: [WorkoutEntry],
        calendar: Calendar = .current
    ) -> [WorkoutHistoryDayGroup] {
        var buckets: [Date: [WorkoutEntry]] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.date)
            buckets[day, default: []].append(workout)
        }
        return buckets.keys.sorted(by: >).map { day in
            WorkoutHistoryDayGroup(
                day: day,
                workouts: (buckets[day] ?? []).sorted { $0.date > $1.date }
            )
        }
    }

    static func fetchDescriptor(
        filter: WorkoutHistoryDateFilter,
        offset: Int,
        limit: Int = pageSize,
        calendar: Calendar = .current
    ) -> FetchDescriptor<WorkoutEntry> {
        var descriptor = FetchDescriptor<WorkoutEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = max(0, offset)
        if let interval = filter.dateInterval(calendar: calendar) {
            let start = interval.start
            let end = interval.end
            descriptor.predicate = #Predicate<WorkoutEntry> { workout in
                workout.date >= start && workout.date < end
            }
        }
        return descriptor
    }
}
