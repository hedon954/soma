import Foundation

struct RestingEnergyFormulaInput: Equatable, Sendable {
    let weightKG: Double
    let heightCM: Double
    let age: Int
    let biologicalSex: BiologicalSex
    let dailyKilocalories: Double

    var originalFormula: String {
        switch biologicalSex {
        case .male:
            "男：10 × 体重kg + 6.25 × 身高cm − 5 × 年龄 + 5"
        case .female:
            "女：10 × 体重kg + 6.25 × 身高cm − 5 × 年龄 − 161"
        case .unspecified, .other:
            ""
        }
    }

    var substitutedFormula: String {
        let adjustment = biologicalSex == .male ? "+ 5" : "− 161"
        return "10 × \(weightKG.formatted()) + 6.25 × \(heightCM.formatted()) − 5 × \(age) \(adjustment) = \(Int(dailyKilocalories.rounded())) kcal/天"
    }
}

enum RestingEnergyCalculator {
    /// Mifflin–St Jeor 静息能量公式，返回完整 24 小时 kcal/day。
    static func dailyKilocalories(
        weightKG: Double?,
        heightCM: Double?,
        age: Int?,
        biologicalSex: BiologicalSex
    ) -> Double? {
        guard let weightKG, weightKG.isFinite, weightKG > 0,
              let heightCM, heightCM.isFinite, heightCM > 0,
              let age, age > 0
        else { return nil }
        let sexAdjustment: Double
        switch biologicalSex {
        case .male: sexAdjustment = 5
        case .female: sexAdjustment = -161
        case .unspecified, .other: return nil
        }
        let result = 10 * weightKG + 6.25 * heightCM - 5 * Double(age) + sexAdjustment
        return result.isFinite && result > 0 ? result : nil
    }
}

enum TrainingEnergyNetIncrement {
    /// 记录卡是完整消耗；日总计只加相对 1 MET 的增量，避免和当天静息重叠。
    static func kilocalories(
        gross: Double?,
        met: Double?,
        durationMinutes: Double? = nil,
        dailyResting: Double? = nil
    ) -> Double? {
        guard let gross, gross.isFinite, gross >= 0 else { return nil }
        if let met, met.isFinite, met > 0 {
            return met <= 1 ? 0 : gross * (met - 1) / met
        }
        guard let durationMinutes, durationMinutes > 0, durationMinutes.isFinite,
              let dailyResting, dailyResting > 0, dailyResting.isFinite
        else {
            return nil
        }
        return max(0, gross - dailyResting * durationMinutes / (24 * 60))
    }
}
