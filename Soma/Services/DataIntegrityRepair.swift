import Foundation
import SwiftData

@MainActor
enum DataIntegrityRepair {
    static func removeUnsupportedInferences(in context: ModelContext) {
        let workouts = (try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? []
        var changed = false

        for workout in workouts
            where workout.mediaKind == .none && !workout.notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        {
            let source = workout.notes.lowercased()
            let hasCompactSets = source.range(
                of: #"\d+\s*[x×*]\s*\d+"#,
                options: .regularExpression
            ) != nil

            if workout.sets != nil,
               !hasCompactSets,
               !source.contains("组")
            {
                workout.sets = nil
                changed = true
            }
            if workout.reps != nil,
               !hasCompactSets,
               !source.contains("次")
            {
                workout.reps = nil
                changed = true
            }
            if workout.weight != nil, !hasExplicitWeight(in: source) {
                workout.weight = nil
                changed = true
            }
            if workout.restSeconds != nil, !hasExplicitRest(in: source) {
                workout.restSeconds = nil
                changed = true
            }
            if workout.durationMinutes != nil, !hasExplicitDuration(in: source) {
                workout.durationMinutes = nil
                changed = true
            }
            if workout.formScore != nil {
                workout.formScore = nil
                changed = true
            }
            if workout.intensity != nil,
               !["偏轻", "适中", "偏重"].contains(where: source.contains)
            {
                workout.intensity = nil
                changed = true
            }
            if let feedback = workout.feedback,
               isPlaceholderFeedback(feedback)
            {
                workout.feedback = nil
                changed = true
            }
        }

        let bodyEntries = (try? context.fetch(FetchDescriptor<BodyEntry>())) ?? []
        for entry in bodyEntries
            where entry.imagePath == nil && !entry.notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        {
            if entry.weight != nil, !hasExplicitWeight(in: entry.notes.lowercased()) {
                entry.weight = nil
                changed = true
            }
        }

        if changed {
            try? context.save()
        }
    }

    static func migrateLegacyWorkoutSets(in context: ModelContext) {
        let workouts = (try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? []
        var changed = false
        for workout in workouts
            where workout.setEntriesData.isEmpty && workout.sets != nil
        {
            guard let count = workout.sets, count > 0 else { continue }
            let reps = workout.reps
            let weight = workout.weight
            workout.setEntries = (0 ..< count).map { _ in
                WorkoutSetEvidence(reps: reps, externalWeightKG: weight)
            }
            changed = true
        }
        if changed {
            try? context.save()
        }
    }

    private static func hasExplicitWeight(in source: String) -> Bool {
        source.contains("自重")
            || source.range(
                of: #"\d+(?:\.\d+)?\s*(?:kg|公斤)"#,
                options: .regularExpression
            ) != nil
    }

    private static func hasExplicitRest(in source: String) -> Bool {
        source.contains("间歇")
            || source.contains("休息")
            || source.contains("rest")
    }

    private static func hasExplicitDuration(in source: String) -> Bool {
        source.contains("分钟")
            || source.contains("小时")
            || source.range(
                of: #"\d+(?:\.\d+)?\s*(?:min|mins|hour|hours)"#,
                options: .regularExpression
            ) != nil
    }

    private static func isPlaceholderFeedback(_ feedback: String) -> Bool {
        let normalized = feedback.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "用户记录",
            "来自用户记录",
            "已记录",
            "来自对话",
            "user record",
            "recorded"
        ].contains(normalized)
    }
}
