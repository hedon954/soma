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
    let factor: Double
    let sourceName: String
    let effectiveFrom: Date
    var restingSourceName = "个人静息公式"
    var trainingNetKilocalories: Double = 0
    var activeEnergyKilocalories: Double?
    var calculation: EnergyDayCalculation?
    var totalKilocalories: Double {
        if let calculation {
            return calculation.total
        }
        return restingKilocalories * factor + trainingNetKilocalories
    }

    static func from(_ calculation: EnergyDayCalculation) -> Self {
        .init(method: .dynamicActivity, restingKilocalories: calculation.input.resting, factor: calculation.factor,
              sourceName: calculation.input.reference.reason, effectiveFrom: calculation.input.reference.effectiveFrom,
              trainingNetKilocalories: calculation.trainingDelta, calculation: calculation)
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
        baselines: [EnergyLifestyleBaseline] = [],
        trainingNetKilocalories: Double = 0,
        activeEnergyKilocalories: Double? = nil,
        calendar: Calendar = .current
    ) -> AdaptiveEnergyOutcome {
        let targetDay = calendar.startOfDay(for: targetDate)
        guard targetDay <= calendar.startOfDay(for: now) else {
            return .init(estimate: nil, missingReason: "尚未发生")
        }
        let baseline = baselines.filter {
            $0.effectiveFrom <= targetDay && $0.factor.isFinite && (1 ... 4).contains($0.factor)
        }.max {
            $0.effectiveFrom == $1.effectiveFrom
                ? $0.id.uuidString < $1.id.uuidString
                : $0.effectiveFrom < $1.effectiveFrom
        }
        let activeEnergy = activeEnergyKilocalories.flatMap { validEnergy($0) ? $0 : nil }
        let factor = baseline?.factor ?? 1.4
        let trainingNet = validEnergy(trainingNetKilocalories) ? max(0, trainingNetKilocalories) : 0
        guard let resting = restingEstimate.flatMap({ validEnergy($0) && $0 > 0 ? $0 : nil }),
              validEnergy(resting * factor + trainingNet)
        else {
            return .init(estimate: nil, missingReason: "缺少有效静息消耗，请补充身体资料")
        }
        return .init(
            estimate: .init(
                method: baseline == nil ? .defaultReference : .confirmedLifestyle,
                restingKilocalories: resting,
                factor: factor,
                sourceName: baseline?.label ?? "默认参考",
                effectiveFrom: baseline?.effectiveFrom ?? targetDay,
                trainingNetKilocalories: trainingNet,
                activeEnergyKilocalories: activeEnergy
            ),
            missingReason: nil
        )
    }

    private static func validEnergy(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value < 100_000
    }
}
