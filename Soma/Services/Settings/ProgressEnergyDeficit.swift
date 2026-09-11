import Foundation

extension ProgressDailyMetrics {
    var energyDeficitMissingReason: String? {
        if isFuture {
            return "尚未发生"
        }
        if intake.recordCount == 0 {
            return "未记录摄入"
        }
        if intake.knownCount == 0 || intake.missingCount > 0 {
            return "饮食热量有缺项"
        }
        guard let expenditure = energy.estimate?.totalKilocalories,
              expenditure.isFinite, expenditure >= 0, intake.value.isFinite
        else { return "缺少消耗估算" }
        return nil
    }

    var estimatedEnergyDeficit: Double? {
        guard energyDeficitMissingReason == nil, let expenditure = energy.estimate?.totalKilocalories else { return nil }
        return expenditure - intake.value
    }
}

/// 摄入与消耗必须先在同日配对，不能把来自不同日期集合的平均值相减。
struct ProgressEnergyDeficit: Equatable, Sendable {
    let kilocalories: Double?
    let includedDayCount: Int
    let eligibleDayCount: Int
    let detail: String
    let unavailableText: String
    let remainingIntakeKilocalories: Double?

    var valueText: String {
        guard let kilocalories else { return unavailableText }
        let rounded = kilocalories.rounded()
        let sign = rounded < 0 ? "−" : ""
        return sign + abs(rounded).formatted(.number.precision(.fractionLength(0)))
    }

    var remainingIntakeText: String? {
        remainingIntakeKilocalories.map { $0.rounded().formatted(.number.precision(.fractionLength(0))) }
    }

    var accessibilityValue: String {
        guard let kilocalories else { return unavailableText + "，" + detail }
        let remaining = remainingIntakeText.map { "仍可摄入 " + $0 + " 千卡，" } ?? ""
        return valueText + " 千卡，" + remaining + (kilocalories < 0 ? "负值表示热量盈余，" : "") + detail
    }

    static func make(snapshot: ProgressHistorySnapshot) -> Self? {
        let daily = snapshot.window.period == .day
        guard snapshot.window.period != .year else { return nil }
        let days = snapshot.days.filter { !$0.isFuture && (daily || $0.isCompleteDay) }
        let values = days.compactMap(\.estimatedEnergyDeficit)
        let total = values.reduce(0, +)
        let amount = values.isEmpty || !total.isFinite ? nil : total
        let detail: String
        let unavailable: String
        if daily {
            unavailable = snapshot.days.first?.energyDeficitMissingReason ?? "待估算"
            detail = amount == nil ? "需要已记录摄入与消耗估算" : "预估总消耗 − 已记录摄入"
        } else {
            unavailable = "待估算"
            let containsToday = snapshot.days.contains { !$0.isFuture && !$0.isCompleteDay }
            detail = days.isEmpty ? "暂无已结束日期"
                : "已计 \(values.count)/\(days.count) 天 · " + (containsToday ? "截至昨日" : "按已记录摄入估算")
        }
        let remaining: Double? = if daily, amount != nil, let calories = snapshot.nutritionRings?.calories,
                                    let target = calories.target, target.isFinite, target > 0
        {
            CalorieRingStatusCopy(progress: calories).remainingKilocalories ?? 0
        } else {
            nil
        }
        return .init(kilocalories: amount, includedDayCount: values.count, eligibleDayCount: days.count,
                     detail: detail, unavailableText: unavailable, remainingIntakeKilocalories: remaining)
    }
}
