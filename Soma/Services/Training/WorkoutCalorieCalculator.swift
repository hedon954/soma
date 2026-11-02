import Foundation
import SwiftData

struct WorkoutCalorieEstimate: Equatable {
    let calories: Int
    let met: Double
    let activityLabel: String
    let durationMinutes: Double
    let durationWasEstimated: Bool
}

enum WorkoutCalorieCalculator {
    /// MET values follow the 2024 Adult Compendium of Physical Activities.
    /// The 4-second fallback is the midpoint of a controlled 1–2s concentric
    /// plus 2–3s eccentric repetition; it is used only when the user supplied
    /// complete sets, reps and rest, and never overwrites actual duration.
    private static let estimatedSecondsPerResistanceRep = 4.0

    static func estimate(
        exercise: String,
        intensity: String?,
        durationMinutes: Int?,
        sets: Int? = nil,
        reps: Int? = nil,
        restSeconds: Int? = nil,
        weightKG: Double?
    ) -> WorkoutCalorieEstimate? {
        let usableDuration = sanitizedActualDurationMinutes(
            durationMinutes,
            sets: sets,
            reps: reps,
            restSeconds: restSeconds
        )
        let evidence: [WorkoutSetEvidence] = if let sets, sets > 0, let reps, reps > 0 {
            (1 ... sets).map { index in
                WorkoutSetEvidence(
                    logicalSetIndex: index,
                    targetKind: .repetitions,
                    reps: reps,
                    restSeconds: index < sets ? restSeconds : nil
                )
            }
        } else {
            []
        }
        return estimateWorkout(
            exercise: exercise,
            intensity: intensity,
            actualDurationMinutes: usableDuration,
            evidence: evidence,
            fallbackRestSeconds: restSeconds,
            weightKG: weightKG
        )
    }

    /// Canonical calculator shared by chat-created and guided workouts.
    /// Whole-workout measured duration wins; otherwise every work and rest
    /// interval must be supported by the stored evidence.
    static func estimateWorkout(
        exercise: String,
        intensity: String?,
        actualDurationMinutes: Int?,
        evidence: [WorkoutSetEvidence],
        fallbackRestSeconds: Int?,
        weightKG: Double?
    ) -> WorkoutCalorieEstimate? {
        guard let weightKG, weightKG > 0 else { return nil }
        let duration: (minutes: Double, estimated: Bool)
        if let actualDurationMinutes, actualDurationMinutes > 0 {
            duration = (Double(actualDurationMinutes), false)
        } else {
            guard let derived = evidenceDuration(
                from: evidence,
                fallbackRestSeconds: fallbackRestSeconds
            ) else {
                return nil
            }
            duration = derived
        }

        let activity = activity(for: exercise, intensity: intensity)
        let calories = activity.met * weightKG * duration.minutes / 60
        guard calories.isFinite, calories > 0 else { return nil }
        return WorkoutCalorieEstimate(
            calories: max(Int(calories.rounded()), 1),
            met: activity.met,
            activityLabel: activity.label,
            durationMinutes: duration.minutes,
            durationWasEstimated: duration.estimated
        )
    }

    /// Guided workouts already have atom-level evidence, so they do not need
    /// to squeeze seconds into the legacy integer `durationMinutes` field.
    static func estimateGuidedWorkout(
        exercise: String,
        intensity: String? = nil,
        evidence: [WorkoutSetEvidence],
        weightKG: Double?
    ) -> WorkoutCalorieEstimate? {
        estimateWorkout(
            exercise: exercise,
            intensity: intensity,
            actualDurationMinutes: nil,
            evidence: evidence,
            fallbackRestSeconds: nil,
            weightKG: weightKG
        )
    }

    static func guidedDuration(
        from evidence: [WorkoutSetEvidence]
    ) -> (minutes: Double, estimated: Bool)? {
        evidenceDuration(from: evidence, fallbackRestSeconds: nil)
    }

