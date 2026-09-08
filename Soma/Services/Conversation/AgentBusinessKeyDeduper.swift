import Foundation
import SwiftData

/// ADR 0049：跨 Turn 业务级重复识别。命中时返回既有记录 ID，不静默合并。
enum AgentBusinessKeyDeduper {
    static func matchingWorkout(
        exerciseID: UUID,
        date: Date,
        setEntries: [WorkoutSetEvidence]?,
        sets: Int?,
        reps: Int?,
        weight: Double?,
        excludingTurnID: UUID?,
        in context: ModelContext
    ) -> WorkoutEntry? {
        let day = Calendar.current.startOfDay(for: date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        let fingerprint = workoutFingerprint(
            setEntries: setEntries,
            sets: sets,
            reps: reps,
            weight: weight
        )
        let targetExerciseID: UUID? = exerciseID
        let workouts = (
            try? context.fetch(
                FetchDescriptor<WorkoutEntry>(
                    predicate: #Predicate {
                        $0.externalSource == nil
                            && $0.exerciseID == targetExerciseID
                            && $0.date >= day
                            && $0.date < nextDay
                    },
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            )
        ) ?? []
        return workouts.first { entry in
            guard entry.sourceTurnID != excludingTurnID
            else {
                return false
            }
            return workoutFingerprint(
                setEntries: entry.setEntries,
                sets: entry.sets,
                reps: entry.reps,
                weight: entry.representativeWeight
            ) == fingerprint
        }
    }

    static func matchingMeal(
        title: String,
        calories: Int,
        date: Date,
        excludingTurnID: UUID?,
        in context: ModelContext
    ) -> MealEntry? {
        let day = Calendar.current.startOfDay(for: date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let targetCalories: Int? = calories
        let meals = (
            try? context.fetch(
                FetchDescriptor<MealEntry>(
                    predicate: #Predicate {
                        $0.date >= day
                            && $0.date < nextDay
                            && $0.calories == targetCalories
                    },
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            )
        ) ?? []
        return meals.first { entry in
            guard entry.sourceTurnID != excludingTurnID
            else {
                return false
            }
            return entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == normalizedTitle
        }
    }

    static func matchingBody(
        weight: Double?,
        bodyFat: Double?,
        date: Date,
        excludingTurnID: UUID?,
        in context: ModelContext
    ) -> BodyEntry? {
        let day = Calendar.current.startOfDay(for: date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        let bodies = (
            try? context.fetch(
                FetchDescriptor<BodyEntry>(
                    predicate: #Predicate {
                        $0.externalSource == nil
                            && $0.date >= day
                            && $0.date < nextDay
                    },
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            )
        ) ?? []
        return bodies.first { entry in
            guard entry.sourceTurnID != excludingTurnID
            else {
                return false
            }
            return nearEqual(entry.weight, weight)
                && nearEqual(entry.bodyFat, bodyFat)
        }
    }

    static func suspectedDuplicateMessage(
        kind: String,
        recordID: Int64
    ) -> String {
        "疑似重复\(kind)记录\(AgentFacingRecordID.trailing(recordID))。如需修改请使用对应 update 工具；如确为新记录请说明差异后再写入。"
    }

    private static func workoutFingerprint(
        setEntries: [WorkoutSetEvidence]?,
        sets: Int?,
        reps: Int?,
        weight: Double?
    ) -> String {
        if let setEntries, !setEntries.isEmpty {
            let parts = setEntries.map { entry in
                let repsText = entry.reps.map(String.init) ?? "-"
                let weightText = entry.externalWeightKG
                    .map { String(format: "%.3f", $0) } ?? "-"
                return "\(repsText)x\(weightText)"
            }
            return "sets:\(parts.joined(separator: "|"))"
        }
        return "scalar:\(sets.map(String.init) ?? "-")|\(reps.map(String.init) ?? "-")|\(weight.map { String(format: "%.3f", $0) } ?? "-")"
    }

    private static func nearEqual(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case let (left?, right?):
            abs(left - right) < 0.000_5
        default:
            false
        }
    }
}
