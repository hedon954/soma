import Charts
import SwiftUI

struct ProgressDetailTrendView: View {
    let snapshot: ProgressHistorySnapshot
    let kind: ProgressRecentActivity.Kind
    @State private var metric: ProgressDetailMetric
    @State private var selectedDate: Date?

    init(snapshot: ProgressHistorySnapshot, kind: ProgressRecentActivity.Kind) {
        self.snapshot = snapshot
        self.kind = kind
        _metric = State(initialValue: kind == .workout ? ProgressPeriodSummary.defaultTrainingMetric(for: snapshot.window.period) : .weight)
    }

    private var points: [ProgressDetailTrendPoint] {
        ProgressDetailTrend.points(snapshot: snapshot, metric: metric)
    }

    private var accent: Color {
        metric.isBody ? AppTheme.bodyAccent : metric == .volume ? AppMetricRole.trainingLoad.accent : AppMetricRole.consistency.accent
    }

    private var selected: ProgressDetailTrendPoint? {
        guard let selectedDate else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("指标", selection: $metric) {
                ForEach(ProgressDetailMetric.options(for: kind)) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("progress-detail-metric")
            if points.isEmpty {
                ContentUnavailableView("未记录\(metric.title)", systemImage: "chart.xyaxis.line")
            } else {
                Text(metric.unit).font(.caption).foregroundStyle(.secondary)
                Chart {
                    ForEach(points) { point in
                        if let end = point.end {
                            RectangleMark(
                                xStart: .value("开始", point.date.addingTimeInterval(end.timeIntervalSince(point.date) * 0.2)),
                                xEnd: .value("结束", end.addingTimeInterval(-end.timeIntervalSince(point.date) * 0.2)),
                                yStart: .value("基线", 0), yEnd: .value(metric.title, point.value)
                            ).foregroundStyle(accent)
                        } else {
                            LineMark(x: .value("日期", point.date), y: .value(metric.title, point.value)).foregroundStyle(accent)
                            PointMark(x: .value("日期", point.date), y: .value(metric.title, point.value)).foregroundStyle(accent)
                        }
                    }
                    if let selected {
                        RuleMark(x: .value("所选日期", selected.date)).foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartXScale(domain: snapshot.window.start ... snapshot.window.end)
                .chartYScale(domain: range)
                .chartXSelection(value: $selectedDate)
                .chartGesture { proxy in
                    SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.month().day()) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .frame(height: 200)
                .accessibilityLabel("\(metric.title)趋势，单位\(metric.unit)")
                if let selected {
                    if let activity = selected.record {
                        NavigationLink { ProgressRecentActivityDestination(activity: activity) } label: { selectionLabel(selected) }
                    } else {
                        NavigationLink {
                            InsightsView(initialPeriod: snapshot.window.period == .year ? .month : .day, initialDate: selected.date)
                        } label: { selectionLabel(selected) }
                    }
                }
            }
        }.onChange(of: metric) { selectedDate = nil }
    }

    private func selectionLabel(_ point: ProgressDetailTrendPoint) -> some View {
        HStack {
            Text(point.date.formatted(snapshot.window.period == .year ? .dateTime.month() : .dateTime.month().day()))
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(metric.isBody && snapshot.window.period == .year ? "均值 " : "")\(point.value.formatted(.number.precision(.fractionLength(0 ... 1)))) \(metric.unit)")
                if metric.isBody, snapshot.window.period == .year {
                    Text("\(point.sampleCount) 次测量").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.font(.subheadline).frame(minHeight: 44).foregroundStyle(.primary)
    }

    private var range: ClosedRange<Double> {
        let values = points.map(\.value)
        let lower = values.min() ?? 0
        let upper = values.max() ?? 1
        if !metric.isBody {
            return 0 ... max(1, upper * 1.1)
        }
        let margin = max(1, (upper - lower) * 0.1)
        return max(0, lower - margin) ... (upper + margin)
    }
}
