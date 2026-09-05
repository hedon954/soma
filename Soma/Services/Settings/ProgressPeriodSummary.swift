import Foundation

struct ProgressPeriodSummary: Sendable {
    struct Metric: Sendable {
        let value: String
        let detail: String?
        let metric: ProgressDetailMetric
        let chartLabel: String
        let points: [ProgressDetailTrendPoint]

        var showsChart: Bool {
            (metric.isBody ? points : points.filter { $0.value > 0 }).count >= 2
        }
    }

    let training: Metric
    let body: Metric

    static func make(snapshot: ProgressHistorySnapshot, calendar: Calendar = .current) -> Self? {
        let period = snapshot.window.period
        guard period != .day else { return nil }
        let training: Metric
        switch period {
        case .week:
            training = .init(value: "训练 \(snapshot.trainingDayCount) 天 · \(snapshot.logicalSets) 组", detail: nil,
                             metric: .trainingDays, chartLabel: "每日训练分布",
                             points: ProgressDetailTrend.points(snapshot: snapshot, metric: .trainingDays))
        case .month:
            training = .init(value: "总容量 \(number(snapshot.volume, decimals: 0)) kg",
                             detail: "训练 \(snapshot.trainingDayCount) 天 · \(snapshot.logicalSets) 组",
                             metric: .volume, chartLabel: "每周训练容量", points: weeklyVolume(snapshot, calendar: calendar))
        case .year:
            let points = ProgressDetailTrend.points(snapshot: snapshot, metric: .trainingDays)
            training = .init(value: "累计训练 \(snapshot.trainingDayCount) 天", detail: "\(points.count { $0.value > 0 }) 个月有训练",
                             metric: .trainingDays, chartLabel: "每月训练天数", points: points)
        case .day: return nil
        }
        return .init(training: training, body: bodySummary(snapshot))
    }

    static func defaultTrainingMetric(for period: ProgressPeriod) -> ProgressDetailMetric {
        period == .month ? .volume : .trainingDays
    }

    private static func bodySummary(_ snapshot: ProgressHistorySnapshot) -> Metric {
        let period = snapshot.window.period
        let points: [ProgressDetailTrendPoint] = period == .year
            ? ProgressDetailTrend.points(snapshot: snapshot, metric: .weight)
            : snapshot.days.filter { !$0.isFuture }.compactMap { day in
                guard let record = day.latestWeight, let weight = record.weight else { return nil }
                return .init(id: record.activity.id.uuidString, date: record.activity.date, end: nil,
                             value: weight, record: record.activity)
            }
        let chartLabel = period == .year ? "月均体重趋势" : "每日体重趋势"
        guard let first = points.first, let last = points.last else {
            return .init(value: "未记录体重", detail: nil, metric: .weight, chartLabel: chartLabel, points: [])
        }
        let value: String
        let detail: String?
        if period == .week {
            value = "周均体重 \(number(points.reduce(0) { $0 + $1.value } / Double(points.count))) kg"
            detail = "\(points.count) 天有测量"
        } else {
            value = "\(period == .year ? "最新月均体重" : "最新体重") \(number(last.value)) kg"
            detail = points.count >= 2 ? "\(period == .year ? "月均变化" : "月内变化") \(change(last.value - first.value)) kg" : nil
        }
        return .init(value: value, detail: detail, metric: .weight, chartLabel: chartLabel, points: points)
    }

    private static func weeklyVolume(_ snapshot: ProgressHistorySnapshot, calendar: Calendar) -> [ProgressDetailTrendPoint] {
        var result: [ProgressDetailTrendPoint] = []
        var start = snapshot.window.start
        while start < snapshot.window.end {
            let end = min(ProgressPeriod.week.window(containing: start, calendar: calendar).end, snapshot.window.end)
            guard end > start else { break }
            let days = snapshot.days.filter { !$0.isFuture && $0.date >= start && $0.date < end }
            if !days.isEmpty {
                result.append(.init(id: "week-\(start.timeIntervalSinceReferenceDate)", date: start, end: end,
                                    value: days.reduce(0) { $0 + $1.volume.value }, record: nil))
            }
            start = end
        }
        return result
    }

    private static func number(_ value: Double, decimals: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... decimals)))
    }

    private static func change(_ value: Double) -> String {
        (value < 0 ? "−" : value > 0 ? "+" : "") + number(abs(value))
    }
}
