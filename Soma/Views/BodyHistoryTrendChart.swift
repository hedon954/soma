import Charts
import SwiftUI

enum BodyHistoryTrendMetric: String, CaseIterable, Identifiable {
    case weight
    case bodyFat
    case waist

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .weight: "体重"
        case .bodyFat: "体脂率"
        case .waist: "腰围"
        }
    }

    var unit: String {
        switch self {
        case .weight: "kg"
        case .bodyFat: "%"
        case .waist: "cm"
        }
    }

    func value(in entry: BodyEntry) -> Double? {
        switch self {
        case .weight: entry.weight
        case .bodyFat: entry.bodyFat
        case .waist: entry.waist
        }
    }
}

struct BodyHistoryTrendPoint: Identifiable {
    var id: UUID
    var date: Date
    var value: Double
}

struct BodyHistoryTrendChart: View {
    let entries: [BodyEntry]
    @State private var metric: BodyHistoryTrendMetric = .weight
    @State private var selectedDate: Date?

    private var points: [BodyHistoryTrendPoint] {
        entries.compactMap { entry in
            guard let value = metric.value(in: entry), value.isFinite else { return nil }
            return BodyHistoryTrendPoint(id: entry.id, date: entry.date, value: value)
        }
        .sorted { $0.date < $1.date }
    }

    private var selected: BodyHistoryTrendPoint? {
        guard let selectedDate else { return points.last }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("指标", selection: $metric) {
                ForEach(BodyHistoryTrendMetric.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("body-history-trend-metric")

            if points.isEmpty {
                ContentUnavailableView(
                    "未记录\(metric.title)",
                    systemImage: "chart.xyaxis.line",
                    description: Text(emptyDescription)
                )
                .frame(minHeight: 160)
            } else {
                Text(metric.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value(metric.title, point.value)
                        )
                        .foregroundStyle(AppTheme.bodyAccent)
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value(metric.title, point.value)
                        )
                        .foregroundStyle(AppTheme.bodyAccent)
                    }
                    if let selected {
                        RuleMark(x: .value("所选日期", selected.date))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartXScale(domain: xDomain)
                .chartYScale(domain: yRange)
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .frame(height: 200)
                .accessibilityLabel("\(metric.title)趋势，单位\(metric.unit)")
                .accessibilityIdentifier("body-history-trend-chart")

                if let selected {
                    HStack {
                        Text(selected.date.formatted(date: .abbreviated, time: .shortened))
                        Spacer()
                        Text(
                            "\(selected.value.formatted(.number.precision(.fractionLength(0 ... 1)))) \(metric.unit)"
                        )
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                }
            }
        }
        .onChange(of: metric) { selectedDate = nil }
    }

    private var emptyDescription: String {
        switch metric {
        case .weight:
            "连接 Apple 健康后会自动同步体重；也可把体重发给教练记录。"
        case .bodyFat, .waist:
            "本迭代体脂与腰围使用本地或教练记录，不会从 Apple 健康自动同步。"
        }
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = points.first?.date, let last = points.last?.date else {
            let now = Date()
            return now.addingTimeInterval(-86400) ... now
        }
        if first == last {
            return first.addingTimeInterval(-86400) ... last.addingTimeInterval(86400)
        }
        return first ... last
    }

    private var yRange: ClosedRange<Double> {
        let values = points.map(\.value)
        let lower = values.min() ?? 0
        let upper = values.max() ?? 1
        let margin = max(1, (upper - lower) * 0.1)
        return max(0, lower - margin) ... (upper + margin)
    }
}
