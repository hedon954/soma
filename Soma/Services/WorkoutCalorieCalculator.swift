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
        let duration: (minutes: Double, estimated: Bool)
        let usableDuration = sanitizedActualDurationMinutes(
            durationMinutes,
            sets: sets,
            reps: reps,
            restSeconds: restSeconds
        )
        if let usableDuration, usableDuration > 0 {
            duration = (Double(usableDuration), false)
        } else {
            guard let estimated = estimatedResistanceDuration(
                sets: sets,
                reps: reps,
                restSeconds: restSeconds
            ) else {
                return nil
            }
            duration = (estimated, true)
        }
        guard
            let weightKG,
            weightKG > 0
        else {
            return nil
        }

        let activity = activity(for: exercise, intensity: intensity)
        let calories = activity.met * weightKG * duration.minutes / 60
        guard calories.isFinite, calories > 0 else { return nil }
        return WorkoutCalorieEstimate(
            calories: Int(calories.rounded()),
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
        guard let duration = guidedDuration(from: evidence),
              let weightKG,
              weightKG > 0
        else {
            return nil
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

    static func guidedDuration(
        from evidence: [WorkoutSetEvidence]
    ) -> (minutes: Double, estimated: Bool)? {
        guard !evidence.isEmpty else { return nil }
        var totalSeconds = 0.0
        var usedRepetitionEstimate = false
        for item in evidence {
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
            case .none:
                if let seconds = item.durationSeconds, seconds > 0 {
                    totalSeconds += Double(seconds)
                } else if let reps = item.reps, reps > 0 {
                    totalSeconds += Double(reps) * estimatedSecondsPerResistanceRep
                    usedRepetitionEstimate = true
                } else {
                    return nil
                }
            }
            if let restSeconds = item.restSeconds, restSeconds >= 0 {
                totalSeconds += Double(restSeconds)
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
        entry.calorieDurationMinutes = estimate?.durationMinutes
        entry.calorieDurationEstimated = estimate?.durationWasEstimated ?? false
        return true
    }

    @MainActor
    static func currentReferenceWeight(in context: ModelContext) -> Double? {
        referenceWeight(at: .now, in: context)
    }

    /// Uses only body measurements known at or before the session start. A
    /// profile reference weight is the explicit fallback when no dated body
    /// measurement exists.
    @MainActor
    static func referenceWeight(
        at date: Date,
        in context: ModelContext
    ) -> Double? {
        let bodyEntries = (try? context.fetch(FetchDescriptor<BodyEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        if let weight = bodyEntries.first(where: {
            $0.date <= date && ($0.weight ?? 0) > 0
        })?.weight {
            return weight
        }
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))) ?? []
        return profiles.compactMap(\.referenceWeight).first(where: { $0 > 0 })
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
