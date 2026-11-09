import Charts
import SwiftUI

struct BodyHistoryTrendPoint: Identifiable {
    var id: UUID
    var date: Date
    var value: Double
}

/// 双轴绘制：把次轴真实值线性映射到主轴绘图域；标签用逆映射还原，避免混用未标注刻度。
enum BodyHistoryDualAxisMapping {
    static func plot(
        _ value: Double,
        from source: ClosedRange<Double>,
        onto target: ClosedRange<Double>
    ) -> Double {
        let sourceSpan = source.upperBound - source.lowerBound
        let targetSpan = target.upperBound - target.lowerBound
        guard sourceSpan > 0, targetSpan > 0, value.isFinite else {
            return target.lowerBound
        }
        let fraction = (value - source.lowerBound) / sourceSpan
        return target.lowerBound + fraction * targetSpan
    }

    static func value(
        atPlot plot: Double,
        from target: ClosedRange<Double>,
        onto source: ClosedRange<Double>
    ) -> Double {
        let sourceSpan = source.upperBound - source.lowerBound
        let targetSpan = target.upperBound - target.lowerBound
        guard sourceSpan > 0, targetSpan > 0, plot.isFinite else {
            return source.lowerBound
        }
        let fraction = (plot - target.lowerBound) / targetSpan
        return source.lowerBound + fraction * sourceSpan
    }

    static func paddedRange(values: [Double], minimumSpan: Double) -> ClosedRange<Double> {
        let finite = values.filter(\.isFinite)
        guard let lower = finite.min(), let upper = finite.max() else {
            return 0 ... max(minimumSpan, 1)
        }
        if lower == upper {
            let pad = max(minimumSpan / 2, abs(lower) * 0.05, 0.5)
            return max(0, lower - pad) ... (upper + pad)
        }
        let margin = max(minimumSpan * 0.1, (upper - lower) * 0.1)
        return max(0, lower - margin) ... (upper + margin)
    }
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

    private var hasWeight: Bool {
        !weightPoints.isEmpty
    }

    private var hasBodyFat: Bool {
        !bodyFatPoints.isEmpty
    }

    private var sharedDomain: ClosedRange<Date> {
        let dates = weightPoints.map(\.date) + bodyFatPoints.map(\.date)
        guard let first = dates.min(), let last = dates.max() else {
            let now = Date()
            return now.addingTimeInterval(-86400) ... now
        }
        if first == last {
            return first.addingTimeInterval(-86400) ... last.addingTimeInterval(86400)
        }
        return first ... last
    }

    private var weightDomain: ClosedRange<Double> {
        BodyHistoryDualAxisMapping.paddedRange(values: weightPoints.map(\.value), minimumSpan: 2)
    }

    private var bodyFatDomain: ClosedRange<Double> {
        BodyHistoryDualAxisMapping.paddedRange(values: bodyFatPoints.map(\.value), minimumSpan: 2)
    }

    /// 主绘图域：有体重时用体重轴；仅体脂时用体脂轴。
    private var plotDomain: ClosedRange<Double> {
        if hasWeight {
            return weightDomain
        }
        if hasBodyFat {
            return bodyFatDomain
        }
        return 0 ... 1
    }

    /// 体脂点在主绘图域中的 Y（有体重时做线性映射；仅体脂时用真实百分点）。
    private var bodyFatPlotPoints: [BodyHistoryTrendPoint] {
        bodyFatPoints.map { point in
            let plotValue = hasWeight
                ? BodyHistoryDualAxisMapping.plot(point.value, from: bodyFatDomain, onto: weightDomain)
                : point.value
            return BodyHistoryTrendPoint(id: point.id, date: point.date, value: plotValue)
        }
    }

    private var weightColor: Color {
        AppTheme.bodyAccent
    }

    private var bodyFatColor: Color {
        AppTheme.trendAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            legend
            if !hasWeight, !hasBodyFat {
                emptyBoth
            } else {
                chart
                selectionReadout
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body-history-trend-section")
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: weightColor, title: "体重", unit: "kg", dashed: false, diamond: false)
            legendItem(color: bodyFatColor, title: "体脂率", unit: "%", dashed: true, diamond: true)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("图例：体重千克，身体蓝实线；体脂率百分比，趋势紫虚线")
        .accessibilityIdentifier("body-history-trend-legend")
    }

