import Foundation

struct EnergyTimeInterval: Codable, Equatable, Sendable {
    let start: Date
    let end: Date

    static func union(_ intervals: [Self], within day: DailyActivityDayKey) -> [Self] {
        let sorted = intervals.compactMap { interval -> Self? in
            let start = max(day.start, interval.start), end = min(day.end, interval.end)
            return start < end ? .init(start: start, end: end) : nil
        }.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var result: [Self] = []
        for interval in sorted {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = .init(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    static func complement(_ intervals: [Self], within day: DailyActivityDayKey) -> [Self] {
        var cursor = day.start
        var result: [Self] = []
        for interval in union(intervals, within: day) {
            if cursor < interval.start {
                result.append(.init(start: cursor, end: interval.start))
            }
            cursor = interval.end
        }
        if cursor < day.end {
            result.append(.init(start: cursor, end: day.end))
        }
        return result
    }

    static func crossesBoundary(start: Date, end: Date, intervals: [Self]) -> Bool {
        intervals.contains { interval in
            (start < interval.start && end > interval.start) || (start < interval.end && end > interval.end)
        }
    }
}

/// Private HealthKit-derived input; never a second public workout record.
struct HealthActivityDayEvidence: Codable, Equatable, Sendable {
    static let statisticsBasis = "health-merged-outside-training-v1"
    let day: DailyActivityDayKey
    let training: [EnergyTrainingEvent]
    let excludedIntervals: [EnergyTimeInterval]
    let nonTrainingKilometers: Double?
    let nonTrainingSteps: Double?
    let hasAmbiguousBoundarySamples: Bool
    let basisID: String
}
