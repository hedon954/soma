import Foundation
import SwiftData

@MainActor
extension ConversationRecorder {
    /// 餐次按这条记录真正发生的时刻推断。补记昨天午餐时不能用现在的钟点，
    /// 否则夜里补记会被标成夜宵。
    static func inferredMealType(at date: Date) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 5 ..< 11: .breakfast
        case 11 ..< 16: .lunch
        case 16 ..< 22: .dinner
        default: .snack
        }
    }

    static func recordID(
        from arguments: AgentToolArguments
    ) -> Int64? {
        arguments.recordID
    }

    static func resolveExercise(
        from arguments: AgentToolArguments,
        allowCreate: Bool,
        in context: ModelContext
    ) throws -> ExerciseDefinition {
        let businessID = arguments.exerciseID
        let rawName = (
            arguments.exerciseName
                ?? arguments.exercise
        )?.trimmed.nilIfEmpty
        guard businessID == nil || rawName == nil else {
            throw ExerciseLibraryError.ambiguousReference
        }
        if let businessID {
            return try ExerciseLibraryStore.definition(
                businessID: businessID,
                in: context
            )
        }
        guard allowCreate, let rawName else {
            throw ExerciseLibraryError.emptyName
        }
        return try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: rawName,
            in: context
        )
    }

    static func businessIDValue(_ id: Int64?) -> AgentJSONValue {
        id.map { .number(Double($0)) } ?? .null
    }

    static func formatWeight(_ weight: Double?) -> String? {
        guard let weight else { return nil }
        return weight == 0
            ? "自重"
            : "\(weight.formatted(.number.precision(.fractionLength(0 ... 1))))kg"
    }

    static func workoutSetEntries(
        from arguments: AgentToolArguments
    ) -> [WorkoutSetEvidence]? {
        if let entries = arguments.setEntries {
            return entries.map {
                WorkoutSetEvidence(
                    reps: $0.reps,
                    externalWeightKG: $0.externalWeightKG
                )
            }
        }
        return legacyWorkoutSetEntries(
            sets: arguments.sets,
            reps: arguments.reps,
            weight: arguments.weight
        )
    }

    static func legacyWorkoutSetEntries(
        sets: Int?,
        reps: Int?,
        weight: Double?
    ) -> [WorkoutSetEvidence]? {
        guard let sets else { return nil }
        return (0 ..< max(sets, 0)).map { _ in
            WorkoutSetEvidence(reps: reps, externalWeightKG: weight)
        }
    }

    static func workoutSetValidationError(
        _ entries: [WorkoutSetEvidence]?
    ) -> String? {
        guard let entries else { return nil }
        guard entries.count <= 100 else {
            return "set_entries 最多包含 100 组。"
        }
        for (index, entry) in entries.enumerated() {
            if let reps = entry.reps, !(1 ... 1000).contains(reps) {
                return "第 \(index + 1) 组 reps 必须在 1 到 1000 之间。"
            }
            if let weight = entry.externalWeightKG, !(0 ... 1000).contains(weight) {
                return "第 \(index + 1) 组 external_weight_kg 必须在 0 到 1000kg 之间。"
            }
        }
        return nil
    }

    static func representativeReps(
        in entries: [WorkoutSetEvidence]?
    ) -> Int? {
        guard let entries, !entries.isEmpty else { return nil }
        let values = entries.compactMap(\.reps)
        guard values.count == entries.count, Set(values).count == 1 else {
            return nil
        }
        return values.first
    }

    static func workoutSetSummary(
        _ entries: [WorkoutSetEvidence]
    ) -> String {
        entries.enumerated().map { index, entry in
            switch (entry.externalWeightKG, entry.reps) {
            case let (.some(weight), .some(reps)):
                "\(formatWeight(weight) ?? "\(weight)kg") × \(reps)次"
            case let (.some(weight), .none):
                "第\(index + 1)组 \(formatWeight(weight) ?? "\(weight)kg")"
            case let (.none, .some(reps)):
                "第\(index + 1)组 \(reps)次"
            case (.none, .none):
                "第\(index + 1)组"
            }
        }.joined(separator: "，")
    }

    static func workoutSummary(_ workout: WorkoutEntry) -> String {
        var parts = [workout.exercise]
        if let setEvidenceSummary = workout.setEvidenceSummary {
            parts.append(setEvidenceSummary)
        } else if let sets = workout.sets, let reps = workout.reps {
            parts.append("\(sets)×\(reps)")
        } else {
            if let sets = workout.sets {
                parts.append("\(sets) 组")
            }
            if let reps = workout.reps {
                parts.append("\(reps) 次")
            }
        }
        if let weight = formatWeight(workout.weight) {
            parts.append(weight)
        }
        if let rest = workout.restSeconds {
            parts.append("间歇 \(rest) 秒")
        }
        if let calories = workout.estimatedCalories {
            parts.append("约 \(calories)kcal")
        }
        return parts.joined(separator: "，")
    }

    static func profileSummary(_ profile: UserProfile) -> String {
        var parts: [String] = []
        if !profile.displayName.isEmpty {
            parts.append(profile.displayName)
        }
        if let birthDate = profile.birthDate {
            parts.append("出生日期 \(birthDate.formatted(date: .numeric, time: .omitted))")
        }
        if let currentAge = profile.currentAge {
            parts.append("当前 \(currentAge) 岁")
        }
        if let height = profile.height {
            parts.append("\(height.formatted(.number.precision(.fractionLength(0 ... 1))))cm")
        }
        if let weight = profile.referenceWeight {
            parts.append("参考体重 \(weight.formatted(.number.precision(.fractionLength(0 ... 1))))kg")
        }
        if !profile.fitnessGoal.isEmpty {
            parts.append("目标：\(profile.fitnessGoal)")
        }
        if !profile.healthNotes.isEmpty {
            parts.append("限制：\(profile.healthNotes)")
        }
        return parts.isEmpty ? "已建立但尚未填写" : parts.joined(separator: "，")
    }

    struct ValidatedGlycemicAssessment {
        var speed: MealGlycemicSpeed
        var text: String
    }

    enum GlycemicAssessmentValidation {
        case success(ValidatedGlycemicAssessment?)
        case failure(String)
    }

    static func validatedGlycemicAssessment(
        _ arguments: AgentToolArguments
    ) -> GlycemicAssessmentValidation {
        let rawSpeed = arguments.glycemicSpeed?.trimmed.nilIfEmpty
        let text = arguments.glycemicAssessment?.trimmed.nilIfEmpty
        guard rawSpeed != nil || text != nil else { return .success(nil) }
        guard let rawSpeed,
              let speed = MealGlycemicSpeed(rawValue: rawSpeed),
              let text
        else {
            return .failure(
                "glycemic_speed 与 glycemic_assessment 必须成对提供，"
                    + "速度只能是 slow、moderate 或 fast。"
            )
        }
        return .success(ValidatedGlycemicAssessment(speed: speed, text: text))
    }

    static func recordedText(_ source: String, analysis: String) -> String {
        [source.isEmpty ? nil : "原始描述：\(source)", analysis.isEmpty ? nil : "AI 估算：\(analysis)"]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    static func resolvedMediaAttachments(
        _ attachments: [MediaAttachmentReference],
        legacyKind: MediaKind,
        legacyPath: String?
    ) -> [MediaAttachmentReference] {
        if !attachments.isEmpty {
            return attachments
        }
        guard legacyKind != .none, let legacyPath else { return [] }
        return [MediaAttachmentReference(kind: legacyKind, path: legacyPath)]
    }
}
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
