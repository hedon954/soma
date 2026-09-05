import Foundation

enum ProgressPeriod: String, CaseIterable, Identifiable, Codable, Sendable {
    case day, week, month, year

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        case .year: "年"
        }
    }

    var returnTitle: String {
        switch self {
        case .day: "回到今天"
        case .week: "回到本周"
        case .month: "回到本月"
        case .year: "回到今年"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    func window(containing date: Date, calendar: Calendar = .current) -> ProgressPeriodWindow {
        var calendar = calendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let interval = calendar.dateInterval(of: component, for: date)
        let start = interval?.start ?? calendar.startOfDay(for: date)
        let end = interval?.end ?? calendar.date(byAdding: component, value: 1, to: start) ?? start
        return ProgressPeriodWindow(period: self, start: start, end: end)
    }
}

struct ProgressPeriodWindow: Hashable, Sendable {
    let period: ProgressPeriod
    let start: Date
    let end: Date

    /// Foundation DateInterval.contains includes its upper bound; record queries must not.
    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    func shifted(by amount: Int, calendar: Calendar = .current) -> Self {
        let anchor = calendar.date(byAdding: period.component, value: amount, to: start) ?? start
        return period.window(containing: anchor, calendar: calendar)
    }

    func canMoveForward(now: Date = .now, calendar: Calendar = .current) -> Bool {
        shifted(by: 1, calendar: calendar).start <= period.window(containing: now, calendar: calendar).start
    }

    func buckets(calendar: Calendar = .current) -> [ProgressDateBucket] {
        let component: Calendar.Component = period == .year ? .month : .day
        var cursor = start
        var result: [ProgressDateBucket] = []
        while cursor < end,
              let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor
        {
            result.append(ProgressDateBucket(start: cursor, end: min(next, end)))
            cursor = next
        }
        return result
    }

    func title(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        switch period {
        case .day: formatter.dateFormat = "yyyy年M月d日"
        case .week: formatter.dateFormat = "M月d日"
        case .month: formatter.dateFormat = "yyyy年M月"
        case .year: formatter.dateFormat = "yyyy年"
        }
        guard period == .week else { return formatter.string(from: start) }
        let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? start
        if calendar.component(.year, from: start) != calendar.component(.year, from: lastDay) {
            formatter.dateFormat = "yyyy年M月d日"
        }
        return "\(formatter.string(from: start))—\(formatter.string(from: lastDay))"
    }
}

struct ProgressDateBucket: Hashable, Sendable, Identifiable {
    let start: Date
    let end: Date
    var id: Date {
        start
    }
}
