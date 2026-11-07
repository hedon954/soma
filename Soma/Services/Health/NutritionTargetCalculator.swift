import Foundation

enum NutritionIntakeStatus: Equatable, Sendable {
    case under
    case onTarget
    case over
    case noTarget

    static func from(ratio: Double?) -> Self {
        guard let ratio, ratio.isFinite, ratio >= 0 else {
            return .noTarget
        }
        if ratio < 0.85 {
            return .under
        }
        if ratio > 1.15 {
            return .over
        }
        return .onTarget
    }

    var accessibilityLabel: String {
        switch self {
        case .under: "摄入不足"
        case .onTarget: "接近目标"
        case .over: "摄入超过"
        case .noTarget: "没有推荐目标"
        }
    }
}

struct NutritionTargets: Equatable, Sendable {
    var calories: Double
    var proteinGrams: Double?
    var carbsGrams: Double?
    var fatGrams: Double?
}

struct NutritionRingProgress: Equatable, Sendable {
    var intake: Double
    var target: Double?

    var ratio: Double? {
        guard let target, target > 0, intake.isFinite else {
            return nil
        }
        return intake / target
    }

    var status: NutritionIntakeStatus {
        if target == 0, intake.isFinite, intake >= 0 {
            return intake > 0 ? .over : .onTarget
        }
        return NutritionIntakeStatus.from(ratio: ratio)
    }
}

/// 当日未达推荐时，底部提示「仍可摄入」用正差额；环心只写已摄入／推荐摄入。
struct CalorieRingStatusCopy: Equatable, Sendable {
    var remainingKilocalories: Double?
    var completedPercent: Int?

    init(progress: NutritionRingProgress) {
        guard let target = progress.target, target >= 0, progress.intake.isFinite else {
            remainingKilocalories = nil
            completedPercent = nil
            return
        }
        let remaining = target - progress.intake
        remainingKilocalories = remaining > 0 ? remaining : nil
        completedPercent = target > 0 ? max(0, Int((progress.intake / target * 100).rounded())) : nil
    }
}

struct ProgressNutritionRings: Equatable, Sendable {
    var calories: NutritionRingProgress
    var protein: NutritionRingProgress
    var carbs: NutritionRingProgress
    var fat: NutritionRingProgress

    static func day(
        intake: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        estimate: Double?,
        weightKG: Double?,
        fitnessGoal: FitnessGoal?,
        dailyTargetDeficitKilocalories: Double? = nil
    ) -> ProgressNutritionRings? {
        guard let estimate, estimate > 0 else {
            return from(intake: intake, protein: protein, carbs: carbs, fat: fat, targets: nil)
        }
        return from(
            intake: intake,
            protein: protein,
            carbs: carbs,
            fat: fat,
            targets: NutritionTargetCalculator.targets(
                weightKG: weightKG,
                fitnessGoal: fitnessGoal,
                totalKilocalories: estimate,
                dailyTargetDeficitKilocalories: dailyTargetDeficitKilocalories
            )
        )
    }

    private static func from(
        intake: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        targets: NutritionTargets?
    ) -> ProgressNutritionRings {
        ProgressNutritionRings(
            calories: NutritionRingProgress(intake: intake, target: targets?.calories),
            protein: NutritionRingProgress(intake: protein, target: targets?.proteinGrams),
            carbs: NutritionRingProgress(intake: carbs, target: targets?.carbsGrams),
            fat: NutritionRingProgress(intake: fat, target: targets?.fatGrams)
        )
    }
}

enum NutritionTargetCalculator {
    static func calorieAdjustment(for goal: FitnessGoal?, dailyTargetDeficitKilocalories: Double? = nil) -> Double {
        if goal?.supportsCalorieDeficit == true {
            return -DailyTargetDeficit.resolve(dailyTargetDeficitKilocalories)
        }
        return goal == .muscleGain ? 250 : 0
    }

    static func proteinGramsPerKilogram(for goal: FitnessGoal?) -> Double {
        switch goal {
        case .muscleGain: 1.8
        case .fatLoss, .recomposition: 2.0
        case .none: 1.6
        }
    }

    static func targets(
        weightKG: Double?,
        fitnessGoal: FitnessGoal?,
        totalKilocalories: Double,
        dailyTargetDeficitKilocalories: Double? = nil
    ) -> NutritionTargets {
        let calories = max(0, totalKilocalories + calorieAdjustment(
            for: fitnessGoal, dailyTargetDeficitKilocalories: dailyTargetDeficitKilocalories
        ))
        guard let weightKG, weightKG.isFinite, weightKG > 0 else {
            return NutritionTargets(
                calories: calories,
                proteinGrams: nil,
                carbsGrams: nil,
                fatGrams: nil
            )
        }
        let protein = weightKG * proteinGramsPerKilogram(for: fitnessGoal)
        let fat = calories * 0.25 / 9
        let remaining = max(0, calories - protein * 4 - fat * 9)
        return NutritionTargets(
            calories: calories,
            proteinGrams: protein,
            carbsGrams: remaining / 4,
            fatGrams: fat
        )
    }
}
