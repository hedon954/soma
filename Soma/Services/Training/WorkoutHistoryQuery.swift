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
    /// `DateFormatter` 构造是毫秒级开销；日期头在列表每次 body 重算时读取，
    /// 必须复用同一个实例。格式固定为中文，不随系统 locale 变化。
    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    let day: Date
    let workouts: [WorkoutEntry]

    var id: Date {
        day
    }

    var title: String {
        Self.dayTitleFormatter.string(from: day)
    }

    var actionCountText: String {
        "\(workouts.count) 个动作"
    }

    /// 只累加完整有效容量；缺重量或次数的动作不计入、也不补零。
    var totalKnownVolumeKG: Double? {
        let volumes = workouts.compactMap(\.estimatedVolume)
        guard !volumes.isEmpty else { return nil }
        return volumes.reduce(0, +)
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
        HistoryDayGrouping.grouped(
            workouts,
            date: \.date,
            calendar: calendar
        )
        .map { day, items in
            WorkoutHistoryDayGroup(day: day, workouts: items)
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
                workout.externalSource == nil
                    && workout.date >= start
                    && workout.date < end
            }
        } else {
            descriptor.predicate = #Predicate<WorkoutEntry> { workout in
                workout.externalSource == nil
            }
        }
        return descriptor
    }
}

struct MealHistoryDayGroup: Identifiable {
    let day: Date
    let meals: [MealEntry]

    var id: Date {
        day
    }

    var title: String {
        WorkoutHistoryDayGroup(day: day, workouts: []).title
    }

    var mealCountText: String {
        "\(meals.count) 餐"
    }

    /// 只累加已有热量；缺项保持为空，不把未估算写成 0。
    var totalKnownCalories: Int? {
        let values = meals.compactMap(\.calories)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }
}

enum MealHistoryQuery {
    static let pageSize = WorkoutHistoryQuery.pageSize

    static func groupedByDay(
        _ meals: [MealEntry],
        calendar: Calendar = .current
    ) -> [MealHistoryDayGroup] {
        HistoryDayGrouping.grouped(
            meals,
            date: \.date,
            calendar: calendar
        )
        .map { day, items in
            MealHistoryDayGroup(day: day, meals: items)
        }
    }

    static func fetchDescriptor(
        filter: WorkoutHistoryDateFilter,
        offset: Int,
        limit: Int = pageSize,
        calendar: Calendar = .current
    ) -> FetchDescriptor<MealEntry> {
        var descriptor = FetchDescriptor<MealEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = max(0, offset)
        if let interval = filter.dateInterval(calendar: calendar) {
            let start = interval.start
            let end = interval.end
            descriptor.predicate = #Predicate<MealEntry> { meal in
                meal.date >= start && meal.date < end
            }
        }
        return descriptor
    }
}

struct BodyHistoryDayGroup: Identifiable {
    let day: Date
    let entries: [BodyEntry]

    var id: Date {
        day
    }

    var title: String {
        WorkoutHistoryDayGroup(day: day, workouts: []).title
    }

    var recordCountText: String {
        "\(entries.count) 条记录"
    }
}

enum BodyHistoryQuery {
    static let pageSize = WorkoutHistoryQuery.pageSize

    static func groupedByDay(
        _ entries: [BodyEntry],
        calendar: Calendar = .current
    ) -> [BodyHistoryDayGroup] {
        HistoryDayGrouping.grouped(
            entries,
            date: \.date,
            calendar: calendar
        )
        .map { day, items in
            BodyHistoryDayGroup(day: day, entries: items)
        }
    }
}

enum HistoryDayGrouping {
    static func grouped<Item>(
        _ items: [Item],
        date: KeyPath<Item, Date>,
        calendar: Calendar = .current
    ) -> [(day: Date, items: [Item])] {
        var buckets: [Date: [Item]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item[keyPath: date])
            buckets[day, default: []].append(item)
        }
        return buckets.keys.sorted(by: >).map { day in
            (
                day: day,
                items: (buckets[day] ?? []).sorted {
                    $0[keyPath: date] > $1[keyPath: date]
                }
            )
        }
    }
}

enum HistoryMonthFilterChips {
    static func chips(
        from choices: (
            years: [Int],
            monthsByYear: [Int: [Int]],
            daysByYearMonth: [Int: [Int: [Int]]]
        ),
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [(filter: WorkoutHistoryDateFilter, title: String)] {
        let currentYear = calendar.component(.year, from: now)
        let spansYears = choices.years.count > 1
        var result: [(WorkoutHistoryDateFilter, String)] = [(.all, "全部")]
        for year in choices.years {
            for month in choices.monthsByYear[year] ?? [] {
                let title = spansYears || year != currentYear
                    ? "\(year)年\(month)月"
                    : "\(month)月"
                result.append((.yearMonth(year: year, month: month), title))
            }
        }
        return result
    }
}
