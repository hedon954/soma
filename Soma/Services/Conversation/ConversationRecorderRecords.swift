import Foundation
import SwiftData

@MainActor
extension ConversationRecorder {
    static func recordWorkout(
        _ arguments: AgentToolArguments,
        sourceText: String,
        sourceDate: Date = .now,
        sourceSessionID: UUID? = nil,
        sourceTurnID: UUID? = nil,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference] = [],
        in context: ModelContext
    ) -> AgentToolResult {
        try? BusinessIDAllocator.assignMissingIDs(in: context)
        let definition: ExerciseDefinition
        do {
            definition = try resolveExercise(
                from: arguments,
                allowCreate: true,
                in: context
            )
        } catch {
            return .failure(error.localizedDescription)
        }
        let exercise = definition.canonicalName
        let setEntries = workoutSetEntries(from: arguments)
        if let error = workoutSetValidationError(setEntries) {
            return .failure(error)
        }
        if let rest = arguments.restSeconds, !(0 ... 3600).contains(rest) {
            return .failure("rest_seconds 必须在 0 到 3600 之间。")
        }
        if let duration = arguments.durationMinutes, !(0 ... 1440).contains(duration) {
            return .failure("duration_minutes 必须在 0 到 1440 之间。")
        }
        if let score = arguments.formScore, !(0 ... 100).contains(score) {
            return .failure("form_score 必须在 0 到 100 之间。")
        }

        let sets = setEntries?.count ?? arguments.sets
        let reps = representativeReps(in: setEntries) ?? arguments.reps
        let durationMinutes = WorkoutCalorieCalculator.sanitizedActualDurationMinutes(
            arguments.durationMinutes,
            sets: sets,
            reps: reps,
            restSeconds: arguments.restSeconds
        )
        let calorieEstimate = WorkoutCalorieCalculator.estimate(
            exercise: exercise,
            intensity: arguments.intensity,
            durationMinutes: durationMinutes,
            sets: sets,
            reps: reps,
            restSeconds: arguments.restSeconds,
            weightKG: WorkoutCalorieCalculator.currentReferenceWeight(in: context)
        )
        let resolvedMedia = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaKind,
            legacyPath: mediaPath
        )
        if let duplicate = AgentBusinessKeyDeduper.matchingWorkout(
            exerciseID: definition.id,
            date: sourceDate,
            setEntries: setEntries,
            sets: arguments.sets,
            reps: arguments.reps,
            weight: arguments.weight,
            excludingTurnID: sourceTurnID,
            in: context
        ) {
            return .success(
                AgentBusinessKeyDeduper.suspectedDuplicateMessage(
                    kind: "训练",
                    recordID: duplicate.businessID ?? 0
                ),
                recordRefs: [workoutReference(duplicate)],
                recordType: .workout
            )
        }
        let created = WorkoutEntry(
            date: sourceDate,
            exercise: exercise,
            exerciseID: definition.id,
            sets: arguments.sets,
            reps: arguments.reps,
            weight: arguments.weight,
            setEntries: setEntries,
            restSeconds: arguments.restSeconds,
            durationMinutes: durationMinutes,
            notes: sourceText,
            mediaKind: mediaKind,
            mediaPath: mediaPath,
            mediaAttachments: resolvedMedia,
            formScore: arguments.formScore,
            intensity: arguments.intensity?.trimmed.nilIfEmpty,
            feedback: arguments.feedback?.trimmed.nilIfEmpty,
            estimatedCalories: calorieEstimate?.calories,
            calorieMET: calorieEstimate?.met,
            calorieDurationMinutes: calorieEstimate?.durationMinutes,
            calorieDurationEstimated: calorieEstimate?.durationWasEstimated ?? false,
            sourceTurnID: sourceTurnID,
            sourceSessionID: sourceSessionID
        )
        context.insert(created)
        created.exerciseDefinition = definition
        try? BusinessIDAllocator.assign(
            created,
            namespace: "workout",
            in: context
        )
        try? context.save()
        let entry = created
        var summary = [exercise]
        if let setEntries, !setEntries.isEmpty {
            summary.append(workoutSetSummary(setEntries))
        } else {
            if let sets = arguments.sets {
                summary.append("\(sets) 组")
            }
            if let reps = arguments.reps {
                summary.append("\(reps) 次")
            }
            if let weight = formatWeight(arguments.weight) {
                summary.append(weight)
            }
        }
        if let rest = arguments.restSeconds {
            summary.append("间歇 \(rest) 秒")
        }
        let calorieSummary = calorieEstimate.map {
            let durationSource = $0.durationWasEstimated
                ? "由组次、间歇和每次约 4 秒动作节奏推算 \($0.durationMinutes.formatted(.number.precision(.fractionLength(0 ... 1)))) 分钟"
                : "按实际记录 \($0.durationMinutes.formatted(.number.precision(.fractionLength(0 ... 1)))) 分钟"
            return "；\(durationSource)，以 \($0.activityLabel) MET \($0.met.formatted(.number.precision(.fractionLength(0 ... 1)))) 估算消耗约 \($0.calories) kcal"
        } ?? {
            let hasUsableDurationInput = arguments.durationMinutes != nil
                || (
                    arguments.sets != nil
                        && arguments.reps != nil
                        && arguments.restSeconds != nil
                )
            guard hasUsableDurationInput else { return "" }
            return "；未估算热量（需要最近体重或个人信息中的参考体重）"
        }()
        return .success(
            "已记录训练：\(summary.joined(separator: "，"))\(calorieSummary)。",
            recordRefs: [workoutReference(entry)],
            recordType: .workout
        )
    }

    static func recordMeal(
        _ arguments: AgentToolArguments,
        sourceText: String,
        sourceDate: Date = .now,
        sourceSessionID: UUID? = nil,
        sourceTurnID: UUID? = nil,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference] = [],
        in context: ModelContext
    ) -> AgentToolResult {
        try? BusinessIDAllocator.assignMissingIDs(in: context)
        guard let title = arguments.title?.trimmed.nilIfEmpty else {
            return .failure("record_meal 缺少 title。")
        }
        if let calories = arguments.calories, !(0 ... 10000).contains(calories) {
            return .failure("calories 必须在 0 到 10000 之间。")
        }
        let macros = [arguments.protein, arguments.carbs, arguments.fat].compactMap { $0 }
        guard macros.allSatisfy({ (0 ... 1000).contains($0) }) else {
            return .failure("蛋白质、碳水和脂肪必须在 0 到 1000g 之间。")
        }
        if let totalSugar = arguments.totalSugar, !(0 ... 1000).contains(totalSugar) {
            return .failure("total_sugar 必须在 0 到 1000g 之间。")
        }
        let glycemic = validatedGlycemicAssessment(arguments)
        if case let .failure(message) = glycemic {
            return .failure(message)
        }
        let items = arguments.items?.map(\.model) ?? []
        guard items.allSatisfy({ item in
            !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && item.calories.map { (0 ... 10000).contains($0) } ?? true
                && [item.protein, item.carbs, item.fat]
                .compactMap { $0 }
                .allSatisfy { (0 ... 1000).contains($0) }
                && (item.totalSugar.map { (0 ... 1000).contains($0) } ?? true)
        }) else {
            return .failure("items 包含空名称或超出范围的营养值。")
        }
        let mealType = MealType(rawValue: arguments.mealType ?? "")
            ?? inferredMealType(at: sourceDate)
        let resolvedMedia = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaKind,
            legacyPath: mediaPath
        )
        let created = MealEntry(
            date: sourceDate,
            mealType: mealType,
            title: title,
            calories: arguments.calories,
            protein: arguments.protein,
            carbs: arguments.carbs,
            fat: arguments.fat,
            totalSugar: arguments.totalSugar,
            items: items,
            nutritionSource: .aiEstimate,
            notes: recordedText(
                sourceText,
                analysis: arguments.note?.trimmed ?? ""
            ),
            imagePath: mediaKind == .image ? mediaPath : nil,
            mediaAttachments: resolvedMedia,
            sourceTurnID: sourceTurnID,
            sourceSessionID: sourceSessionID
        )
        if !items.isEmpty {
            created.replaceItemsAndDeriveTotals(items)
        }
        if case let .success(assessment) = glycemic, let assessment {
            created.glycemicSpeed = assessment.speed
            created.glycemicAssessment = assessment.text
        }
        context.insert(created)
        try? BusinessIDAllocator.assign(
            created,
            namespace: "meal",
            in: context
        )
        try? context.save()
        let caloriesText = created.calories.map { "约 \($0)kcal" } ?? "营养尚未估算"
        return .success(
            "已记录\(mealType.rawValue)：\(title)，\(caloriesText)。",
            data: mealResultData(created),
            recordRefs: [mealReference(created)],
            recordType: .meal
        )
    }

    static func recordBody(
        _ arguments: AgentToolArguments,
        sourceText: String,
        sourceDate: Date = .now,
        sourceSessionID: UUID? = nil,
        sourceTurnID: UUID? = nil,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference] = [],
        in context: ModelContext
    ) -> AgentToolResult {
        try? BusinessIDAllocator.assignMissingIDs(in: context)
        if let weight = arguments.weight, !(0 ... 500).contains(weight) {
            return .failure("weight 必须在 0 到 500kg 之间。")
        }
        if let bodyFat = arguments.bodyFat, !(0 ... 100).contains(bodyFat) {
            return .failure("body_fat 必须在 0 到 100 之间。")
        }
        if let waist = arguments.waist, !(0 ... 300).contains(waist) {
            return .failure("waist 必须在 0 到 300cm 之间。")
        }
        let analysis = [
            arguments.postureNote?.trimmed.nilIfEmpty,
            arguments.safetyNote?.trimmed.nilIfEmpty
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        let resolvedMedia = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaKind,
            legacyPath: mediaPath
        )
        if let duplicate = AgentBusinessKeyDeduper.matchingBody(
            weight: arguments.weight,
            bodyFat: arguments.bodyFat,
            date: sourceDate,
            excludingTurnID: sourceTurnID,
            in: context
        ) {
            return .success(
                AgentBusinessKeyDeduper.suspectedDuplicateMessage(
                    kind: "身体",
                    recordID: duplicate.businessID ?? 0
                ),
                recordRefs: [bodyReference(duplicate)],
                recordType: .body
            )
        }
        let created = BodyEntry(
            date: sourceDate,
            weight: arguments.weight,
            bodyFat: arguments.bodyFat,
            waist: arguments.waist,
            notes: sourceText,
            imagePath: mediaKind == .image ? mediaPath : nil,
            mediaAttachments: resolvedMedia,
            analysis: analysis,
            sourceTurnID: sourceTurnID,
            sourceSessionID: sourceSessionID
        )
        context.insert(created)
        try? BusinessIDAllocator.assign(
            created,
            namespace: "body",
            in: context
        )
        try? context.save()
        let weightSummary = arguments.weight.map { String(format: "%.1fkg", $0) } ?? "未提供体重"
        return .success(
            "已记录身体数据：\(weightSummary)。",
            recordRefs: [bodyReference(created)],
            recordType: .body
        )
    }
}

