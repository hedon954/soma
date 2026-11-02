import Foundation

struct EnergyCalibrationDay: Codable, Equatable, Sendable {
    let date: Date
    let intake: Double?
    let uncalibratedTotal: Double?
    let foodComplete: Bool
    let activityComplete: Bool
    /// Raw observations; same-day readings are reduced to a median, never counted as separate days.
    let weights: [Double]
    let fluidChangeConcern: Bool
    var calculation: EnergyDayCalculation?
    var sourceMealIDs: [UUID]?
}

struct EnergyCalibrationReview: Codable, Equatable, Sendable {
    let date: Date
    let windowStart: Date
    let windowEnd: Date
    let inputFingerprint: String
    let previousCorrection: Double
    let nextCorrection: Double
    let meanIntake: Double?
    let meanModel: Double?
    let slope: Double?
    let minimumCandidate: Double?
    let maximumCandidate: Double?
    let weightDayCount: Int
    let direction: Int
    let evidenceEligible: Bool
    let reason: String
    var restoredFromKey: String?
    var inputDays: [EnergyCalibrationDay]?
    var previousReviewFingerprint: String?
    var algorithmVersion: String? = "soma-calibration-1"
    var delta: Double {
        nextCorrection - previousCorrection
    }
}

enum EnergyCalibration {
    /// Engineering control parameters, not clinical thresholds or confidence limits.
    static let densityRange = 1800.0 ... 9500.0

    static func evaluate(
        days: [EnergyCalibrationDay], on date: Date, correction: Double, resting: Double,
        fingerprint: String, previous: EnergyCalibrationReview?, lastApplied: EnergyCalibrationReview?,
        calendar: Calendar = .current
    ) -> EnergyCalibrationReview {
        let end = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -28, to: end) ?? end
        let window = days.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
        let validWeights = window.map { day in day.weights.filter { $0.isFinite && $0 > 0 } }
        let weightCount = validWeights.count { !$0.isEmpty }
        func review(
            _ reason: String, next: Double? = nil, intake: Double? = nil, model: Double? = nil,
            slope: Double? = nil, low: Double? = nil, high: Double? = nil,
            direction: Int = 0, eligible: Bool = false
        ) -> EnergyCalibrationReview {
            .init(date: end, windowStart: start, windowEnd: end, inputFingerprint: fingerprint,
                  previousCorrection: correction, nextCorrection: next ?? correction,
                  meanIntake: intake, meanModel: model, slope: slope, minimumCandidate: low, maximumCandidate: high,
                  weightDayCount: weightCount, direction: direction, evidenceEligible: eligible, reason: reason,
                  inputDays: window, previousReviewFingerprint: previous?.inputFingerprint)
        }
        guard correction.isFinite, resting.isFinite, resting > 0 else { return review("静息或既有修正无效") }
        guard !fingerprint.isEmpty else { return review("缺少可复算的输入指纹") }
        let dates = Set(window.map { calendar.startOfDay(for: $0.date) })
        guard window.count == 28, dates.count == 28 else { return review("需要连续 28 个结束日的记录") }
        guard window.allSatisfy({ $0.foodComplete && valid($0.intake) }) else { return review("观察窗口有饮食未确认完整或热量缺项") }
        guard window.allSatisfy({ $0.activityComplete && valid($0.uncalibratedTotal) && ($0.uncalibratedTotal ?? 0) > 0 }) else {
            return review("步行覆盖、训练记录或消耗估算尚不完整")
        }
        guard !window.contains(where: \.fluidChangeConcern) else { return review("有体液变化疑问，暂停校准") }
        guard weightCount >= 12 else { return review("需要至少 12 个不同日期的体重") }
        for week in 0 ..< 4 where validWeights[(week * 7) ..< (week * 7 + 7)].count(where: { !$0.isEmpty }) < 3 {
            return review("每周需要至少三日体重记录")
        }
        let points = window.indices.compactMap { index -> (Date, Double)? in
            median(validWeights[index]).map { (window[index].date, $0) }
        }
        guard let slope = trend(points, calendar: calendar) else { return review("体重观察跨度不足") }
        var slopes = [slope]
        for week in 0 ..< 4 {
            let weekStart = window[week * 7].date
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            if let value = trend(points.filter { $0.0 < weekStart || $0.0 >= weekEnd }, calendar: calendar) {
                slopes.append(value)
            }
        }
        let meanIntake = window.compactMap(\.intake).reduce(0, +) / 28
        let meanModel = window.compactMap(\.uncalibratedTotal).reduce(0, +) / 28
        let candidates = slopes.flatMap { trendSlope in
            [meanIntake - densityRange.lowerBound * trendSlope - meanModel, meanIntake - densityRange.upperBound * trendSlope - meanModel]
        }
        guard let low = candidates.min(), let high = candidates.max(), low.isFinite, high.isFinite else {
            return review("敏感性计算无法完成")
        }
        let nearest = min(high, max(low, correction))
        let error = nearest - correction
        let direction = error > 0 ? 1 : error < 0 ? -1 : 0
        func evidence(_ reason: String, next: Double? = nil) -> EnergyCalibrationReview {
            review(reason, next: next, intake: meanIntake, model: meanModel, slope: slope,
                   low: low, high: high, direction: direction, eligible: true)
        }
        guard abs(error) >= 100 else { return evidence("敏感性范围包含旧值或偏差不足 100 kcal/天，保持") }
        if let lastApplied {
            let elapsed = calendar.dateComponents([.day], from: lastApplied.date, to: end).day ?? 0
            guard elapsed >= 7, lastApplied.inputFingerprint != fingerprint else {
                return evidence("本周已调整或同一输入已经生效，保持")
            }
        }
        guard let previous, previous.evidenceEligible, previous.direction == direction,
              let elapsed = calendar.dateComponents([.day], from: previous.date, to: end).day,
              (7 ... 14).contains(elapsed), previous.inputFingerprint != fingerprint
        else { return evidence("等待下一次周评估确认同方向证据") }
        let delta = min(75, max(-75, 0.25 * error))
        let updated = correction + delta
        guard abs(updated) <= resting * 0.20 else { return evidence("累计修正将超过静息的 20%，暂停并检查记录") }
        return evidence("连续两次周评估同方向；采用最近候选差额的四分之一，每周最多 75 kcal/天", next: updated)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(), middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func trend(_ points: [(Date, Double)], calendar: Calendar) -> Double? {
        var slopes: [Double] = []
        for left in points.indices {
            for right in points.indices where right > left {
                let days = calendar.dateComponents([.day], from: points[left].0, to: points[right].0).day ?? 0
                if days >= 7 {
                    slopes.append((points[right].1 - points[left].1) / Double(days))
                }
            }
        }
        return median(slopes)
    }

    private static func valid(_ value: Double?) -> Bool {
        value.map { $0.isFinite && (0 ..< 100_000).contains($0) } ?? false
    }
}
