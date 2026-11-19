import Charts
import SwiftUI

enum ExerciseTrendMetric: String, CaseIterable, Identifiable {
    case capacity = "容量"
    case load = "重量"
    case repetitions = "次数"
    case duration = "时长"

    var id: String {
        rawValue
    }

    var unit: String {
        switch self {
        case .capacity, .load: "kg"
        case .repetitions: "次"
        case .duration: "秒"
        }
    }

    var accent: Color {
        switch self {
        case .capacity, .load: AppMetricRole.trainingLoad.accent
        case .repetitions, .duration: AppMetricRole.performance.accent
        }
    }

    func points(for observation: ExerciseEffortObservation) -> [ExerciseEffortTrendPoint] {
        guard self != .capacity else { return [] }
        var values: [String: Double] = [:]
        for effort in observation.efforts {
            let side = switch effort.side {
            case .some(.left): "左侧"
            case .some(.right): "右侧"
            default: "整组"
            }
            let series: String
            let value: Double?
            switch self {
            case .capacity: return []
            case .load:
                series = side
                value = effort.externalWeightKG.flatMap { $0 > 0 ? $0 : nil }
            case .repetitions:
                guard let weight = effort.externalWeightKG, weight.isFinite else { continue }
                series = side + (weight == 0 ? " · 自重" : " · \(weight.formatted()) kg")
                value = effort.reps.map(Double.init)
            case .duration:
                series = side
                value = effort.durationSeconds.map(Double.init)
            }
            guard let value, value.isFinite, value > 0 else { continue }
            values[series] = max(values[series] ?? 0, value)
        }
        return values.sorted { $0.key < $1.key }.map {
            .init(recordID: observation.id, date: observation.date, series: $0.key, value: $0.value)
        }
    }
}

struct ExerciseEffortObservation {
    let id: UUID
    let date: Date
    let efforts: [WorkoutSetEvidence]
}

struct ExerciseEffortTrendPoint: Identifiable {
    let recordID: UUID
    let date: Date
    let series: String
    let value: Double
    var id: String {
        "\(recordID):\(series)"
    }
}

struct ExerciseEffortTrends: View {
    let metric: ExerciseTrendMetric
    let observations: [ExerciseEffortObservation]
    @Binding var selectedRecord: UUID?
    @State private var selection: Date?

    var body: some View {
        let points = observations.reversed().flatMap { metric.points(for: $0) }
        if points.isEmpty {
            Text("还没有可比较的\(metric.rawValue)记录。")
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            let series = Array(Set(points.map(\.series))).sorted()
            Chart {
                ForEach(points) { point in
                    PointMark(x: .value("日期", point.date), y: .value(metric.rawValue, point.value))
                        .symbol(by: .value("系列", point.series))
                        .foregroundStyle(by: .value("系列", point.series))
                }
                if let selected = points.first(where: { $0.recordID == selectedRecord }) {
                    RuleMark(x: .value("选中日期", selected.date)).foregroundStyle(AppTheme.tint)
                }
            }
            .chartForegroundStyleScale(domain: series, range: Array(repeating: metric.accent, count: series.count))
            .chartXAxis { AxisMarks(values: Array(Set(points.map(\.date))).sorted()) { AxisValueLabel(format: .dateTime.month().day()) } }
            .chartXSelection(value: $selection)
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
            }
            .frame(height: 150)
            .accessibilityLabel("训练\(metric.rawValue)趋势，单位\(metric.unit)")
            .accessibilityIdentifier("exercise-effort-trend")
            .onChange(of: selection) {
                selectedRecord = selection.flatMap { date in
                    points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?.recordID
                }
            }
        }
    }
}
