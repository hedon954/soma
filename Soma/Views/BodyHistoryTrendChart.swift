import Charts
import SwiftUI

struct BodyHistoryTrendPoint: Identifiable, Equatable {
    var id: String
    var date: Date
    var value: Double
}

enum BodyHistoryTrendSeriesKey: String, CaseIterable {
    case weight = "体重"
    case bodyFat = "体脂率"
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

/// 可单测的合并趋势图数据：体重/体脂必须是独立有序序列，禁止混成一条折线。
struct BodyHistoryTrendChartModel: Equatable {
    var weightPoints: [BodyHistoryTrendPoint]
    var bodyFatPoints: [BodyHistoryTrendPoint]
    var bodyFatPlotPoints: [BodyHistoryTrendPoint]
    var weightDomain: ClosedRange<Double>
    var bodyFatDomain: ClosedRange<Double>
    var plotDomain: ClosedRange<Double>
    var sharedDateDomain: ClosedRange<Date>

    var hasWeight: Bool {
        !weightPoints.isEmpty
    }

    var hasBodyFat: Bool {
        !bodyFatPoints.isEmpty
    }

    static func make(from entries: [BodyEntry]) -> BodyHistoryTrendChartModel {
        make(
            weights: entries.compactMap { entry in
                guard let value = entry.weight, value.isFinite else { return nil }
                return (id: entry.id, date: entry.date, value: value)
            },
            bodyFats: entries.compactMap { entry in
                guard let value = entry.bodyFat, value.isFinite else { return nil }
                return (id: entry.id, date: entry.date, value: value)
            }
        )
    }

    static func make(
        weights: [(id: UUID, date: Date, value: Double)],
        bodyFats: [(id: UUID, date: Date, value: Double)]
    ) -> BodyHistoryTrendChartModel {
        let weightPoints = weights
            .filter(\.value.isFinite)
            .map {
                BodyHistoryTrendPoint(
                    id: "\(BodyHistoryTrendSeriesKey.weight.rawValue)-\($0.id.uuidString)",
                    date: $0.date,
                    value: $0.value
                )
            }
            .sorted { $0.date < $1.date }

        let bodyFatPoints = bodyFats
            .filter(\.value.isFinite)
            .map {
                BodyHistoryTrendPoint(
                    id: "\(BodyHistoryTrendSeriesKey.bodyFat.rawValue)-\($0.id.uuidString)",
                    date: $0.date,
                    value: $0.value
                )
            }
            .sorted { $0.date < $1.date }

        let weightDomain = BodyHistoryDualAxisMapping.paddedRange(
            values: weightPoints.map(\.value),
            minimumSpan: 2
        )
        let bodyFatDomain = BodyHistoryDualAxisMapping.paddedRange(
            values: bodyFatPoints.map(\.value),
            minimumSpan: 2
        )
        let hasWeight = !weightPoints.isEmpty
        let hasBodyFat = !bodyFatPoints.isEmpty
        let plotDomain: ClosedRange<Double> = {
            if hasWeight {
                return weightDomain
            }
            if hasBodyFat {
                return bodyFatDomain
            }
            return 0 ... 1
        }()

        let bodyFatPlotPoints: [BodyHistoryTrendPoint] = bodyFatPoints.map { point in
            let plotValue = hasWeight
                ? BodyHistoryDualAxisMapping.plot(point.value, from: bodyFatDomain, onto: weightDomain)
                : point.value
            return BodyHistoryTrendPoint(id: point.id, date: point.date, value: plotValue)
        }

        let dates = weightPoints.map(\.date) + bodyFatPoints.map(\.date)
        let sharedDateDomain: ClosedRange<Date> = {
            guard let first = dates.min(), let last = dates.max() else {
                let now = Date()
                return now.addingTimeInterval(-86400) ... now
            }
            if first == last {
                return first.addingTimeInterval(-86400) ... last.addingTimeInterval(86400)
            }
            return first ... last
        }()

        return BodyHistoryTrendChartModel(
            weightPoints: weightPoints,
            bodyFatPoints: bodyFatPoints,
            bodyFatPlotPoints: bodyFatPlotPoints,
            weightDomain: weightDomain,
            bodyFatDomain: bodyFatDomain,
            plotDomain: plotDomain,
            sharedDateDomain: sharedDateDomain
        )
    }

