import Foundation

struct ProgressRecordedTotal: Equatable, Sendable {
    let value: Double
    let knownCount: Int
    let missingCount: Int
    let recordCount: Int

    init(_ values: [Double?], additionalIncompleteCount: Int = 0) {
        let known = values.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
        value = known.reduce(0, +)
        knownCount = known.count
        missingCount = values.count - known.count + min(known.count, max(0, additionalIncompleteCount))
        recordCount = values.count
    }
}

struct ProgressHistoryRecord: Sendable {
    let activity: ProgressRecentActivity
    var calories: Double?
    var calorieMET: Double?
    var activeEnergyKilocalories: Double?
    var isDailyActivity = false
    /// 日常活动获胜来源。只用于判断训练能否从同一份日活动能量里拆出，不把多个来源相加。
    var dailyActivitySource: DailyActivityWinningSource? = nil
    var trainingEvidence: EnergyTrainingEvent?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var volume: Double?
    var logicalSets: Int = 0
    var weight: Double?
    var bodyFat: Double?
    var waist: Double?
    var caloriesArePartial = false
    var exerciseID: UUID?
    var durationSeconds: Double?
    var primaryMuscles: [String] = []
    var secondaryMuscles: [String] = []
}

struct ProgressProfileFacts: Sendable {
    var updatedAt: Date
    var birthDate: Date?
    var height: Double?
    var biologicalSex: BiologicalSex
    var baselines: [EnergyLifestyleBaseline]
    var fitnessGoal: FitnessGoal?
    var energyFacts: EnergyProjectionFacts = .init()
}

struct ProgressDailyMetrics: Sendable, Identifiable {
    let date: Date
    let isFuture: Bool
    let isCompleteDay: Bool
    let records: [ProgressHistoryRecord]
    let intake: ProgressRecordedTotal
    let protein: ProgressRecordedTotal
    let carbs: ProgressRecordedTotal
    let fat: ProgressRecordedTotal
    let trainingCalories: ProgressRecordedTotal
    let volume: ProgressRecordedTotal
    let logicalSets: Int
    let energy: AdaptiveEnergyOutcome
    let restingFormula: RestingEnergyFormulaInput?
    let usesLaterProfile: Bool
    var foodConfirmedComplete = false
    var id: Date {
        date
    }

    var hasTraining: Bool {
        records.contains { $0.activity.kind == .workout && !$0.isDailyActivity }
    }

    var latestWeight: ProgressHistoryRecord? {
        records.last { record in
            guard let weight = record.weight else { return false }
            return weight.isFinite && weight > 0
        }
    }
}

struct ProgressEnergyChartBucket: Identifiable, Sendable {
    let start: Date
    let end: Date
    let intake: Double?
    let estimate: Double?
    let intakeDayCount: Int
    let estimateDayCount: Int
    var id: Date {
        start
    }
}

struct ProgressHistorySnapshot: Sendable {
    let window: ProgressPeriodWindow
    let days: [ProgressDailyMetrics]
    let energyBuckets: [ProgressEnergyChartBucket]
    let averageIntake: Double?
    let averageEstimate: Double?
    let intakeDayCount: Int
    let estimateDayCount: Int
    let trainingDayCount: Int
    let logicalSets: Int
    let volume: Double
    let latestWeightKG: Double?
    let fitnessGoal: FitnessGoal?
    let nutritionRings: ProgressNutritionRings?
    var energyUpdates: [EnergyHistoryUpdate] = []
    var habitualEnergyFactor: Double?
    var energyForecasts: [EnergyForecast] = []
}