    private func legendItem(
        color: Color,
        title: String,
        unit: String,
        dashed: Bool,
        diamond: Bool
    ) -> some View {
        HStack(spacing: 6) {
            ZStack {
                if dashed {
                    Capsule()
                        .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .frame(width: 18, height: 2)
                } else {
                    Capsule()
                        .fill(color)
                        .frame(width: 18, height: 3)
                }
                if diamond {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .rotationEffect(.degrees(45))
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                }
            }
            .frame(width: 22, height: 12)
            Text("\(title) \(unit)")
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("\(title)，单位\(unit)")
    }

    private var emptyBoth: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("暂无体重或体脂记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("连接 Apple 健康后会自动同步体重与体脂；也可发给教练记录。不同时间的样本不会捏成同一次测量。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var chart: some View {
        Chart {
            if hasWeight {
                ForEach(weightPoints) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("体重", point.value)
                    )
                    .foregroundStyle(weightColor)
                    .interpolationMethod(.linear)
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("体重", point.value)
                    )
                    .foregroundStyle(weightColor)
                    .symbol(BasicChartSymbolShape.circle)
                    .symbolSize(40)
                }
            }

            if hasBodyFat {
                ForEach(bodyFatPlotPoints) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("体脂绘图", point.value)
                    )
                    .foregroundStyle(bodyFatColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .interpolationMethod(.linear)
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("体脂绘图", point.value)
                    )
                    .foregroundStyle(bodyFatColor)
                    .symbol(BasicChartSymbolShape.diamond)
                    .symbolSize(48)
                }
            }

            if let selectedDate {
                RuleMark(x: .value("所选日期", selectedDate))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: sharedDomain)
        .chartYScale(domain: plotDomain)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            if hasWeight {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number.formatted(.number.precision(.fractionLength(0 ... 1))))
                                .foregroundStyle(weightColor)
                        }
                    }
                }
            } else if hasBodyFat {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number.formatted(.number.precision(.fractionLength(0 ... 1))))
                                .foregroundStyle(bodyFatColor)
                        }
                    }
                }
            }
            if hasWeight, hasBodyFat {
                AxisMarks(position: .trailing, values: bodyFatTickPlotValues) { value in
                    AxisValueLabel {
                        if let plot = value.as(Double.self) {
                            let fat = BodyHistoryDualAxisMapping.value(
                                atPlot: plot,
                                from: weightDomain,
                                onto: bodyFatDomain
                            )
                            Text(fat.formatted(.number.precision(.fractionLength(0 ... 1))))
                                .foregroundStyle(bodyFatColor)
                        }
                    }
                }
            }
        }
        .chartYAxisLabel(position: .leading, alignment: .center) {
            Text(hasWeight ? "kg" : "%")
                .font(.caption2)
                .foregroundStyle(hasWeight ? weightColor : bodyFatColor)
        }
        .chartYAxisLabel(position: .trailing, alignment: .center) {
            if hasWeight, hasBodyFat {
                Text("%")
                    .font(.caption2)
                    .foregroundStyle(bodyFatColor)
            }
        }
        .frame(height: 200)
        .accessibilityLabel(chartAccessibilityLabel)
        .accessibilityIdentifier("body-history-trend-chart")
    }

    private var bodyFatTickPlotValues: [Double] {
        guard hasWeight, hasBodyFat else { return [] }
        return axisTicks(in: bodyFatDomain, count: 4).map {
            BodyHistoryDualAxisMapping.plot($0, from: bodyFatDomain, onto: weightDomain)
        }
    }

    private func axisTicks(in domain: ClosedRange<Double>, count: Int) -> [Double] {
        guard count > 1 else { return [domain.lowerBound] }
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return [domain.lowerBound] }
        return (0 ..< count).map { index in
            domain.lowerBound + span * Double(index) / Double(count - 1)
        }
    }

    private var chartAccessibilityLabel: String {
        switch (hasWeight, hasBodyFat) {
        case (true, true):
            "体重与体脂率合并趋势，左轴千克，右轴百分比"
        case (true, false):
            "体重趋势，单位千克"
        case (false, true):
            "体脂率趋势，单位百分比"
        case (false, false):
            "暂无趋势数据"
        }
    }

    private var selectionReadout: some View {
        let weight = nearest(in: weightPoints)
        let fat = nearest(in: bodyFatPoints)
        return VStack(alignment: .leading, spacing: 4) {
            if let weight {
                Text(
                    "体重 \(weight.value.formatted(.number.precision(.fractionLength(0 ... 1)))) kg · \(weight.date.formatted(date: .abbreviated, time: .shortened))"
                )
                .foregroundStyle(weightColor)
            } else if hasWeight {
                Text("体重 —")
                    .foregroundStyle(.secondary)
            }
            if let fat {
                Text(
                    "体脂率 \(fat.value.formatted(.number.precision(.fractionLength(0 ... 1)))) % · \(fat.date.formatted(date: .abbreviated, time: .shortened))"
                )
                .foregroundStyle(bodyFatColor)
            } else if hasBodyFat {
                Text("体脂率 —")
                    .foregroundStyle(.secondary)
            }
            if let weight, let fat, weight.date != fat.date {
                Text("两条曲线取自不同记录时间，不是同一次测量。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44, alignment: .topLeading)
        .accessibilityIdentifier("body-history-trend-selection")
    }

    private func points(for keyPath: KeyPath<BodyEntry, Double?>) -> [BodyHistoryTrendPoint] {
        entries.compactMap { entry in
            guard let value = entry[keyPath: keyPath], value.isFinite else { return nil }
            return BodyHistoryTrendPoint(id: entry.id, date: entry.date, value: value)
        }
        .sorted { $0.date < $1.date }
    }

    private func nearest(in points: [BodyHistoryTrendPoint]) -> BodyHistoryTrendPoint? {
        guard !points.isEmpty else { return nil }
        guard let selectedDate else { return points.last }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }
}
