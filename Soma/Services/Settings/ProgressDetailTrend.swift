import Foundation

enum ProgressDetailMetric: String, CaseIterable, Identifiable, Sendable {
    case trainingDays, sets, volume, duration, weight, bodyFat, waist
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .trainingDays: "训练天数"
        case .sets: "工作组"
        case .volume: "容量"
        case .duration: "时长"
        case .weight: "体重"
        case .bodyFat: "体脂率"
        case .waist: "腰围"
        }
    }

    var unit: String {
        switch self {
        case .trainingDays: "天"
        case .sets: "组"
        case .duration: "分钟"
        case .volume, .weight: "kg"
        case .bodyFat: "%"
        case .waist: "cm"
        }
    }

    var isBody: Bool {
        [.weight, .bodyFat, .waist].contains(self)
    }

    static func options(for kind: ProgressRecentActivity.Kind) -> [Self] {
        kind == .workout ? [.trainingDays, .sets, .volume, .duration] : [.weight, .bodyFat, .waist]
    }
}

struct ProgressDetailTrendPoint: Identifiable, Sendable {
    let id: String
    let date: Date
    let end: Date?
    let value: Double
    let record: ProgressRecentActivity?
    var sampleCount = 1
}

enum ProgressDetailTrend {
    static func showsMiniChart(snapshot: ProgressHistorySnapshot, metric: ProgressDetailMetric) -> Bool {
        guard snapshot.window.period != .day else { return false }
        let points = points(snapshot: snapshot, metric: metric)
        return (metric.isBody ? points : points.filter { $0.value > 0 }).count >= 2
    }

    static func points(snapshot: ProgressHistorySnapshot, metric: ProgressDetailMetric) -> [ProgressDetailTrendPoint] {
        if metric.isBody {
            let measurements: [ProgressDetailTrendPoint] = snapshot.days.flatMap(\.records).compactMap { record in
                guard record.activity.kind == .body else { return nil }
                let value: Double? = switch metric {
                case .weight: record.weight
                case .bodyFat: record.bodyFat
                case .waist: record.waist
                default: nil
                }
                guard let value, value.isFinite, value > 0 else { return nil }
                return .init(id: record.activity.id.uuidString, date: record.activity.date, end: nil, value: value, record: record.activity)
            }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            guard snapshot.window.period == .year else { return measurements }
            return snapshot.energyBuckets.compactMap { bucket in
                let samples = measurements.filter { $0.date >= bucket.start && $0.date < bucket.end }
                guard !samples.isEmpty else { return nil }
                return .init(id: "\(bucket.start.timeIntervalSince1970)", date: bucket.start,
                             end: nil, value: samples.reduce(0) { $0 + $1.value } / Double(samples.count),
                             record: nil, sampleCount: samples.count)
            }
        }
        return snapshot.energyBuckets.compactMap { bucket in
            let days = snapshot.days.filter { !$0.isFuture && $0.date >= bucket.start && $0.date < bucket.end }
            guard !days.isEmpty else { return nil }
            let value: Double = switch metric {
            case .trainingDays: Double(days.count(where: \.hasTraining))
            case .sets: Double(days.reduce(0) { $0 + $1.logicalSets })
            case .volume: days.reduce(0) { $0 + $1.volume.value }
            case .duration: days.flatMap(\.records).compactMap(\.durationSeconds).filter { $0.isFinite && $0 >= 0 }.reduce(0, +) / 60
            default: 0
            }
            return .init(id: "\(bucket.start.timeIntervalSince1970)", date: bucket.start, end: bucket.end, value: value, record: nil)
        }
    }
}

struct ProgressMuscleWorkload: Identifiable, Sendable {
    let name: String
    var primarySets = 0
    var secondarySets = 0
    var id: String {
        name
    }

    static func aggregate(_ records: [ProgressHistoryRecord]) -> [Self] {
        var result: [String: Self] = [:]
        for record in records where record.activity.kind == .workout && record.logicalSets > 0 {
            let primary = Set(record.primaryMuscles.filter { !$0.isEmpty })
            let secondary = Set(record.secondaryMuscles.filter { !$0.isEmpty }).subtracting(primary)
            for name in primary {
                result[name, default: .init(name: name)].primarySets += record.logicalSets
            }
            for name in secondary {
                result[name, default: .init(name: name)].secondarySets += record.logicalSets
            }
        }
        return result.values.sorted {
            let left = $0.primarySets + $0.secondarySets
            let right = $1.primarySets + $1.secondarySets
            return left == right ? $0.name < $1.name : left > right
        }
    }
}
