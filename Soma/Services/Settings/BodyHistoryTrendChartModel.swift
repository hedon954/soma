import Foundation

struct BodyHistoryTrendPoint: Identifiable, Equatable {
    var id: String
    var date: Date
    var value: Double
}

enum BodyHistoryTrendSeriesKey: String, CaseIterable {
    case weight = "体重"
    case bodyFat = "体脂率"
}

/// 趋势图时间区间：相对「现在」的日历半开窗；默认一个月。
enum BodyHistoryTrendRange: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case threeMonths
    case year

    static let `default` = Self.month

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .week: "一周"
        case .month: "一个月"
        case .threeMonths: "三个月"
        case .year: "一年"
        }
    }

    struct Window: Equatable, Sendable {
        var start: Date
        /// 半开上界：不含。
        var end: Date

        func contains(_ date: Date) -> Bool {
            date >= start && date < end
        }
    }

    func window(now: Date, calendar: Calendar = .current) -> Window {
        let dayStart = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let start: Date = switch self {
        case .week:
            calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        case .month:
            calendar.date(byAdding: .month, value: -1, to: dayStart) ?? dayStart
        case .threeMonths:
            calendar.date(byAdding: .month, value: -3, to: dayStart) ?? dayStart
        case .year:
            calendar.date(byAdding: .year, value: -1, to: dayStart) ?? dayStart
        }
        return Window(start: start, end: end)
    }
}