extension ConversationRecorder {
    static func updateWorkout(
        _ arguments: AgentToolArguments,
        sourceText: String,
        occurredAt: Date? = nil,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) -> AgentToolResult {
        guard let id = recordID(from: arguments) else {
            return .failure("update_workout 需要有效的 record_id。")
        }
        guard let entry = workout(businessID: id, in: context) else {
            return .failure("没有找到指定训练记录，请重新查询。")
        }
        if let occurredAt {
            entry.date = occurredAt
        }
        let setEntries = workoutSetEntries(from: arguments)
        if let error = workoutSetValidationError(setEntries) {
            return .failure(error)
        }
        if let rest = arguments.restSeconds, !(0 ... 3600).contains(rest) {
            return .failure("rest_seconds 必须在 0 到 3600 之间。")
        }
        if let duration = arguments.durationMinutes, !(0 ... 1440).contains(duration) {
            return .failure("duration_minutes 必须在 0 到 1440 之间。")
        }

        if arguments.exerciseID != nil
            || arguments.exerciseName != nil
            || arguments.exercise != nil
        {
            do {
                let definition = try resolveExercise(
                    from: arguments,
                    allowCreate: arguments.exerciseID == nil,
                    in: context
                )
                entry.exerciseID = definition.id
                entry.exerciseDefinition = definition
                entry.exercise = definition.canonicalName
            } catch {
                return .failure(error.localizedDescription)
            }
        }
        if let setEntries {
            entry.setEntries = setEntries
        }
        entry.restSeconds = arguments.restSeconds ?? entry.restSeconds
        if arguments.durationMinutes != nil {
            entry.durationMinutes = WorkoutCalorieCalculator.sanitizedActualDurationMinutes(
                arguments.durationMinutes,
                sets: entry.setCount,
                reps: entry.representativeReps,
                restSeconds: entry.restSeconds
            )
        } else {
            WorkoutCalorieCalculator.sanitizeStoredDurationIfNeeded(
                entry,
                weightKG: WorkoutCalorieCalculator.currentReferenceWeight(in: context)
            )
        }
        entry.formScore = arguments.formScore ?? entry.formScore
        entry.intensity = arguments.intensity?.trimmed.nilIfEmpty ?? entry.intensity
        entry.feedback = arguments.feedback?.trimmed.nilIfEmpty ?? entry.feedback
        entry.notes = RecordMergePolicy.mergedText(entry.notes, sourceText)
        entry.mediaAttachments = RecordMergePolicy.mergedMedia(
            entry.mediaAttachments,
            resolvedMediaAttachments(
                mediaAttachments,
                legacyKind: mediaKind,
                legacyPath: mediaPath
            )
        )
        let estimate = WorkoutCalorieCalculator.estimate(
            exercise: entry.exercise,
            intensity: entry.intensity,
            durationMinutes: entry.durationMinutes,
            sets: entry.setCount,
            reps: entry.representativeReps,
            restSeconds: entry.restSeconds,
            weightKG: WorkoutCalorieCalculator.currentReferenceWeight(in: context)
        )
        entry.estimatedCalories = estimate?.calories
        entry.calorieMET = estimate?.met
        entry.calorieDurationMinutes = estimate?.durationMinutes
        entry.calorieDurationEstimated = estimate?.durationWasEstimated ?? false
        try? context.save()
        return .success(
            "已更新训练 [id:\(entry.businessID ?? 0)]：\(workoutSummary(entry))。",
            recordRefs: [workoutReference(entry)],
            recordType: .workout
        )
    }

