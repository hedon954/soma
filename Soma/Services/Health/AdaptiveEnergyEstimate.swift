import Foundation

struct EnergyLifestyleBaseline: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = .init()
    var effectiveFrom: Date
    var factor: Double
    var label: String
}

struct AdaptiveEnergyEstimate: Equatable, Sendable {
    enum Method: String, Sendable {
        case confirmedLifestyle
        case defaultReference
        case dynamicActivity
    }

    let method: Method
    let restingKilocalories: Double
    /// 残差系数，来自 `ResidualEnergyCoefficient`。不是总消耗 / 静息，也不是传统全天 PAL。
    let factor: Double
    let sourceName: String
    let effectiveFrom: Date
    var restingSourceName = "个人静息公式"
    /// 进入总消耗的活动能量。所选日活动能量存在时，这里就是那一份读数，不是另加的训练。
    var trainingNetKilocalories: Double = 0
    /// 所选日活动读数。nil 表示没有读数；0 是有效读数。
    var activeEnergyKilocalories: Double?
    var components: DailyEnergyTotal.Components?
    var calculation: EnergyDayCalculation?
    var totalKilocalories: Double {
        if let components {
            return components.totalKilocalories
        }
        return restingKilocalories * factor + trainingNetKilocalories
    }

    static func presented(
        _ components: DailyEnergyTotal.Components,
        selectedActiveKilocalories: Double?,
        calculation: EnergyDayCalculation?,
        effectiveFrom: Date
    ) -> Self {
        .init(
            method: .defaultReference,
            restingKilocalories: components.restingKilocalories,
            factor: components.coefficient,
            sourceName: "初始回退系数",
            effectiveFrom: effectiveFrom,
            trainingNetKilocalories: components.activityKilocalories,
            activeEnergyKilocalories: selectedActiveKilocalories,
            components: components,
            calculation: calculation
        )
    }

    static func from(_ calculation: EnergyDayCalculation) -> Self {
        if let components = calculation.presentedTotal {
            return presented(
                components,
                selectedActiveKilocalories: calculation.presentedSelectedActiveKilocalories,
                calculation: calculation,
                effectiveFrom: calculation.input.date
            )
        }
        return .init(
            method: .dynamicActivity,
            restingKilocalories: calculation.input.resting,
            factor: calculation.factor,
            sourceName: calculation.input.reference.reason,
            effectiveFrom: calculation.input.reference.effectiveFrom,
            trainingNetKilocalories: calculation.trainingDelta,
            calculation: calculation
        )
    }
}

struct AdaptiveEnergyOutcome: Equatable, Sendable {
    let estimate: AdaptiveEnergyEstimate?
    let missingReason: String?
}

enum AdaptiveEnergyEstimator {
    static func estimate(
        for targetDate: Date,
        now: Date = .now,
        restingEstimate: Double?,
        trainingNetKilocalories: Double = 0,
        activeEnergyKilocalories: Double? = nil,
        coefficient: ResidualEnergyCoefficient = .current(),
        includedTrainingKilocalories: Double? = nil,
        calendar: Calendar = .current
    ) -> AdaptiveEnergyOutcome {
        let targetDay = calendar.startOfDay(for: targetDate)
        guard targetDay <= calendar.startOfDay(for: now) else {
            return .init(estimate: nil, missingReason: "尚未发生")
        }
        guard let resting = restingEstimate, DailyEnergyTotal.isUsableActive(resting), resting > 0 else {
            return .init(estimate: nil, missingReason: "缺少有效静息消耗，请补充身体资料")
        }
        let recorded = activeEnergyKilocalories == nil && trainingNetKilocalories > 0 ? trainingNetKilocalories : nil
        guard let components = DailyEnergyTotal.compose(
            restingKilocalories: resting,
            coefficient: coefficient,
            selectedActiveKilocalories: activeEnergyKilocalories,
            includedTrainingKilocalories: activeEnergyKilocalories == nil ? nil : includedTrainingKilocalories,
            recordedTrainingKilocalories: recorded
        ) else {
            return .init(estimate: nil, missingReason: "缺少有效静息消耗，请补充身体资料")
        }
        return .init(
            estimate: .presented(
                components,
                selectedActiveKilocalories: activeEnergyKilocalories.flatMap { DailyEnergyTotal.isUsableActive($0) ? $0 : nil },
                calculation: nil,
                effectiveFrom: targetDay
            ),
            missingReason: nil
        )
    }
}