/// 按自然日各取最后一次有效样本（图表用）；同时间用 id 字符串稳定决胜。
enum BodyHistoryTrendDayReduction {
    static func lastPerCalendarDay(
        _ samples: [(id: UUID, date: Date, value: Double)],
        calendar: Calendar
    ) -> [(id: UUID, date: Date, value: Double)] {
        var latestByDay: [Date: (id: UUID, date: Date, value: Double)] = [:]
        for sample in samples where sample.value.isFinite {
            let day = calendar.startOfDay(for: sample.date)
            if let existing = latestByDay[day] {
                if isLater(sample, than: existing) {
                    latestByDay[day] = sample
                }
            } else {
                latestByDay[day] = sample
            }
        }
        return latestByDay.values.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func isLater(
        _ sample: (id: UUID, date: Date, value: Double),
        than existing: (id: UUID, date: Date, value: Double)
    ) -> Bool {
        if sample.date != existing.date {
            return sample.date > existing.date
        }
        return sample.id.uuidString > existing.id.uuidString
    }
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
    var range: BodyHistoryTrendRange
    var showsPermanentPoints: Bool

    var hasWeight: Bool {
        !weightPoints.isEmpty
    }

    var hasBodyFat: Bool {
        !bodyFatPoints.isEmpty
    }

    static let permanentPointLimit = 16

    static func make(
        from entries: [BodyEntry],
        range: BodyHistoryTrendRange = .default,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> BodyHistoryTrendChartModel {
        make(
            weights: entries.compactMap { entry in
                guard let value = entry.weight, value.isFinite else { return nil }
                return (id: entry.id, date: entry.date, value: value)
            },
            bodyFats: entries.compactMap { entry in
                guard let value = entry.bodyFat, value.isFinite else { return nil }
                return (id: entry.id, date: entry.date, value: value)
            },
            range: range,
            now: now,
            calendar: calendar
        )
    }

    static func make(
        weights: [(id: UUID, date: Date, value: Double)],
        bodyFats: [(id: UUID, date: Date, value: Double)],
        range: BodyHistoryTrendRange = .default,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> BodyHistoryTrendChartModel {
        let window = range.window(now: now, calendar: calendar)
        let reducedWeights = BodyHistoryTrendDayReduction.lastPerCalendarDay(
            weights.filter { $0.value.isFinite && window.contains($0.date) },
            calendar: calendar
        )
        let reducedBodyFats = BodyHistoryTrendDayReduction.lastPerCalendarDay(
            bodyFats.filter { $0.value.isFinite && window.contains($0.date) },
            calendar: calendar
        )
        let weightPoints = reducedWeights.map {
            BodyHistoryTrendPoint(
                id: "\(BodyHistoryTrendSeriesKey.weight.rawValue)-\($0.id.uuidString)",
                date: $0.date,
                value: $0.value
            )
        }
        let bodyFatPoints = reducedBodyFats.map {
            BodyHistoryTrendPoint(
                id: "\(BodyHistoryTrendSeriesKey.bodyFat.rawValue)-\($0.id.uuidString)",
                date: $0.date,
                value: $0.value
            )
        }

        let weightDomain = BodyHistoryDualAxisMapping.paddedRange(
            values: weightPoints.map(\.value),
            minimumSpan: 2
        )
        let bodyFatDomain = BodyHistoryDualAxisMapping.paddedRange(
            values: bodyFatPoints.map(\.value),
            minimumSpan: 2
        )
        let hasWeight = !weightPoints.isEmpty
        let plotDomain: ClosedRange<Double> = {
            if hasWeight {
                return weightDomain
            }
            if !bodyFatPoints.isEmpty {
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

        // 共享所选时间域，不以样本 min/max 收缩，也不用最新记录日冒充今天。
        let domainEnd = window.end.addingTimeInterval(-1)
        let sharedDateDomain = window.start ... max(window.start, domainEnd)
        let showsPermanentPoints = max(weightPoints.count, bodyFatPoints.count) <= permanentPointLimit

        return BodyHistoryTrendChartModel(
            weightPoints: weightPoints,
            bodyFatPoints: bodyFatPoints,
            bodyFatPlotPoints: bodyFatPlotPoints,
            weightDomain: weightDomain,
            bodyFatDomain: bodyFatDomain,
            plotDomain: plotDomain,
            sharedDateDomain: sharedDateDomain,
            range: range,
            showsPermanentPoints: showsPermanentPoints
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

/// 图内点选的单次样本（永不把不同时间的体重/体脂拼成一次）。
struct BodyHistoryTrendSelection: Equatable, Sendable {
    var id: String
    var series: BodyHistoryTrendSeriesKey
    var date: Date
    /// 真实展示值：kg 或百分点。
    var displayValue: Double
    /// 主绘图域中的 Y，用于命中与标注定位。
    var plotValue: Double

    var unit: String {
        switch series {
        case .weight: "kg"
        case .bodyFat: "%"
        }
    }

    var title: String {
        series.rawValue
    }

    var annotationText: String {
        let value = displayValue.formatted(.number.precision(.fractionLength(0 ... 1)))
        let time = date.formatted(date: .abbreviated, time: .shortened)
        return "\(title) \(value) \(unit)\n\(time)"
    }

    var accessibilityLabel: String {
        let value = displayValue.formatted(.number.precision(.fractionLength(0 ... 1)))
        let time = date.formatted(date: .abbreviated, time: .shortened)
        return "\(title) \(value) \(unit)，\(time)"
    }
}

enum BodyHistoryTrendSelectionResolver {
    /// 归一化平面上的最大命中半径（约等于舒适触达）。
    static let maxNormalizedDistance = 0.12

    static func selectablePoints(from model: BodyHistoryTrendChartModel) -> [BodyHistoryTrendSelection] {
        let weights = model.weightPoints.map {
            BodyHistoryTrendSelection(
                id: $0.id,
                series: .weight,
                date: $0.date,
                displayValue: $0.value,
                plotValue: $0.value
            )
        }
        let fats = zip(model.bodyFatPoints, model.bodyFatPlotPoints).map { display, plot in
            BodyHistoryTrendSelection(
                id: display.id,
                series: .bodyFat,
                date: display.date,
                displayValue: display.value,
                plotValue: plot.value
            )
        }
        return weights + fats
    }

    /// 在日期域 × 绘图域的归一化平面上找最近单样本；超出阈值则无选中。
    static func nearest(
        date: Date,
        plotY: Double,
        in model: BodyHistoryTrendChartModel,
        maxNormalizedDistance: Double = maxNormalizedDistance
    ) -> BodyHistoryTrendSelection? {
        let points = selectablePoints(from: model)
        guard !points.isEmpty else { return nil }
        let dateSpan = max(model.sharedDateDomain.upperBound.timeIntervalSince(model.sharedDateDomain.lowerBound), 1)
        let plotSpan = max(model.plotDomain.upperBound - model.plotDomain.lowerBound, 0.0001)
        var best: (BodyHistoryTrendSelection, Double)?
        for point in points {
            let dx = point.date.timeIntervalSince(date) / dateSpan
            let dy = (point.plotValue - plotY) / plotSpan
            let distance = (dx * dx + dy * dy).squareRoot()
            if let current = best {
                if distance < current.1 {
                    best = (point, distance)
                }
            } else {
                best = (point, distance)
            }
        }
        guard let best, best.1 <= maxNormalizedDistance else { return nil }
        return best.0
    }

    /// 区间切换后：若选中样本仍落在当前模型点集中则保留，否则清空。
    static func validated(
        _ selection: BodyHistoryTrendSelection?,
        in model: BodyHistoryTrendChartModel
    ) -> BodyHistoryTrendSelection? {
        guard let selection else { return nil }
        return selectablePoints(from: model).first { $0.id == selection.id }
    }
}