    /// 若错误地把两系按时间混成一条折线，会在相邻异系点之间产生跨指标连线；测试用此检测。
    var illicitCrossSeriesAdjacencies: Int {
        let mixed = (weightPoints.map { ($0.date, BodyHistoryTrendSeriesKey.weight, $0.value) }
            + bodyFatPlotPoints.map { ($0.date, BodyHistoryTrendSeriesKey.bodyFat, $0.value) })
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 {
                    return lhs.0 < rhs.0
                }
                return lhs.1.rawValue < rhs.1.rawValue
            }
        guard mixed.count >= 2 else { return 0 }
        var count = 0
        for index in 1 ..< mixed.count where mixed[index].1 != mixed[index - 1].1 {
            count += 1
        }
        return count
    }

    var xAxisTickDates: [Date] {
        let start = sharedDateDomain.lowerBound
        let end = sharedDateDomain.upperBound
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return [start] }
        // 3 个短标签，避免中文「9月1日」在窄图上被截成「1…」。
        return [
            start,
            start.addingTimeInterval(span / 2),
            end
        ]
    }

    static func compactAxisDate(_ date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)/\(day)"
    }
}

struct BodyHistoryTrendChart: View {
    let entries: [BodyEntry]
    @State private var selectedDate: Date?

    private var model: BodyHistoryTrendChartModel {
        BodyHistoryTrendChartModel.make(from: entries)
    }

    private var weightColor: Color {
        AppTheme.bodyAccent
    }

    private var bodyFatColor: Color {
        AppTheme.trendAccent
    }

    var body: some View {
        let chartModel = model
        return VStack(alignment: .leading, spacing: 12) {
            legend
            if !chartModel.hasWeight, !chartModel.hasBodyFat {
                emptyBoth
            } else {
                chart(chartModel)
                selectionReadout(chartModel)
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
                        .stroke(color, style: StrokeStyle(lineWidth: 3, dash: [5, 3]))
                        .frame(width: 20, height: 3)
                } else {
                    Capsule()
                        .fill(color)
                        .frame(width: 20, height: 3)
                }
                if diamond {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(45))
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                }
            }
            .frame(width: 24, height: 12)
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
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.linear)
                    .accessibilityHidden(true)

                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("绘图值", point.value)
                    )
                    .foregroundStyle(weightColor)
                    .symbol(BasicChartSymbolShape.circle)
                    .symbolSize(44)
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
                    .lineStyle(StrokeStyle(lineWidth: 3, dash: [5, 3]))
                    .interpolationMethod(.linear)
                    .accessibilityHidden(true)

                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("绘图值", point.value)
                    )
                    .foregroundStyle(bodyFatColor)
                    .symbol(BasicChartSymbolShape.diamond)
                    .symbolSize(64)
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
        .chartYAxisLabel(position: .leading, alignment: .center) {
            Text(model.hasWeight ? "kg" : "%")
                .font(.caption2)
                .foregroundStyle(model.hasWeight ? weightColor : bodyFatColor)
        }
        .chartYAxisLabel(position: .trailing, alignment: .center) {
            if model.hasWeight, model.hasBodyFat {
                Text("%")
                    .font(.caption2)
                    .foregroundStyle(bodyFatColor)
            }
        }
        .frame(height: 200)
        .accessibilityLabel(chartAccessibilityLabel(model))
        .accessibilityIdentifier("body-history-trend-chart")
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
        switch (model.hasWeight, model.hasBodyFat) {
        case (true, true):
            "体重与体脂率合并趋势，左轴千克，右轴百分比，两条独立曲线"
        case (true, false):
            "体重趋势，单位千克"
        case (false, true):
            "体脂率趋势，单位百分比"
        case (false, false):
            "暂无趋势数据"
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
