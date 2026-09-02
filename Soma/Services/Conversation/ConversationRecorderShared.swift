import Foundation
import SwiftData

@MainActor
extension ConversationRecorder {
    /// 餐次按这条记录真正发生的时刻推断。补记昨天午餐时不能用现在的钟点，
    /// 否则夜里补记会被标成夜宵。
    static func inferredMealType(at date: Date) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 5 ..< 11: .breakfast
        case 11 ..< 14: .lunch
        case 14 ..< 17: .afternoonSnack
        case 17 ..< 22: .dinner
        default: .snack
        }
    }

    /// 餐次只有在用户原话明确出现时才覆盖确定性的时间判断。Tool 参数是模型输出，
    /// 不能把模型的惯性猜测当成用户事实。多次纠正时采用最后一次出现的餐次。
    static func explicitMealType(in sourceText: String) -> MealType? {
        MealType.allCases.compactMap { type in
            sourceText.range(of: type.rawValue, options: .backwards).map {
                (type, $0.lowerBound)
            }
        }.max { lhs, rhs in
            lhs.1 < rhs.1
        }?.0
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
        from arguments: AgentToolArguments,
        exercise: ExerciseDefinition? = nil
    ) -> [WorkoutSetEvidence]? {
        if let entries = arguments.setEntries {
            return entries.map {
                let targetKind = $0.targetKind
                    ?? arguments.targetKind
                    ?? ExerciseLoggingProfile.resolvedTargetKind(
                        exercise: exercise,
                        reps: $0.reps,
                        durationSeconds: $0.durationSeconds
                    )
                return WorkoutSetEvidence(
                    logicalSetIndex: $0.logicalSetIndex,
                    side: $0.side,
                    targetKind: targetKind,
                    reps: targetKind == .repetitions ? $0.reps : nil,
                    durationSeconds: targetKind == .duration ? $0.durationSeconds : nil,
                    externalWeightKG: $0.externalWeightKG,
                    restSeconds: $0.restSeconds
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
            if let seconds = entry.durationSeconds, !(1 ... 86400).contains(seconds) {
                return "第 \(index + 1) 组 duration_seconds 必须在 1 到 86400 之间。"
            }
            if entry.reps != nil, entry.durationSeconds != nil {
                return "第 \(index + 1) 组 reps 与 duration_seconds 只能提供一个。"
            }
            if let weight = entry.externalWeightKG, !(0 ... 1000).contains(weight) {
                return "第 \(index + 1) 组 external_weight_kg 必须在 0 到 1000kg 之间。"
            }
            if let logicalSetIndex = entry.logicalSetIndex,
               !(1 ... 1000).contains(logicalSetIndex)
            {
                return "第 \(index + 1) 条 logical_set_index 必须在 1 到 1000 之间。"
            }
            if let rest = entry.restSeconds, !(0 ... 3600).contains(rest) {
                return "第 \(index + 1) 条 rest_seconds 必须在 0 到 3600 之间。"
            }
        }
        return nil
    }

    struct WorkoutProfileValidationFailure {
        let message: String
        let field: String
        let expected: String
    }

    static func workoutProfileValidationFailure(
        arguments: AgentToolArguments,
        entries: [WorkoutSetEvidence]?
    ) -> WorkoutProfileValidationFailure? {
        guard let entries, !entries.isEmpty else { return nil }
        if let targetKind = arguments.targetKind,
           let conflictIndex = entries.firstIndex(where: { $0.targetKind != targetKind })
        {
            return .init(
                message: "set_entries 的 target_kind 必须与训练 target_kind 一致。",
                field: "set_entries[\(conflictIndex)].target_kind",
                expected: targetKind.rawValue
            )
        }
        guard let laterality = arguments.laterality else { return nil }
        let sides = Set(entries.map { $0.side ?? .none })
        switch laterality {
        case .none:
            if sides.contains(.left) || sides.contains(.right) {
                return .init(
                    message: "laterality=none 不能保存 left/right effort；左右各做请使用 both。",
                    field: "laterality",
                    expected: ExerciseLaterality.both.rawValue
                )
            }
        case .left:
            if sides != [.left] {
                return .init(
                    message: "laterality=left 只能保存 left effort。",
                    field: "set_entries.side",
                    expected: WorkoutEffortSide.left.rawValue
                )
            }
        case .right:
            if sides != [.right] {
                return .init(
                    message: "laterality=right 只能保存 right effort。",
                    field: "set_entries.side",
                    expected: WorkoutEffortSide.right.rawValue
                )
            }
        case .both:
            let draft = WorkoutRecordDraft(evidence: entries)
            if let conflict = draft.groups.first(where: {
                Set($0.efforts.compactMap(\.side)) != [.left, .right]
            }) {
                return .init(
                    message: "laterality=both 的每个 logical_set_index 都必须各有一条 left 和 right effort。",
                    field: "set_entries.logical_set_index",
                    expected: "paired left/right efforts for logical set \(conflict.logicalSetIndex ?? 0)"
                )
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
            switch (entry.externalWeightKG, entry.reps, entry.durationSeconds) {
            case let (.some(weight), .some(reps), _):
                "\(formatWeight(weight) ?? "\(weight)kg") × \(reps)次"
            case let (.some(weight), _, .some(seconds)):
                "\(formatWeight(weight) ?? "\(weight)kg") × \(seconds)秒"
            case let (.some(weight), .none, .none):
                "第\(index + 1)组 \(formatWeight(weight) ?? "\(weight)kg")"
            case let (.none, .some(reps), _):
                "第\(index + 1)组 \(reps)次"
            case let (.none, _, .some(seconds)):
                "第\(index + 1)组 \(seconds)秒"
            case (.none, .none, .none):
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
        if profile.biologicalSex != .unspecified {
            parts.append("生理性别 \(profile.biologicalSex.rawValue)")
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

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
