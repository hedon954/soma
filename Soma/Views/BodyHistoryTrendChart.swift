import Charts
import SwiftUI

struct BodyHistoryTrendChart: View {
    let entries: [BodyEntry]
    var now: Date = .now
    @State private var range: BodyHistoryTrendRange = .default
    @State private var selectedDate: Date?

    private var model: BodyHistoryTrendChartModel {
        BodyHistoryTrendChartModel.make(from: entries, range: range, now: now)
    }

    private var weightColor: Color {
        AppTheme.bodyAccent
    }

    private var bodyFatColor: Color {
        AppTheme.trendAccent
    }

    var body: some View {
        let chartModel = model
        return VStack(alignment: .leading, spacing: 10) {
            rangePicker
            legend
            if !chartModel.hasWeight, !chartModel.hasBodyFat {
                emptyInRange
            } else {
                unitHeaders(chartModel)
                chart(chartModel)
                selectionReadout(chartModel)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body-history-trend-section")
        .onChange(of: range) { _, _ in
            selectedDate = nil
        }
    }

    private var rangePicker: some View {
        Picker("时间区间", selection: $range) {
            ForEach(BodyHistoryTrendRange.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("body-history-trend-range")
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
                        .stroke(color, style: StrokeStyle(lineWidth: 1.25, dash: [4, 3]))
                        .frame(width: 18, height: 2)
                } else {
                    Capsule()
                        .fill(color)
                        .frame(width: 18, height: 2)
                }
                if diamond {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .rotationEffect(.degrees(45))
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(width: 22, height: 10)
            Text("\(title) \(unit)")
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("\(title)，单位\(unit)")
    }

    private func unitHeaders(_ model: BodyHistoryTrendChartModel) -> some View {
        HStack {
            Text(model.hasWeight ? "kg" : "%")
                .font(.caption2)
                .foregroundStyle(model.hasWeight ? weightColor : bodyFatColor)
            Spacer(minLength: 0)
            if model.hasWeight, model.hasBodyFat {
                Text("%")
                    .font(.caption2)
                    .foregroundStyle(bodyFatColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.hasWeight && model.hasBodyFat ? "左轴千克，右轴百分比" : (model.hasWeight ? "单位千克" : "单位百分比"))
        .accessibilityIdentifier("body-history-trend-axis-units")
    }

    private var emptyInRange: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("所选时间内暂无体重或体脂")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("可切换更长区间，或连接 Apple 健康同步；下方列表仍显示全部记录。不同时间的样本不会捏成同一次测量。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityIdentifier("body-history-trend-empty-range")
    }

    private func chart(_ model: BodyHistoryTrendChartModel) -> some View {
        let selectedWeight = selectedHighlight(in: model.weightPoints)
        let selectedFatPlot = selectedHighlight(in: model.bodyFatPlotPoints)
        return Chart {
            if model.hasWeight {
                ForEach(model.weightPoints) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("绘图值", point.value),
                        series: .value("指标", BodyHistoryTrendSeriesKey.weight.rawValue)
                    )
                    .foregroundStyle(weightColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.25))
                    .interpolationMethod(.linear)
                    .accessibilityHidden(true)

                    if model.showsPermanentPoints {
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("绘图值", point.value)
                        )
                        .foregroundStyle(weightColor)
                        .symbol(BasicChartSymbolShape.circle)
                        .symbolSize(12)
                        .accessibilityHidden(true)
                    }
                }
                if let selectedWeight {
                    PointMark(
                        x: .value("日期", selectedWeight.date),
                        y: .value("绘图值", selectedWeight.value)
                    )
                    .foregroundStyle(weightColor)
                    .symbol(BasicChartSymbolShape.circle)
                    .symbolSize(28)
                    .accessibilityHidden(true)
                }
            }

            if model.hasBodyFat {
                ForEach(model.bodyFatPlotPoints) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("绘图值", point.value),
                        series: .value("指标", BodyHistoryTrendSeriesKey.bodyFat.rawValue)
                    )
                    .foregroundStyle(bodyFatColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 3]))
                    .interpolationMethod(.linear)
                    .accessibilityHidden(true)

                    if model.showsPermanentPoints {
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("绘图值", point.value)
                        )
                        .foregroundStyle(bodyFatColor)
                        .symbol(BasicChartSymbolShape.diamond)
                        .symbolSize(14)
                        .accessibilityHidden(true)
                    }
                }
                if let selectedFatPlot {
                    PointMark(
                        x: .value("日期", selectedFatPlot.date),
                        y: .value("绘图值", selectedFatPlot.value)
                    )
                    .foregroundStyle(bodyFatColor)
                    .symbol(BasicChartSymbolShape.diamond)
                    .symbolSize(30)
                    .accessibilityHidden(true)
                }
            }

            if let selectedDate {
                RuleMark(x: .value("所选日期", selectedDate))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: model.sharedDateDomain)
        .chartYScale(domain: model.plotDomain)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: model.xAxisTickDates) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(BodyHistoryTrendChartModel.compactAxisDate(date))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartYAxis {
            if model.hasWeight {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number.formatted(.number.precision(.fractionLength(0 ... 1))))
                                .foregroundStyle(weightColor)
                        }
                    }
                }
            } else if model.hasBodyFat {
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
            if model.hasWeight, model.hasBodyFat {
                AxisMarks(position: .trailing, values: bodyFatTickPlotValues(model)) { value in
                    AxisValueLabel {
                        if let plot = value.as(Double.self) {
                            let fat = BodyHistoryDualAxisMapping.value(
                                atPlot: plot,
                                from: model.weightDomain,
                                onto: model.bodyFatDomain
                            )
                            Text(fat.formatted(.number.precision(.fractionLength(0 ... 1))))
                                .foregroundStyle(bodyFatColor)
                        }
                    }
                }
            }
        }
        .frame(height: 200)
        .accessibilityLabel(chartAccessibilityLabel(model))
        .accessibilityIdentifier("body-history-trend-chart")
    }

    private func selectedHighlight(in points: [BodyHistoryTrendPoint]) -> BodyHistoryTrendPoint? {
        guard selectedDate != nil else { return nil }
        return nearest(in: points)
    }

    private func bodyFatTickPlotValues(_ model: BodyHistoryTrendChartModel) -> [Double] {
        guard model.hasWeight, model.hasBodyFat else { return [] }
        return axisTicks(in: model.bodyFatDomain, count: 4).map {
            BodyHistoryDualAxisMapping.plot($0, from: model.bodyFatDomain, onto: model.weightDomain)
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

    private func chartAccessibilityLabel(_ model: BodyHistoryTrendChartModel) -> String {
        let rangeText = model.range.title
        switch (model.hasWeight, model.hasBodyFat) {
        case (true, true):
            return "体重与体脂率合并趋势，区间\(rangeText)，左轴千克，右轴百分比，两条独立曲线"
        case (true, false):
            return "体重趋势，区间\(rangeText)，单位千克"
        case (false, true):
            return "体脂率趋势，区间\(rangeText)，单位百分比"
        case (false, false):
            return "暂无趋势数据"
        }
    }

    private func selectionReadout(_ model: BodyHistoryTrendChartModel) -> some View {
        let weight = nearest(in: model.weightPoints)
        let fat = nearest(in: model.bodyFatPoints)
        return VStack(alignment: .leading, spacing: 4) {
            if let weight {
                Text(
                    "体重 \(weight.value.formatted(.number.precision(.fractionLength(0 ... 1)))) kg · \(weight.date.formatted(date: .abbreviated, time: .shortened))"
                )
                .foregroundStyle(weightColor)
            } else if model.hasWeight {
                Text("体重 —")
                    .foregroundStyle(.secondary)
            }
            if let fat {
                Text(
                    "体脂率 \(fat.value.formatted(.number.precision(.fractionLength(0 ... 1)))) % · \(fat.date.formatted(date: .abbreviated, time: .shortened))"
                )
                .foregroundStyle(bodyFatColor)
            } else if model.hasBodyFat {
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

    private func nearest(in points: [BodyHistoryTrendPoint]) -> BodyHistoryTrendPoint? {
        guard !points.isEmpty else { return nil }
        guard let selectedDate else { return points.last }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }
}