enum ProgressHistoryProjection {
    static func build(
        window: ProgressPeriodWindow, records: [ProgressHistoryRecord], profile: ProgressProfileFacts?,
        now: Date = .now, calendar: Calendar = .current
    ) -> ProgressHistorySnapshot {
        let today = calendar.startOfDay(for: now)
        let runtime = EnergyRuntimeProjection.build(window: window, records: records, profile: profile, now: now, calendar: calendar)
        let visible = records.filter { $0.activity.date <= now && window.contains($0.activity.date) }
        let groups = Dictionary(grouping: visible, by: { calendar.startOfDay(for: $0.activity.date) })
        let weights = records.filter { record in
            guard let weight = record.weight else { return false }
            return weight.isFinite && weight > 0 && record.activity.date <= now
        }.sorted { $0.activity.date < $1.activity.date }
        var days: [ProgressDailyMetrics] = []
        var cursor = window.start
        while cursor < window.end, let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor {
            let entries = (groups[cursor] ?? []).sorted { $0.activity.date < $1.activity.date }
            let meals = entries.filter { $0.activity.kind == .meal }
            let workouts = entries.filter { $0.activity.kind == .workout }
            let recordedActivity = workouts.compactMap(\.activeEnergyKilocalories).last
            let weight = weights.last { $0.activity.date < next }?.weight
            let age = profile?.birthDate.flatMap { calendar.dateComponents([.year], from: $0, to: cursor).year }
            let resting = RestingEnergyCalculator.dailyKilocalories(
                weightKG: weight, heightCM: profile?.height, age: age, biologicalSex: profile?.biologicalSex ?? .unspecified
            )
            let formula: RestingEnergyFormulaInput? = if let weight, let height = profile?.height, let age, let resting {
                .init(weightKG: weight, heightCM: height, age: age, biologicalSex: profile?.biologicalSex ?? .unspecified, dailyKilocalories: resting)
            } else {
                nil
            }
            days.append(.init(
                date: cursor, isFuture: cursor > today, isCompleteDay: next <= today, records: entries,
                intake: .init(meals.map(\.calories), additionalIncompleteCount: meals.count { $0.caloriesArePartial && $0.calories != nil }),
                protein: .init(meals.map(\.protein)),
                carbs: .init(meals.map(\.carbs)), fat: .init(meals.map(\.fat)),
                trainingCalories: .init(recordedActivity.map { [$0] } ?? workouts.map(\.calories)), volume: .init(workouts.map(\.volume)),
                logicalSets: workouts.reduce(0) { $0 + max(0, $1.logicalSets) },
                energy: runtime.outcomes[cursor] ?? .init(estimate: nil, missingReason: cursor > today ? "尚未发生" : "缺少有效静息消耗，请补充身体资料"),
                restingFormula: formula, usesLaterProfile: (profile?.updatedAt ?? .distantPast) >= next,
                foodConfirmedComplete: runtime.completeFoodDays.contains(cursor)
            ))
            cursor = next
        }
        let eligible = window.period == .day ? days.filter { !$0.isFuture } : days.filter(\.isCompleteDay)
        let intake = eligible.filter { $0.intake.knownCount > 0 }.map(\.intake.value)
        let estimates = eligible.compactMap { $0.energy.estimate?.totalKilocalories }
        let buckets = window.buckets(calendar: calendar).map { bucket in
            let contents = days.filter { $0.date >= bucket.start && $0.date < bucket.end && !$0.isFuture }
            let included = window.period == .year ? contents.filter(\.isCompleteDay) : contents
            let intake = included.filter { $0.intake.knownCount > 0 }.map(\.intake.value)
            let estimates = included.compactMap { $0.energy.estimate?.totalKilocalories }
            return ProgressEnergyChartBucket(
                start: bucket.start, end: bucket.end, intake: mean(intake), estimate: mean(estimates),
                intakeDayCount: intake.count, estimateDayCount: estimates.count
            )
        }
        let latestWeight = weights.last { $0.activity.date <= now }?.weight
        let goal = profile?.fitnessGoal
        let nutritionRings: ProgressNutritionRings? = if window.period == .day, let day = days.first, !day.isFuture {
            .day(
                intake: day.intake.value,
                protein: day.protein.value,
                carbs: day.carbs.value,
                fat: day.fat.value,
                estimate: day.energy.estimate?.totalKilocalories,
                weightKG: latestWeight,
                fitnessGoal: goal
            )
        } else {
            nil
        }
        return .init(
            window: window, days: days, energyBuckets: buckets,
            averageIntake: mean(intake), averageEstimate: mean(estimates), intakeDayCount: intake.count, estimateDayCount: estimates.count,
            trainingDayCount: days.count(where: \.hasTraining), logicalSets: days.reduce(0) { $0 + $1.logicalSets },
            volume: days.reduce(0) { $0 + $1.volume.value },
            latestWeightKG: latestWeight,
            fitnessGoal: goal,
            nutritionRings: nutritionRings, energyUpdates: runtime.updates,
            habitualEnergyFactor: EnergyReferenceBuilder.habitualFactor(Array(runtime.calculations.values), before: today, calendar: calendar),
            energyForecasts: EnergyForecastProjection.upcoming(calculations: runtime.calculations, plans: profile?.energyFacts.plannedDays ?? [],
                                                               on: today, calendar: calendar)
        )
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