    static func updateMeal(
        _ arguments: AgentToolArguments,
        sourceText: String,
        occurredAt: Date? = nil,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) -> AgentToolResult {
        guard let id = recordID(from: arguments) else {
            return .failure("update_meal 需要有效的 record_id。")
        }
        guard let entry = meal(businessID: id, in: context) else {
            return .failure("没有找到指定饮食记录，请重新查询。")
        }
        if let occurredAt {
            entry.date = occurredAt
        }
        if let calories = arguments.calories, !(0 ... 10000).contains(calories) {
            return .failure("calories 必须在 0 到 10000 之间。")
        }
        let macros = [arguments.protein, arguments.carbs, arguments.fat].compactMap { $0 }
        guard macros.allSatisfy({ (0 ... 1000).contains($0) }) else {
            return .failure("蛋白质、碳水和脂肪必须在 0 到 1000g 之间。")
        }
        if let totalSugar = arguments.totalSugar, !(0 ... 1000).contains(totalSugar) {
            return .failure("total_sugar 必须在 0 到 1000g 之间。")
        }
        let glycemic = validatedGlycemicAssessment(arguments)
        if case let .failure(message) = glycemic {
            return .failure(message)
        }
        if let itemInputs = arguments.items {
            let items = itemInputs.map(\.model)
            guard items.allSatisfy({ item in
                !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && item.calories.map { (0 ... 10000).contains($0) } ?? true
                    && [item.protein, item.carbs, item.fat]
                    .compactMap { $0 }
                    .allSatisfy { (0 ... 1000).contains($0) }
                    && (item.totalSugar.map { (0 ... 1000).contains($0) } ?? true)
            }) else {
                return .failure("items 包含空名称或超出范围的营养值。")
            }
            entry.replaceItemsAndDeriveTotals(items)
        }
        if let rawType = arguments.mealType {
            guard let type = MealType(rawValue: rawType) else {
                return .failure("meal_type 必须是早餐、午餐、晚餐或加餐。")
            }
            entry.mealType = type
        }
        entry.title = arguments.title?.trimmed.nilIfEmpty ?? entry.title
        if arguments.items == nil {
            entry.calories = arguments.calories ?? entry.calories
            entry.protein = arguments.protein ?? entry.protein
            entry.carbs = arguments.carbs ?? entry.carbs
            entry.fat = arguments.fat ?? entry.fat
            entry.totalSugar = arguments.totalSugar ?? entry.totalSugar
            if arguments.calories != nil
                || arguments.protein != nil
                || arguments.carbs != nil
                || arguments.fat != nil
                || arguments.totalSugar != nil
            {
                entry.nutritionSource = .aiEstimate
            }
        }
        if case let .success(assessment) = glycemic, let assessment {
            entry.glycemicSpeed = assessment.speed
            entry.glycemicAssessment = assessment.text
        }
        let note = recordedText(
            sourceText,
            analysis: arguments.note?.trimmed ?? ""
        )
        if !note.isEmpty {
            entry.notes = note
        }
        entry.mediaAttachments = RecordMergePolicy.mergedMedia(
            entry.mediaAttachments,
            resolvedMediaAttachments(
                mediaAttachments,
                legacyKind: mediaKind,
                legacyPath: mediaPath
            )
        )
        try? context.save()
        let caloriesText = entry.calories.map { "约 \($0)kcal" } ?? "营养尚未估算"
        return .success(
            "已更新\(entry.mealType.rawValue)：\(entry.title)，\(caloriesText)。",
            data: mealResultData(entry),
            recordRefs: [mealReference(entry)],
            recordType: .meal
        )
    }