    static func evidenceDuration(
        from evidence: [WorkoutSetEvidence],
        fallbackRestSeconds: Int?
    ) -> (minutes: Double, estimated: Bool)? {
        guard !evidence.isEmpty else { return nil }
        let draft = WorkoutRecordDraft(evidence: evidence)
        let groups = draft.groups.sorted { $0.sourceOrder < $1.sourceOrder }
        guard !groups.isEmpty else { return nil }
        var totalSeconds = 0.0
        var usedRepetitionEstimate = false
        for (groupIndex, group) in groups.enumerated() {
            let efforts = group.efforts.sorted { $0.sourceOrder < $1.sourceOrder }
            guard !efforts.isEmpty else { return nil }
            for (effortIndex, item) in efforts.enumerated() {
                switch item.targetKind {
                case .duration:
                    guard let seconds = item.durationSeconds, seconds > 0 else {
                        return nil
                    }
                    totalSeconds += Double(seconds)
                case .repetitions:
                    guard let reps = item.reps, reps > 0 else { return nil }
                    if let seconds = item.durationSeconds, seconds > 0 {
                        totalSeconds += Double(seconds)
                    } else {
                        totalSeconds += Double(reps) * estimatedSecondsPerResistanceRep
                        usedRepetitionEstimate = true
                    }
                }

                if let restSeconds = item.restSeconds, restSeconds >= 0 {
                    totalSeconds += Double(restSeconds)
                } else {
                    let requiresGroupRest = effortIndex == efforts.count - 1
                        && groupIndex < groups.count - 1
                    if requiresGroupRest {
                        guard let fallbackRestSeconds, fallbackRestSeconds >= 0 else {
                            return nil
                        }
                        totalSeconds += Double(fallbackRestSeconds)
                    }
                }
            }
        }
        guard totalSeconds > 0 else { return nil }
        return (totalSeconds / 60, usedRepetitionEstimate)
    }

    static func estimatedResistanceDuration(
        sets: Int?,
        reps: Int?,
        restSeconds: Int?
    ) -> Double? {
        guard
            let sets,
            sets > 0,
            let reps,
            reps > 0
        else {
            return nil
        }
        if sets > 1 {
            guard let restSeconds, restSeconds >= 0 else { return nil }
        }

        let repetitionSeconds = Double(sets * reps) * estimatedSecondsPerResistanceRep
        let recoverySeconds = Double(max(sets - 1, 0) * (restSeconds ?? 0))
        let totalMinutes = (repetitionSeconds + recoverySeconds) / 60
        return totalMinutes > 0 ? totalMinutes : nil
    }

    /// Detects the common Agent mistake `sets × reps × restSeconds / 60`
    /// (e.g. 4×8×90/60 = 48) which treats rest as per-rep work time.
    static func isMistakenSetsRepsRestDuration(
        _ durationMinutes: Int?,
        sets: Int?,
        reps: Int?,
        restSeconds: Int?
    ) -> Bool {
        guard
            let durationMinutes,
            durationMinutes > 0,
            let sets,
            sets > 0,
            let reps,
            reps > 0,
            let restSeconds,
            restSeconds > 0
        else {
            return false
        }
        let mistaken = Int((Double(sets * reps * restSeconds) / 60).rounded())
        guard durationMinutes == mistaken else { return false }
        if let estimated = estimatedResistanceDuration(
            sets: sets,
            reps: reps,
            restSeconds: restSeconds
        ) {
            // Keep genuine long sessions that happen to match the formula.
            return Double(durationMinutes) > estimated * 2.5
        }
        return true
    }

    static func sanitizedActualDurationMinutes(
        _ durationMinutes: Int?,
        sets: Int?,
        reps: Int?,
        restSeconds: Int?
    ) -> Int? {
        if isMistakenSetsRepsRestDuration(
            durationMinutes,
            sets: sets,
            reps: reps,
            restSeconds: restSeconds
        ) {
            return nil
        }
        return durationMinutes
    }

    /// Clears a mistaken `durationMinutes` and refreshes calorie fields from the
    /// resistance formula. Returns whether the entry was changed.
    @discardableResult
    static func sanitizeStoredDurationIfNeeded(
        _ entry: WorkoutEntry,
        weightKG: Double? = nil
    ) -> Bool {
        let sets = entry.setCount
        let reps = entry.representativeReps
        guard isMistakenSetsRepsRestDuration(
            entry.durationMinutes,
            sets: sets,
            reps: reps,
            restSeconds: entry.restSeconds
        ) else {
            return false
        }
        entry.durationMinutes = nil
        guard entry.estimatedCalories == nil || entry.calorieScope == .metGross else { return true }
        let estimate = estimate(
            exercise: entry.exercise,
            intensity: entry.intensity,
            durationMinutes: nil,
            sets: sets,
            reps: reps,
            restSeconds: entry.restSeconds,
            weightKG: weightKG
        )
        entry.estimatedCalories = estimate?.calories
        entry.calorieMET = estimate?.met
        entry.calorieScope = .metGross
        entry.calorieDurationMinutes = estimate?.durationMinutes
        entry.calorieDurationEstimated = estimate?.durationWasEstimated ?? false
        return true
    }

