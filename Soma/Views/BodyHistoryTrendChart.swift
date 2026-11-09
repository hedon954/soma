import Charts
import SwiftUI

struct BodyHistoryTrendPoint: Identifiable {
    var id: UUID
    var date: Date
    var value: Double
}

struct BodyHistoryTrendChart: View {
    let entries: [BodyEntry]
    @State private var selectedDate: Date?

    private var weightPoints: [BodyHistoryTrendPoint] {
        points(for: \.weight)
    }

    private var bodyFatPoints: [BodyHistoryTrendPoint] {
        points(for: \.bodyFat)
    }

    private var sharedDomain: ClosedRange<Date> {
        let dates = (weightPoints.map(\.date) + bodyFatPoints.map(\.date))
        guard let first = dates.min(), let last = dates.max() else {
            let now = Date()
            return now.addingTimeInterval(-86400) ... now
        }
        if first == last {
            return first.addingTimeInterval(-86400) ... last.addingTimeInterval(86400)
        }
        return first ... last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            metricChart(
                title: "体重",
                unit: "kg",
                points: weightPoints,
                emptyTitle: "未记录体重",
                emptyDescription: "连接 Apple 健康后会自动同步体重；也可把体重发给教练记录。",
                chartIdentifier: "body-history-trend-chart-weight"
            )
            metricChart(
                title: "体脂率",
                unit: "%",
                points: bodyFatPoints,
                emptyTitle: "未记录体脂率",
                emptyDescription: "体脂可来自本地/教练记录，或 Apple 健康中的体脂率样本；不会把不同时间的体重与体脂捏成同一次测量。",
                chartIdentifier: "body-history-trend-chart-body-fat",
                compactEmpty: true
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body-history-trend-section")
    }

    private func metricChart(
        title: String,
        unit: String,
        points: [BodyHistoryTrendPoint],
        emptyTitle: String,
        emptyDescription: String,
        chartIdentifier: String,
        compactEmpty: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let selected = selectedPoint(in: points) {
                    Text(
                        "\(selected.value.formatted(.number.precision(.fractionLength(0 ... 1)))) \(unit)"
                    )
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppTheme.bodyAccent)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title)，单位\(unit)")

            if points.isEmpty {
                Text(emptyTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(emptyDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, compactEmpty ? 4 : 8)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(AppTheme.bodyAccent)
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(AppTheme.bodyAccent)
                    }
                    if let selected = selectedPoint(in: points) {
                        RuleMark(x: .value("所选日期", selected.date))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartXScale(domain: sharedDomain)
                .chartYScale(domain: yRange(for: points))
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .frame(height: 132)
                .accessibilityLabel("\(title)趋势，单位\(unit)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(chartIdentifier)
    }

    private func points(for keyPath: KeyPath<BodyEntry, Double?>) -> [BodyHistoryTrendPoint] {
        entries.compactMap { entry in
            guard let value = entry[keyPath: keyPath], value.isFinite else { return nil }
            return BodyHistoryTrendPoint(id: entry.id, date: entry.date, value: value)
        }
        .sorted { $0.date < $1.date }
    }

    private func selectedPoint(in points: [BodyHistoryTrendPoint]) -> BodyHistoryTrendPoint? {
        guard !points.isEmpty else { return nil }
        guard let selectedDate else { return points.last }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private func yRange(for points: [BodyHistoryTrendPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        let lower = values.min() ?? 0
        let upper = values.max() ?? 1
        let margin = max(1, (upper - lower) * 0.1)
        return max(0, lower - margin) ... (upper + margin)
    }
}
