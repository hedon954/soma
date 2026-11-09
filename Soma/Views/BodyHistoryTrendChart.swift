import Charts
import SwiftUI

struct BodyHistoryTrendChart: View {
    let entries: [BodyEntry]
    var now: Date = .now
    @State private var range: BodyHistoryTrendRange = .default
    @State private var selection: BodyHistoryTrendSelection?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body-history-trend-section")
        .onChange(of: range) { _, newRange in
            let updated = BodyHistoryTrendChartModel.make(from: entries, range: newRange, now: now)
            selection = BodyHistoryTrendSelectionResolver.validated(selection, in: updated)
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
        let content = Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    legendItem(color: weightColor, title: "体重", unit: "kg", dashed: false, diamond: false)
                    legendItem(color: bodyFatColor, title: "体脂率", unit: "%", dashed: true, diamond: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 16) {
                    legendItem(color: weightColor, title: "体重", unit: "kg", dashed: false, diamond: false)
                    legendItem(color: bodyFatColor, title: "体脂率", unit: "%", dashed: true, diamond: true)
                    Spacer(minLength: 0)
                }
            }
        }
        return content
            .font(.caption)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("图例：体重千克，身体蓝实线；体脂率百分比，趋势紫虚线。点选图上样本可查看该次数值。")
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
            Text("可切换更长区间，或连接 Apple 健康同步；下方列表仍显示全部记录。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityIdentifier("body-history-trend-empty-range")
    }

    private func chart(_ model: BodyHistoryTrendChartModel) -> some View {
        Chart {
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
            }

            if let selection {
                PointMark(
                    x: .value("日期", selection.date),
                    y: .value("绘图值", selection.plotValue)
                )
                .foregroundStyle(selection.series == .weight ? weightColor : bodyFatColor)
                .symbol(
                    selection.series == .weight
                        ? BasicChartSymbolShape.circle
                        : BasicChartSymbolShape.diamond
                )
                .symbolSize(44)
                .annotation(position: annotationPosition(for: selection, in: model), spacing: 6) {
                    selectionCallout(selection)
                }
                .accessibilityLabel(selection.accessibilityLabel)
                .accessibilityIdentifier("body-history-trend-selection-callout")
            }
        }
        .chartXScale(domain: model.sharedDateDomain)
        .chartYScale(domain: model.plotDomain)
        .chartXAxis {
            AxisMarks(values: model.xAxisTickDates) { value in
                AxisGridLine().foregroundStyle(AppTheme.separator)
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
                    AxisGridLine().foregroundStyle(AppTheme.separator)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number.formatted(.number.precision(.fractionLength(0 ... 1))))
                                .foregroundStyle(weightColor)
                        }
                    }
                }
            } else if model.hasBodyFat {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppTheme.separator)
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
        .frame(height: chartHeight)
        // 坐标/网格随字号适度放大，但不跟到 AccessibilityXXXL，避免挤爆绘图区。
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                select(at: value.location, proxy: proxy, geo: geo, model: model)
                            }
                    )
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(chartAccessibilityLabel(model))
        .accessibilityHint("点选图上的样本可查看该次数值与时间")
        .accessibilityIdentifier("body-history-trend-chart")
        .accessibilityAction(named: Text("朗读最近体重样本")) {
            if let last = model.weightPoints.last {
                selection = BodyHistoryTrendSelection(
                    id: last.id,
                    series: .weight,
                    date: last.date,
                    displayValue: last.value,
                    plotValue: last.value
                )
            }
        }
        .accessibilityAction(named: Text("朗读最近体脂样本")) {
            if let last = model.bodyFatPoints.last,
               let plot = model.bodyFatPlotPoints.last
            {
                selection = BodyHistoryTrendSelection(
                    id: last.id,
                    series: .bodyFat,
                    date: last.date,
                    displayValue: last.value,
                    plotValue: plot.value
                )
            }
        }
    }

    private func selectionCallout(_ selection: BodyHistoryTrendSelection) -> some View {
        let color = selection.series == .weight ? weightColor : bodyFatColor
        let value = selection.displayValue.formatted(.number.precision(.fractionLength(0 ... 1)))
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(selection.title) \(value) \(selection.unit)")
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            Text(selection.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 240 : 200, alignment: .leading)
        .background(
            AppTheme.insetBackground,
            in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 0.5)
        )
        .accessibilityIdentifier("body-history-trend-selection-callout")
    }

    private func annotationPosition(
        for selection: BodyHistoryTrendSelection,
        in model: BodyHistoryTrendChartModel
    ) -> AnnotationPosition {
        let span = model.sharedDateDomain.upperBound.timeIntervalSince(model.sharedDateDomain.lowerBound)
        guard span > 0 else { return .top }
        let fraction = selection.date.timeIntervalSince(model.sharedDateDomain.lowerBound) / span
        if fraction > 0.72 {
            return .leading
        }
        if fraction < 0.28 {
            return .trailing
        }
        let plotSpan = model.plotDomain.upperBound - model.plotDomain.lowerBound
        if plotSpan > 0 {
            let yFraction = (selection.plotValue - model.plotDomain.lowerBound) / plotSpan
            if yFraction > 0.78 {
                return .bottom
            }
        }
        return .top
    }

    private func select(
        at location: CGPoint,
        proxy: ChartProxy,
        geo: GeometryProxy,
        model: BodyHistoryTrendChartModel
    ) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geo[plotFrame]
        let localX = location.x - frame.origin.x
        let localY = location.y - frame.origin.y
        guard localX >= 0, localY >= 0, localX <= frame.width, localY <= frame.height,
              let date: Date = proxy.value(atX: localX),
              let plotY: Double = proxy.value(atY: localY)
        else {
            selection = nil
            return
        }
        selection = BodyHistoryTrendSelectionResolver.nearest(date: date, plotY: plotY, in: model)
    }

    private var chartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 300 : 220
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
}