    @MainActor
    static func refreshStoredEstimate(
        _ entry: WorkoutEntry,
        in context: ModelContext,
        calorieOverride: Int? = nil,
        calorieScope: WorkoutCalorieScope? = nil
    ) {
        refreshStoredEstimate(
            entry,
            weightKG: latestRecordedWeight(at: entry.date, in: context),
            calorieOverride: calorieOverride,
            calorieScope: calorieScope
        )
    }

    static func refreshStoredEstimate(
        _ entry: WorkoutEntry,
        weightKG: Double?,
        calorieOverride: Int? = nil,
        calorieScope: WorkoutCalorieScope? = nil
    ) {
        let estimate = estimateWorkout(
            exercise: entry.exercise,
            intensity: entry.intensity,
            actualDurationMinutes: entry.durationMinutes,
            evidence: entry.setEntries,
            fallbackRestSeconds: entry.restSeconds,
            weightKG: weightKG
        )
        let scope = calorieOverride.map { value in
            calorieScope ?? (value == entry.estimatedCalories ? entry.calorieScope : .unknown)
        } ?? .metGross
        entry.estimatedCalories = calorieOverride ?? estimate?.calories
        entry.calorieScope = scope
        entry.calorieMET = estimate?.met
        entry.calorieDurationMinutes = estimate?.durationMinutes
        entry.calorieDurationEstimated = estimate?.durationWasEstimated ?? false
    }

    @MainActor
    static func currentRecordedWeight(in context: ModelContext) -> Double? {
        latestRecordedWeight(at: .now, in: context)
    }

    /// 只使用 Session 开始时间之前已记录的体重事实；身体资料不再维护第二份体重。
    @MainActor
    static func latestRecordedWeight(
        at date: Date,
        in context: ModelContext
    ) -> Double? {
        let cutoff = date
        var bodyDescriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate {
                $0.date <= cutoff && $0.weight != nil
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        bodyDescriptor.fetchLimit = 50
        let bodyEntries = (try? context.fetch(bodyDescriptor)) ?? []
        if let weight = bodyEntries.first(where: {
            ($0.weight ?? 0) > 0
        })?.weight {
            return weight
        }
        return nil
    }

    private static func activity(
        for exercise: String,
        intensity: String?
    ) -> (met: Double, label: String) {
        let normalized = exercise
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let vigorous = ["偏重", "高强度", "vigorous", "high intensity", "hiit"]
            .contains { value in
                intensity?.localizedCaseInsensitiveContains(value) == true
                    || normalized.localizedCaseInsensitiveContains(value)
            }

        if containsAny(normalized, ["壶铃摆动", "kettlebell swing"]) {
            return (9.8, "壶铃摆动")
        }
        if containsAny(normalized, ["循环训练", "循环", "circuit", "hiit"]) {
            return vigorous ? (7.5, "高强度循环训练") : (5.0, "中等强度循环训练")
        }
        if containsAny(normalized, ["深蹲", "硬拉", "squat", "deadlift"]) {
            return (5.0, "深蹲或硬拉训练")
        }
        if containsAny(normalized, ["俯卧撑", "引体", "徒手", "弓步", "平板支撑", "push-up", "pull-up", "calisthenics"]) {
            return vigorous ? (6.5, "高强度自重训练") : (3.0, "一般自重训练")
        }
        if containsAny(normalized, ["登阶机", "爬楼机", "stair treadmill", "stairmaster"]) {
            return (9.3, "登阶机训练")
        }
        if containsAny(normalized, ["划船机", "rowing"]) {
            return vigorous ? (7.3, "高强度划船机") : (5.0, "中等强度划船机")
        }
        if containsAny(normalized, ["椭圆机", "elliptical"]) {
            return vigorous ? (9.0, "高强度椭圆机") : (5.0, "中等强度椭圆机")
        }
        if containsAny(normalized, ["单车", "自行车", "动感单车", "cycling", "bike"]) {
            return (6.8, "一般室内单车")
        }
        if containsAny(normalized, ["跑步", "慢跑", "跑步机", "running", "jogging", "treadmill"]) {
            return (5.5, "一般健身房有氧训练")
        }
        return vigorous ? (6.0, "高强度力量训练") : (3.5, "一般抗阻训练")
    }

    private static func containsAny(_ source: String, _ candidates: [String]) -> Bool {
        candidates.contains { source.localizedCaseInsensitiveContains($0) }
    }
}