    static func updateBody(
        _ arguments: AgentToolArguments,
        sourceText: String,
        occurredAt: Date? = nil,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) -> AgentToolResult {
        guard let id = recordID(from: arguments) else {
            return .failure("update_body 需要有效的 record_id。")
        }
        guard let entry = bodyEntry(businessID: id, in: context) else {
            return .failure("没有找到指定身体记录，请重新查询。")
        }
        if let occurredAt {
            entry.date = occurredAt
        }
        if let weight = arguments.weight, !(0 ... 500).contains(weight) {
            return .failure("weight 必须在 0 到 500kg 之间。")
        }
        if let bodyFat = arguments.bodyFat, !(0 ... 100).contains(bodyFat) {
            return .failure("body_fat 必须在 0 到 100 之间。")
        }
        if let waist = arguments.waist, !(0 ... 300).contains(waist) {
            return .failure("waist 必须在 0 到 300cm 之间。")
        }
        entry.weight = arguments.weight ?? entry.weight
        entry.bodyFat = arguments.bodyFat ?? entry.bodyFat
        entry.waist = arguments.waist ?? entry.waist
        entry.notes = RecordMergePolicy.mergedText(entry.notes, sourceText)
        let analysis = [
            arguments.postureNote?.trimmed.nilIfEmpty,
            arguments.safetyNote?.trimmed.nilIfEmpty
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        if !analysis.isEmpty {
            entry.analysis = analysis
        }
        entry.mediaAttachments = RecordMergePolicy.mergedMedia(
            entry.mediaAttachments,
            resolvedMediaAttachments(
                mediaAttachments,
                legacyKind: mediaKind,
                legacyPath: mediaPath
            )
        )
        try? context.save()
        return .success(
            "已更新身体记录 [id:\(entry.businessID ?? 0)]。",
            recordRefs: [bodyReference(entry)],
            recordType: .body
        )
    }

    static func deleteRecord(
        _ arguments: AgentToolArguments,
        sourceText: String,
        in context: ModelContext
    ) -> AgentToolResult {
        guard RecordDeletionPolicy.hasExplicitIntent(sourceText) else {
            return .failure("只有用户在当前消息明确要求删除时才能删除记录。")
        }
        guard let id = recordID(from: arguments),
              let type = arguments.recordType
        else {
            return .failure("delete_record 需要 record_type 和有效的 record_id。")
        }

        switch type {
        case "workout":
            guard let entry = workout(businessID: id, in: context) else {
                return .failure("没有找到指定训练记录，请重新查询。")
            }
            do {
                try GuidedWorkoutRecordStore.delete(entry, in: context)
            } catch {
                return .failure("删除训练记录失败：\(error.localizedDescription)")
            }
        case "meal":
            guard let entry = meal(businessID: id, in: context) else {
                return .failure("没有找到指定饮食记录，请重新查询。")
            }
            context.delete(entry)
        case "body":
            guard let entry = bodyEntry(businessID: id, in: context) else {
                return .failure("没有找到指定身体记录，请重新查询。")
            }
            context.delete(entry)
        default:
            return .failure("record_type 只支持 workout、meal 或 body。")
        }
        try? context.save()
        return .success("已删除指定\(type)记录；聊天原文与共享媒体仍然保留。")
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
