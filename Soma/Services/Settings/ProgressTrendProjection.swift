import Foundation

enum ProgressTrendMetric: String, CaseIterable, Identifiable, Sendable {
    case trainingVolume
    case calorieIntake
    case weight

    var id: String {
        rawValue
    }
}

struct ProgressTrendSample: Equatable, Sendable {
    let date: Date
    let value: Double?
}

struct ProgressTrendPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let value: Double
    let itemCount: Int
    let isPartial: Bool

    var id: Date {
        date
    }
}

struct ProgressTrendSeries: Identifiable, Equatable, Sendable {
    let metric: ProgressTrendMetric
    let points: [ProgressTrendPoint]

    var id: ProgressTrendMetric {
        metric
    }
}

struct ProgressMetricBreakdownItem: Equatable, Sendable {
    let label: String
    let value: String
}

enum ProgressTrendProjection {
    static func dailySum(
        metric: ProgressTrendMetric,
        samples: [ProgressTrendSample],
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) -> ProgressTrendSeries {
        let relevant = samples.filter { $0.date >= start && $0.date <= end }
        let grouped = Dictionary(grouping: relevant) {
            calendar.startOfDay(for: $0.date)
        }
        let points = grouped.compactMap { day, samples -> ProgressTrendPoint? in
            let known = samples.compactMap(\.value)
            guard !known.isEmpty else { return nil }
            return ProgressTrendPoint(
                date: day,
                value: known.reduce(0, +),
                itemCount: samples.count,
                isPartial: samples.contains { $0.value == nil }
            )
        }.sorted { $0.date < $1.date }
        return ProgressTrendSeries(metric: metric, points: points)
    }

    static func dailyLatest(
        metric: ProgressTrendMetric,
        samples: [ProgressTrendSample],
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) -> ProgressTrendSeries {
        let relevant = samples.filter {
            $0.date >= start && $0.date <= end && $0.value != nil
        }
        let grouped = Dictionary(grouping: relevant) {
            calendar.startOfDay(for: $0.date)
        }
        let points = grouped.compactMap { day, samples -> ProgressTrendPoint? in
            guard let latest = samples.max(by: { $0.date < $1.date }),
                  let value = latest.value
            else {
                return nil
            }
            return ProgressTrendPoint(
                date: day,
                value: value,
                itemCount: samples.count,
                isPartial: false
            )
        }.sorted { $0.date < $1.date }
        return ProgressTrendSeries(metric: metric, points: points)
    }
}
