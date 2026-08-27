import Charts
import SwiftUI

struct MonthlyProgressTrendCard: View {
    let series: [ProgressTrendSeries]
    @State private var selectedMetric = ProgressTrendMetric.trainingVolume
    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetricHeading(title: "近 30 天趋势", role: selectedMetric.metricRole)
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("趋势指标", selection: $selectedMetric) {
                        ForEach(ProgressTrendMetric.allCases) { metric in
                            Text(metric.shortTitle).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedMetric.title)
                                .font(.subheadline.weight(.medium))
                            Text("最近 30 天")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ProgressSourceButton(source: .trend(selectedSeries))
                    }

                    if selectedSeries.points.isEmpty {
                        ContentUnavailableView(
                            "暂无\(selectedMetric.shortTitle)数据",
                            systemImage: selectedMetric.systemImage,
                            description: Text("记录后会在这里形成 30 天曲线。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        chart
                        selectedPointDetail
                    }
                }
            }
        }
        .onAppear {
            chooseInitialMetricIfNeeded()
            selectLatestPoint()
        }
        .onChange(of: selectedMetric) {
            selectLatestPoint()
        }
    }

    private var chart: some View {
        Chart(selectedSeries.points) { point in
            LineMark(
                x: .value("日期", point.date),
                y: .value(selectedMetric.title, point.value)
            )
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round))
            .foregroundStyle(selectedMetric.accent)

            PointMark(
                x: .value("日期", point.date),
                y: .value(selectedMetric.title, point.value)
            )
            .symbolSize(selectedPoint?.date == point.date ? 70 : 34)
            .foregroundStyle(selectedMetric.accent)

            if selectedPoint?.date == point.date {
                RuleMark(x: .value("所选日期", point.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: monthDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                    .foregroundStyle(AppTheme.separator)
                AxisTick()
                    .foregroundStyle(AppTheme.separator)
                AxisValueLabel(format: .dateTime.month().day())
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                    .foregroundStyle(AppTheme.separator)
                AxisTick()
                    .foregroundStyle(AppTheme.separator)
                AxisValueLabel()
                    .foregroundStyle(.secondary)
            }
        }
        .chartXSelection(value: $selectedDate)
        .frame(height: 200)
        .accessibilityLabel("\(selectedMetric.title)最近 30 天曲线")
        .accessibilityHint("轻点或拖动数据点查看当日明细")
    }

    private var selectedPointDetail: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(selectedPoint?.date.formatted(.dateTime.month().day()) ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(selectedPoint.map(valueText) ?? "—")
                .font(.subheadline.weight(.medium).monospacedDigit())
            Spacer()
            Text(selectedPoint.map(detailText) ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 4)
        .frame(minHeight: AppTheme.minimumTapTarget)
        .accessibilityElement(children: .combine)
    }

    private var selectedSeries: ProgressTrendSeries {
        series.first { $0.metric == selectedMetric }
            ?? ProgressTrendSeries(metric: selectedMetric, points: [])
    }

    private var selectedPoint: ProgressTrendPoint? {
        guard let selectedDate else { return selectedSeries.points.last }
        return selectedSeries.points.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var monthDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let end = Date.now
        let start = calendar.date(
            byAdding: .day,
            value: -29,
            to: calendar.startOfDay(for: end)
        ) ?? end
        return start ... end
    }

    private var yDomain: ClosedRange<Double> {
        guard let minimum = selectedSeries.points.map(\.value).min(),
              let maximum = selectedSeries.points.map(\.value).max()
        else {
            return 0 ... 1
        }
        let span = maximum - minimum
        let padding = max(span * 0.12, selectedMetric.minimumYPadding)
        return max(0, minimum - padding) ... (maximum + padding)
    }

    private func chooseInitialMetricIfNeeded() {
        guard selectedSeries.points.isEmpty,
              let firstAvailable = series.first(where: { !$0.points.isEmpty })
        else {
            return
        }
        selectedMetric = firstAvailable.metric
    }

    private func selectLatestPoint() {
        selectedDate = selectedSeries.points.last?.date
    }

    private func valueText(_ point: ProgressTrendPoint) -> String {
        switch selectedMetric {
        case .trainingVolume:
            "\(point.value.formatted(.number.precision(.fractionLength(0)))) kg"
        case .calorieIntake:
            "\(point.isPartial ? "≥ " : "")\(Int(point.value.rounded())) kcal"
        case .weight:
            "\(point.value.formatted(.number.precision(.fractionLength(1)))) kg"
        }
    }

    private func detailText(_ point: ProgressTrendPoint) -> String {
        switch selectedMetric {
        case .trainingVolume:
            "当天可计算容量"
        case .calorieIntake:
            "\(point.itemCount) 条饮食\(point.isPartial ? " · 有缺失" : "")"
        case .weight:
            point.itemCount > 1 ? "同日最后一次" : "身体记录"
        }
    }
}

private extension ProgressTrendMetric {
    var shortTitle: String {
        switch self {
        case .trainingVolume: "训练"
        case .calorieIntake: "摄入"
        case .weight: "体重"
        }
    }

    var systemImage: String {
        switch self {
        case .trainingVolume: "scalemass"
        case .calorieIntake: "fork.knife"
        case .weight: "figure"
        }
    }

    var metricRole: AppMetricRole {
        switch self {
        case .trainingVolume: .trainingLoad
        case .calorieIntake: .recovery
        case .weight: .body
        }
    }

    var minimumYPadding: Double {
        switch self {
        case .trainingVolume: 10
        case .calorieIntake: 50
        case .weight: 0.5
        }
    }
}
