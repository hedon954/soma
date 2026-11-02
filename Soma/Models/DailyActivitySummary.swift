import Foundation

enum DailyActivityMetricKind: String, Codable, CaseIterable, Sendable {
    case steps, walkingRunningDistance, activeEnergy

    var title: String {
        switch self {
        case .steps: "步数"
        case .walkingRunningDistance: "步行与跑步距离"
        case .activeEnergy: "活动消耗"
        }
    }

    var unit: String {
        switch self {
        case .steps: "步"
        case .walkingRunningDistance: "km"
        case .activeEnergy: "kcal"
        }
    }

    func displayValue(_ value: Double?) -> String {
        guard let value else { return "—" }
        let displayed = self == .walkingRunningDistance ? value / 1000 : value
        return displayed.formatted(.number.precision(.fractionLength(self == .walkingRunningDistance ? 1 : 0)))
    }
}

struct DailyActivityDayKey: Codable, Hashable, Sendable {
    let start: Date
    let end: Date
    let calendarIdentifier: String
    let timeZoneIdentifier: String

    init(date: Date, calendar: Calendar) {
        start = calendar.startOfDay(for: date)
        end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        calendarIdentifier = String(describing: calendar.identifier)
        timeZoneIdentifier = calendar.timeZone.identifier
    }
}

struct HealthDataSource: Codable, Equatable, Hashable, Sendable {
    let name: String
    let bundleIdentifier: String
}

struct ActivitySourceAttribution: Codable, Equatable, Sendable {
    let sources: [HealthDataSource]
    let readAt: Date

    init?(sources: [HealthDataSource], readAt: Date) {
        let unique = Dictionary(sources.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { _, new in new })
        guard !unique.isEmpty else { return nil }
        self.sources = unique.values.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
        self.readAt = readAt
    }

    var label: String {
        sources.count == 1 ? sources[0].name : "多来源"
    }
}

struct DailyActivityMetric: Codable, Equatable, Sendable {
    enum Availability: String, Codable, Sendable {
        case loading, value, noReadableData, failed
    }

    var provider: String {
        "appleHealth"
    }

    var value: Double?
    var availability: Availability = .loading
    var readAt: Date?
    var source: ActivitySourceAttribution?

    mutating func replace(value: Double?, readAt: Date) {
        source = nil
        self.readAt = readAt
        guard let value else {
            self.value = nil
            availability = .noReadableData
            return
        }
        guard value.isFinite, value >= 0 else {
            self.value = nil
            availability = .failed
            return
        }
        self.value = value
        availability = .value
    }
}

struct DailyActivitySummary: Codable, Equatable, Sendable {
    let key: DailyActivityDayKey
    var metrics: [DailyActivityMetricKind: DailyActivityMetric] = [:]

    subscript(_ kind: DailyActivityMetricKind) -> DailyActivityMetric {
        get { metrics[kind] ?? DailyActivityMetric() }
        set { metrics[kind] = newValue }
    }
}

struct DailyActivityWindow: Equatable, Sendable {
    let calendar: Calendar
    let days: [DailyActivityDayKey]
    var localTrainingIntervals: [EnergyTimeInterval] = []

    init(containing date: Date, now: Date, calendar: Calendar, recent: Bool) {
        self.calendar = calendar
        let day = calendar.startOfDay(for: date)
        guard day <= now else { days = []; return }
        let start = recent ? calendar.date(byAdding: .day, value: -29, to: day) ?? day : day
        var result: [DailyActivityDayKey] = []
        var cursor = start
        while cursor <= day {
            let key = DailyActivityDayKey(date: cursor, calendar: calendar)
            guard key.end > cursor else { break }
            result.append(key)
            cursor = key.end
        }
        days = result
    }
}

struct DailyActivityValue: Sendable {
    let key: DailyActivityDayKey
    let value: Double?
}

struct DailyActivitySources: Sendable {
    let key: DailyActivityDayKey
    let source: ActivitySourceAttribution?
}

enum DailyActivityUpdate: Sendable {
    case values(DailyActivityMetricKind, [DailyActivityValue], Date)
    case sources(DailyActivityMetricKind, [DailyActivitySources])
    case failure(DailyActivityMetricKind)
    case sourceFailure(DailyActivityMetricKind)
    case trainingEvidence([HealthActivityDayEvidence])
    case trainingFailure
}
