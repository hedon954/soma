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

struct DailyEnergyProjectionResult: Equatable, Sendable {
    let dailyTotalKilocalories: Int
    let projectedRestingKilocalories: Int
    let projectedActiveKilocalories: Int
    let elapsedDayFraction: Double
    let originalFormula: String
    let substitutedFormula: String
}

enum DailyEnergyProjectionCalculator {
    static func estimate(
        restingKilocaloriesSoFar: Int?,
        dailyRestingEstimate: Double?,
        restingUsesHealth: Bool,
        activeKilocaloriesSoFar: Int?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DailyEnergyProjectionResult? {
        guard let activeKilocaloriesSoFar, activeKilocaloriesSoFar >= 0 else {
            return nil
        }
        let fraction = elapsedDayFraction(now: now, calendar: calendar)
        guard fraction > 0 else { return nil }

        let projectedResting: Int
        let originalFormula: String
        let substitutedFormula: String
        let projectedActive = Int(
            (Double(activeKilocaloriesSoFar) / fraction).rounded()
        )
        let percentage = Int((fraction * 100).rounded())

        if restingUsesHealth {
            guard let restingKilocaloriesSoFar, restingKilocaloriesSoFar >= 0 else {
                return nil
            }
            projectedResting = Int(
                (Double(restingKilocaloriesSoFar) / fraction).rounded()
            )
            let total = projectedResting + projectedActive
            originalFormula = "（截至当前静息 + 截至当前活动）÷ 今日已过比例"
            substitutedFormula = "（\(restingKilocaloriesSoFar) + \(activeKilocaloriesSoFar)）÷ \(percentage)% = \(total) kcal"
        } else {
            guard let dailyRestingEstimate, dailyRestingEstimate > 0 else {
                return nil
            }
            projectedResting = Int(dailyRestingEstimate.rounded())
            let total = projectedResting + projectedActive
            originalFormula = "24h 静息 + 截至当前活动 ÷ 今日已过比例"
            substitutedFormula = "\(projectedResting) + \(activeKilocaloriesSoFar) ÷ \(percentage)% = \(total) kcal"
        }

        return DailyEnergyProjectionResult(
            dailyTotalKilocalories: projectedResting + projectedActive,
            projectedRestingKilocalories: projectedResting,
            projectedActiveKilocalories: projectedActive,
            elapsedDayFraction: fraction,
            originalFormula: originalFormula,
            substitutedFormula: substitutedFormula
        )
    }

    static func elapsedDayFraction(
        now: Date,
        calendar: Calendar
    ) -> Double {
        let dayStart = calendar.startOfDay(for: now)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return 0
        }
        let dayDuration = nextDay.timeIntervalSince(dayStart)
        guard dayDuration > 0 else { return 0 }
        return min(max(now.timeIntervalSince(dayStart) / dayDuration, 0), 1)
    }
}
