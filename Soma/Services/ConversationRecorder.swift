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
        if let durationMinutes, durationMinutes > 0 {
            duration = (Double(durationMinutes), false)
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

    @MainActor
    static func currentReferenceWeight(in context: ModelContext) -> Double? {
        let recentBodyEntries = (try? context.fetch(FetchDescriptor<BodyEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        if let weight = recentBodyEntries.compactMap(\.weight).first, weight > 0 {
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

@MainActor
enum ConversationRecorder {
    static func apply(
        _ result: ConversationResult,
        sourceText: String,
        sourceDate: Date = .now,
        sourceSessionID: UUID? = nil,
        sourceTurnID: UUID? = nil,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference] = [],
        gyms: [GymProfile],
        equipment: [GymEquipment],
        in context: ModelContext
    ) -> String {
        switch result.intent {
        case .gym:
            recordGym(
                result,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                gyms: gyms,
                equipment: equipment,
                in: context
            )
        case .meal:
            recordMeal(
                result,
                sourceText: sourceText,
                sourceDate: sourceDate,
                sourceSessionID: sourceSessionID,
                sourceTurnID: sourceTurnID,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .body:
            recordBody(
                result,
                sourceText: sourceText,
                sourceDate: sourceDate,
                sourceSessionID: sourceSessionID,
                sourceTurnID: sourceTurnID,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .workout:
            recordWorkout(
                result,
                sourceText: sourceText,
                sourceDate: sourceDate,
                sourceSessionID: sourceSessionID,
                sourceTurnID: sourceTurnID,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .switchGym:
            switchGym(result, gyms: gyms, in: context)
        case .coach:
            break
        }
        try? context.save()
        return result.reply
    }

    static func executeAgentTool(
        _ call: AgentToolCall,
        sourceText: String,
        sourceDate: Date = .now,
        sourceSessionID: UUID? = nil,
        sourceTurnID: UUID? = nil,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference] = [],
        preferredGymID: UUID? = nil,
        in context: ModelContext
    ) -> AgentToolResult {
        switch call.name {
        case .loadSkill:
            .failure("load_skill 应由 Agent 运行时处理。")
        case .queryUserData:
            queryUserData(
                call.arguments,
                preferredGymID: preferredGymID,
                in: context
            )
        case .recordWorkout:
            recordWorkout(
                call.arguments,
                sourceText: sourceText,
                sourceDate: sourceDate,
                sourceSessionID: sourceSessionID,
                sourceTurnID: sourceTurnID,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .recordMeal:
            recordMeal(
                call.arguments,
                sourceText: sourceText,
                sourceDate: sourceDate,
                sourceSessionID: sourceSessionID,
                sourceTurnID: sourceTurnID,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .recordBody:
            recordBody(
                call.arguments,
                sourceText: sourceText,
                sourceDate: sourceDate,
                sourceSessionID: sourceSessionID,
                sourceTurnID: sourceTurnID,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .updateWorkout:
            updateWorkout(
                call.arguments,
                sourceText: sourceText,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .updateMeal:
            updateMeal(
                call.arguments,
                sourceText: sourceText,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .updateBody:
            updateBody(
                call.arguments,
                sourceText: sourceText,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .deleteRecord:
            deleteRecord(
                call.arguments,
                sourceText: sourceText,
                in: context
            )
        case .updateGym:
            updateGym(
                call.arguments,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .switchGym:
            switchGym(call.arguments, in: context)
        }
    }

    private static func queryUserData(
        _ arguments: AgentToolArguments,
        preferredGymID: UUID?,
        in context: ModelContext
    ) -> AgentToolResult {
        let scope = arguments.scope?.lowercased() ?? "overview"
        let limit = min(max(arguments.limit ?? 5, 1), 20)

        switch scope {
        case "overview":
            let gyms = fetchGyms(in: context)
            let equipment = fetchEquipment(in: context)
            let workouts = fetchWorkouts(in: context)
            let meals = fetchMeals(in: context)
            let body = fetchBodyEntries(in: context)
            let gym = preferredGymID
                .flatMap { id in gyms.first(where: { $0.id == id }) }
                ?? GymSelection.current(in: gyms)
            let equipmentNames = gym.map { target in
                equipment.filter { $0.gymID == target.id }.map(\.name).joined(separator: "、")
            }.flatMap(\.nilIfEmpty) ?? "无"
            let workout = workouts.first.map {
                "[id:\($0.id.uuidString)] \(workoutSummary($0))"
            } ?? "暂无"
            let todayCalories = meals
                .filter { Calendar.current.isDateInToday($0.date) }
                .reduce(0) { $0 + $1.calories }
            let weight = body.first.map {
                let value = $0.weight.map { String(format: "%.1fkg", $0) } ?? "仅体态资料"
                return "[id:\($0.id.uuidString)] \(value)"
            } ?? "暂无"
            let profile = fetchProfiles(in: context).first.map(profileSummary) ?? "暂无"
            let latestMeal = meals.first.map {
                "[id:\($0.id.uuidString)] \($0.mealType.rawValue) \($0.title)"
            } ?? "暂无"
            return .success(
                "个人信息：\(profile)；当前健身房：\(gym?.name ?? "无")；可用器械：\(equipmentNames)；最近训练：\(workout)；最近饮食：\(latestMeal)；今日摄入：\(todayCalories)kcal；最近体重：\(weight)。"
            )

        case "workouts":
            let values = fetchWorkouts(in: context).prefix(limit).map {
                "[id:\($0.id.uuidString)] \($0.date.formatted(date: .abbreviated, time: .omitted)) \(workoutSummary($0))"
            }
            return .success(values.isEmpty ? "暂无训练记录。" : values.joined(separator: "\n"))

        case "meals":
            let values = fetchMeals(in: context).prefix(limit).map {
                "[id:\($0.id.uuidString)] \($0.date.formatted(date: .abbreviated, time: .omitted)) \($0.mealType.rawValue) \($0.title) \($0.calories)kcal"
            }
            return .success(values.isEmpty ? "暂无饮食记录。" : values.joined(separator: "\n"))

        case "body":
            let values = fetchBodyEntries(in: context).prefix(limit).map {
                var metrics: [String] = []
                if let weight = $0.weight {
                    metrics.append(String(format: "%.1fkg", weight))
                }
                if let bodyFat = $0.bodyFat {
                    metrics.append(String(format: "体脂 %.1f%%", bodyFat))
                }
                if let waist = $0.waist {
                    metrics.append(String(format: "腰围 %.1fcm", waist))
                }
                let values = metrics.isEmpty ? "仅记录了体型资料" : metrics.joined(separator: "，")
                return "[id:\($0.id.uuidString)] \($0.date.formatted(date: .abbreviated, time: .omitted)) \(values)"
            }
            return .success(values.isEmpty ? "暂无身体记录。" : values.joined(separator: "\n"))

        case "profile":
            let values = fetchProfiles(in: context).prefix(limit).map(profileSummary)
            return .success(values.isEmpty ? "尚未填写身体信息。" : values.joined(separator: "\n"))

        case "gyms":
            let gyms = fetchGyms(in: context)
            let equipment = fetchEquipment(in: context)
            let values = gyms.prefix(limit).map { gym in
                let names = equipment.filter { $0.gymID == gym.id }.map(\.name).joined(separator: "、")
                return "[id:\(gym.id.uuidString)] \(gym.isCurrent ? "当前：" : "")\(gym.name)；器械：\(names.nilIfEmpty ?? "暂无")"
            }
            return .success(values.isEmpty ? "还没有健身房。" : values.joined(separator: "\n"))

        default:
            return .failure("scope 不支持。可选值：overview、profile、workouts、meals、body、gyms。")
        }
    }

    private static func recordWorkout(
        _ arguments: AgentToolArguments,
        sourceText: String,
        sourceDate: Date,
        sourceSessionID: UUID?,
        sourceTurnID: UUID?,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) -> AgentToolResult {
        guard let exercise = arguments.exercise?.trimmed.nilIfEmpty else {
            return .failure("record_workout 缺少 exercise。")
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
        if let score = arguments.formScore, !(0 ... 100).contains(score) {
            return .failure("form_score 必须在 0 到 100 之间。")
        }

        let calorieEstimate = WorkoutCalorieCalculator.estimate(
            exercise: exercise,
            intensity: arguments.intensity,
            durationMinutes: arguments.durationMinutes,
            sets: setEntries?.count ?? arguments.sets,
            reps: representativeReps(in: setEntries) ?? arguments.reps,
            restSeconds: arguments.restSeconds,
            weightKG: WorkoutCalorieCalculator.currentReferenceWeight(in: context)
        )
        let resolvedMedia = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaKind,
            legacyPath: mediaPath
        )
        let input = WorkoutMergeInput(
            date: sourceDate,
            sessionID: sourceSessionID,
            turnID: sourceTurnID,
            exercise: exercise,
            setEntries: setEntries,
            sets: arguments.sets,
            reps: arguments.reps,
            weight: arguments.weight,
            restSeconds: arguments.restSeconds,
            durationMinutes: arguments.durationMinutes,
            sourceText: sourceText,
            media: resolvedMedia,
            isCorrection: RecordMergePolicy.isCorrectionOrSupplement(sourceText)
        )
        let existing = RecordMergePolicy.workoutCandidate(
            for: input,
            entries: fetchWorkouts(in: context)
        )
        if let existing {
            RecordMergePolicy.mergeWorkout(
                existing,
                input: input,
                formScore: arguments.formScore,
                intensity: arguments.intensity?.trimmed.nilIfEmpty,
                feedback: arguments.feedback?.trimmed.nilIfEmpty,
                calorieEstimate: calorieEstimate
            )
        } else {
            context.insert(WorkoutEntry(
                date: sourceDate,
                exercise: exercise,
                sets: arguments.sets,
                reps: arguments.reps,
                weight: arguments.weight,
                setEntries: setEntries,
                restSeconds: arguments.restSeconds,
                durationMinutes: arguments.durationMinutes,
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
            ))
        }
        try? context.save()
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
            "\(existing == nil ? "已记录" : "已合并更新")训练：\(summary.joined(separator: "，"))\(calorieSummary)。",
            recordType: .workout
        )
    }

    private static func recordMeal(
        _ arguments: AgentToolArguments,
        sourceText: String,
        sourceDate: Date,
        sourceSessionID: UUID?,
        sourceTurnID: UUID?,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) -> AgentToolResult {
        guard let title = arguments.title?.trimmed.nilIfEmpty else {
            return .failure("record_meal 缺少 title。")
        }
        guard let calories = arguments.calories, (0 ... 10000).contains(calories) else {
            return .failure("calories 必须在 0 到 10000 之间。")
        }
        let protein = arguments.protein ?? 0
        let carbs = arguments.carbs ?? 0
        let fat = arguments.fat ?? 0
        guard [protein, carbs, fat].allSatisfy({ (0 ... 1000).contains($0) }) else {
            return .failure("蛋白质、碳水和脂肪必须在 0 到 1000g 之间。")
        }
        let mealType = MealType(rawValue: arguments.mealType ?? "") ?? inferredMealType()
        let resolvedMedia = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaKind,
            legacyPath: mediaPath
        )
        let input = MealMergeInput(
            date: sourceDate,
            sessionID: sourceSessionID,
            turnID: sourceTurnID,
            mealType: mealType,
            title: title,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            sourceText: recordedText(
                sourceText,
                analysis: arguments.note?.trimmed ?? ""
            ),
            media: resolvedMedia,
            isCorrection: RecordMergePolicy.isCorrectionOrSupplement(sourceText)
        )
        let existing = RecordMergePolicy.mealCandidate(
            for: input,
            entries: fetchMeals(in: context)
        )
        if let existing {
            RecordMergePolicy.mergeMeal(existing, input: input)
        } else {
            context.insert(MealEntry(
                date: sourceDate,
                mealType: mealType,
                title: title,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                notes: input.sourceText,
                imagePath: mediaKind == .image ? mediaPath : nil,
                mediaAttachments: resolvedMedia,
                sourceTurnID: sourceTurnID,
                sourceSessionID: sourceSessionID
            ))
        }
        try? context.save()
        return .success(
            "\(existing == nil ? "已记录" : "已合并更新")\(mealType.rawValue)：\(title)，约 \(calories)kcal。",
            recordType: .meal
        )
    }

    private static func recordBody(
        _ arguments: AgentToolArguments,
        sourceText: String,
        sourceDate: Date,
        sourceSessionID: UUID?,
        sourceTurnID: UUID?,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) -> AgentToolResult {
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
        let input = BodyMergeInput(
            date: sourceDate,
            sessionID: sourceSessionID,
            turnID: sourceTurnID,
            weight: arguments.weight,
            bodyFat: arguments.bodyFat,
            waist: arguments.waist,
            sourceText: sourceText,
            media: resolvedMedia,
            isCorrection: RecordMergePolicy.isCorrectionOrSupplement(sourceText)
        )
        let existing = RecordMergePolicy.bodyCandidate(
            for: input,
            entries: fetchBodyEntries(in: context)
        )
        if let existing {
            RecordMergePolicy.mergeBody(existing, input: input, analysis: analysis)
        } else {
            context.insert(BodyEntry(
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
            ))
        }
        try? context.save()
        let weightSummary = arguments.weight.map { String(format: "%.1fkg", $0) } ?? "未提供体重"
        let action = existing == nil ? "已记录" : "已合并更新"
        return .success("\(action)身体数据：\(weightSummary)。", recordType: .body)
    }
}

extension ConversationRecorder {
    private static func updateWorkout(
        _ arguments: AgentToolArguments,
        sourceText: String,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) -> AgentToolResult {
        guard let id = recordID(from: arguments) else {
            return .failure("update_workout 需要有效的 record_id。")
        }
        guard let entry = fetchWorkouts(in: context).first(where: { $0.id == id }) else {
            return .failure("没有找到指定训练记录，请重新查询。")
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

        entry.exercise = arguments.exercise?.trimmed.nilIfEmpty ?? entry.exercise
        if let setEntries {
            entry.setEntries = setEntries
        }
        entry.restSeconds = arguments.restSeconds ?? entry.restSeconds
        entry.durationMinutes = arguments.durationMinutes ?? entry.durationMinutes
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
            "已更新训练 [id:\(entry.id.uuidString)]：\(workoutSummary(entry))。",
            recordType: .workout
        )
    }

    private static func updateMeal(
        _ arguments: AgentToolArguments,
        sourceText: String,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) -> AgentToolResult {
        guard let id = recordID(from: arguments) else {
            return .failure("update_meal 需要有效的 record_id。")
        }
        guard let entry = fetchMeals(in: context).first(where: { $0.id == id }) else {
            return .failure("没有找到指定饮食记录，请重新查询。")
        }
        if let calories = arguments.calories, !(0 ... 10000).contains(calories) {
            return .failure("calories 必须在 0 到 10000 之间。")
        }
        let macros = [arguments.protein, arguments.carbs, arguments.fat].compactMap { $0 }
        guard macros.allSatisfy({ (0 ... 1000).contains($0) }) else {
            return .failure("蛋白质、碳水和脂肪必须在 0 到 1000g 之间。")
        }
        if let rawType = arguments.mealType {
            guard let type = MealType(rawValue: rawType) else {
                return .failure("meal_type 必须是早餐、午餐、晚餐或加餐。")
            }
            entry.mealType = type
        }
        entry.title = arguments.title?.trimmed.nilIfEmpty ?? entry.title
        entry.calories = arguments.calories ?? entry.calories
        entry.protein = arguments.protein ?? entry.protein
        entry.carbs = arguments.carbs ?? entry.carbs
        entry.fat = arguments.fat ?? entry.fat
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
        return .success(
            "已更新\(entry.mealType.rawValue) [id:\(entry.id.uuidString)]：\(entry.title)，约 \(entry.calories)kcal。",
            recordType: .meal
        )
    }

    private static func updateBody(
        _ arguments: AgentToolArguments,
        sourceText: String,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) -> AgentToolResult {
        guard let id = recordID(from: arguments) else {
            return .failure("update_body 需要有效的 record_id。")
        }
        guard let entry = fetchBodyEntries(in: context).first(where: { $0.id == id }) else {
            return .failure("没有找到指定身体记录，请重新查询。")
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
            "已更新身体记录 [id:\(entry.id.uuidString)]。",
            recordType: .body
        )
    }

    private static func deleteRecord(
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
            guard let entry = fetchWorkouts(in: context).first(where: { $0.id == id }) else {
                return .failure("没有找到指定训练记录，请重新查询。")
            }
            context.delete(entry)
        case "meal":
            guard let entry = fetchMeals(in: context).first(where: { $0.id == id }) else {
                return .failure("没有找到指定饮食记录，请重新查询。")
            }
            context.delete(entry)
        case "body":
            guard let entry = fetchBodyEntries(in: context).first(where: { $0.id == id }) else {
                return .failure("没有找到指定身体记录，请重新查询。")
            }
            context.delete(entry)
        default:
            return .failure("record_type 只支持 workout、meal 或 body。")
        }
        try? context.save()
        return .success("已删除指定\(type)记录；聊天原文与共享媒体仍然保留。")
    }

    private static func updateGym(
        _ arguments: AgentToolArguments,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) -> AgentToolResult {
        let gyms = fetchGyms(in: context)
        let requestedName = arguments.gymName?.trimmed.nilIfEmpty
        let target: GymProfile
        if let requestedName,
           let existing = gyms.first(where: {
               $0.name.localizedCaseInsensitiveContains(requestedName)
                   || requestedName.localizedCaseInsensitiveContains($0.name)
           })
        {
            target = existing
        } else if requestedName == nil, let current = GymSelection.current(in: gyms) {
            target = current
        } else {
            target = GymProfile(
                name: requestedName ?? "新健身房",
                notes: "通过 Agent 对话创建",
                isCurrent: true
            )
            GymSelection.activate(target, among: gyms)
            context.insert(target)
        }

        if let summary = arguments.summary?.trimmed.nilIfEmpty {
            target.notes = summary
        }
        let imageAttachments = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaKind,
            legacyPath: mediaPath
        ).filter { $0.kind == .image }
        if let coverPath = imageAttachments.first?.path {
            target.coverImagePath = coverPath
            let existingMedia = (try? context.fetch(FetchDescriptor<GymMedia>())) ?? []
            for attachment in imageAttachments where
                !existingMedia.contains(where: {
                    $0.gymID == target.id && $0.path == attachment.path
                })
            {
                context.insert(GymMedia(gymID: target.id, path: attachment.path))
            }
        }

        let existingEquipment = fetchEquipment(in: context)
        for input in arguments.equipment ?? [] {
            let name = input.name.trimmed
            guard !name.isEmpty else { continue }
            if let existing = existingEquipment.first(where: {
                $0.gymID == target.id
                    && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                existing.category = input.category.trimmed
                existing.capabilities = input.capabilities.trimmed
                existing.confidence = min(max(input.confidence ?? existing.confidence, 0), 1)
                if let imagePath = imageAttachments.first?.path {
                    existing.imagePath = imagePath
                }
            } else {
                context.insert(GymEquipment(
                    gymID: target.id,
                    name: name,
                    category: input.category.trimmed,
                    capabilities: input.capabilities.trimmed,
                    confidence: min(max(input.confidence ?? 0.9, 0), 1),
                    imagePath: imageAttachments.first?.path
                ))
            }
        }
        try? context.save()
        let names = (arguments.equipment ?? []).map(\.name).filter { !$0.isEmpty }
        let detail = names.isEmpty ? "环境信息" : names.joined(separator: "、")
        return .success("已更新健身房「\(target.name)」：\(detail)。", recordType: .gym)
    }

    private static func switchGym(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let name = arguments.gymName?.trimmed.nilIfEmpty else {
            return .failure("switch_gym 缺少 gym_name。")
        }
        let gyms = fetchGyms(in: context)
        guard let target = gyms.first(where: {
            $0.name.localizedCaseInsensitiveContains(name)
                || name.localizedCaseInsensitiveContains($0.name)
        }) else {
            let available = gyms.map(\.name).joined(separator: "、")
            return .failure("没有找到「\(name)」。现有健身房：\(available.nilIfEmpty ?? "无")。")
        }
        GymSelection.activate(target, among: gyms)
        try? context.save()
        return .success("当前健身房已切换为「\(target.name)」。", recordType: .switchGym)
    }

    private static func fetchGyms(in context: ModelContext) -> [GymProfile] {
        (try? context.fetch(FetchDescriptor<GymProfile>(
            sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []
    }

    private static func fetchEquipment(in context: ModelContext) -> [GymEquipment] {
        (try? context.fetch(FetchDescriptor<GymEquipment>(
            sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []
    }

    private static func fetchWorkouts(in context: ModelContext) -> [WorkoutEntry] {
        (try? context.fetch(FetchDescriptor<WorkoutEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
    }

    private static func fetchMeals(in context: ModelContext) -> [MealEntry] {
        (try? context.fetch(FetchDescriptor<MealEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
    }

    private static func fetchBodyEntries(in context: ModelContext) -> [BodyEntry] {
        (try? context.fetch(FetchDescriptor<BodyEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
    }

    private static func fetchProfiles(in context: ModelContext) -> [UserProfile] {
        (try? context.fetch(FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))) ?? []
    }

    private static func inferredMealType() -> MealType {
        switch Calendar.current.component(.hour, from: .now) {
        case 5 ..< 11: .breakfast
        case 11 ..< 16: .lunch
        case 16 ..< 22: .dinner
        default: .snack
        }
    }

    private static func recordID(
        from arguments: AgentToolArguments
    ) -> UUID? {
        arguments.recordID.flatMap(UUID.init(uuidString:))
    }

    private static func formatWeight(_ weight: Double?) -> String? {
        guard let weight else { return nil }
        return weight == 0
            ? "自重"
            : "\(weight.formatted(.number.precision(.fractionLength(0 ... 1))))kg"
    }

    private static func workoutSetEntries(
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

    private static func legacyWorkoutSetEntries(
        sets: Int?,
        reps: Int?,
        weight: Double?
    ) -> [WorkoutSetEvidence]? {
        guard let sets else { return nil }
        return (0 ..< max(sets, 0)).map { _ in
            WorkoutSetEvidence(reps: reps, externalWeightKG: weight)
        }
    }

    private static func workoutSetValidationError(
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

    private static func representativeReps(
        in entries: [WorkoutSetEvidence]?
    ) -> Int? {
        guard let entries, !entries.isEmpty else { return nil }
        let values = entries.compactMap(\.reps)
        guard values.count == entries.count, Set(values).count == 1 else {
            return nil
        }
        return values.first
    }

    private static func workoutSetSummary(
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

    private static func workoutSummary(_ workout: WorkoutEntry) -> String {
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

    private static func profileSummary(_ profile: UserProfile) -> String {
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

    private static func recordGym(
        _ result: ConversationResult,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        gyms: [GymProfile],
        equipment: [GymEquipment],
        in context: ModelContext
    ) {
        guard let analysis = result.gym else { return }
        let target = targetGym(named: result.gymName, gyms: gyms, in: context)
        target.notes = analysis.summary
        let imageAttachments = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaKind,
            legacyPath: mediaPath
        ).filter { $0.kind == .image }
        if let coverPath = imageAttachments.first?.path {
            target.coverImagePath = coverPath
            let existingMedia = (
                try? context.fetch(FetchDescriptor<GymMedia>())
            ) ?? []
            for imageAttachment in imageAttachments where
                !existingMedia.contains(where: {
                    $0.gymID == target.id && $0.path == imageAttachment.path
                })
            {
                context.insert(GymMedia(gymID: target.id, path: imageAttachment.path))
            }
        }
        for item in analysis.equipment {
            let existing = equipment.first {
                $0.gymID == target.id && $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame
            }
            if let existing {
                existing.category = item.category
                existing.capabilities = item.capabilities
                existing.confidence = item.confidence
                if let imagePath = imageAttachments.first?.path {
                    existing.imagePath = imagePath
                }
            } else {
                context.insert(GymEquipment(
                    gymID: target.id,
                    name: item.name,
                    category: item.category,
                    capabilities: item.capabilities,
                    confidence: item.confidence,
                    imagePath: imageAttachments.first?.path
                ))
            }
        }
    }

    private static func targetGym(
        named name: String?,
        gyms: [GymProfile],
        in context: ModelContext
    ) -> GymProfile {
        if let name,
           let match = gyms.first(where: { $0.name.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0.name) })
        {
            GymSelection.activate(match, among: gyms)
            return match
        }
        if let current = GymSelection.current(in: gyms), name == nil {
            return current
        }
        let gym = GymProfile(
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "新健身房",
            notes: "通过 AI 对话创建",
            isCurrent: true
        )
        GymSelection.activate(gym, among: gyms)
        context.insert(gym)
        return gym
    }

    private static func recordMeal(
        _ result: ConversationResult,
        sourceText: String,
        sourceDate: Date,
        sourceSessionID: UUID?,
        sourceTurnID: UUID?,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) {
        guard let meal = result.meal else { return }
        let hour = Calendar.current.component(.hour, from: sourceDate)
        let type: MealType = switch hour {
        case 5 ..< 11: .breakfast
        case 11 ..< 16: .lunch
        case 16 ..< 22: .dinner
        default: .snack
        }
        let resolvedMedia = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaPath == nil ? .none : .image,
            legacyPath: mediaPath
        )
        let input = MealMergeInput(
            date: sourceDate,
            sessionID: sourceSessionID,
            turnID: sourceTurnID,
            mealType: type,
            title: meal.title,
            calories: meal.calories,
            protein: meal.protein,
            carbs: meal.carbs,
            fat: meal.fat,
            sourceText: recordedText(sourceText, analysis: meal.note),
            media: resolvedMedia,
            isCorrection: RecordMergePolicy.isCorrectionOrSupplement(sourceText)
        )
        if let existing = RecordMergePolicy.mealCandidate(
            for: input,
            entries: fetchMeals(in: context)
        ) {
            RecordMergePolicy.mergeMeal(
                existing,
                input: input,
                confidence: meal.confidence
            )
        } else {
            context.insert(MealEntry(
                date: sourceDate,
                mealType: type,
                title: meal.title,
                calories: meal.calories,
                protein: meal.protein,
                carbs: meal.carbs,
                fat: meal.fat,
                notes: input.sourceText,
                imagePath: mediaPath,
                mediaAttachments: resolvedMedia,
                confidence: meal.confidence,
                sourceTurnID: sourceTurnID,
                sourceSessionID: sourceSessionID
            ))
        }
    }

    private static func recordBody(
        _ result: ConversationResult,
        sourceText: String,
        sourceDate: Date,
        sourceSessionID: UUID?,
        sourceTurnID: UUID?,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) {
        guard let body = result.body else { return }
        let resolvedMedia = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaPath == nil ? .none : .image,
            legacyPath: mediaPath
        )
        let input = BodyMergeInput(
            date: sourceDate,
            sessionID: sourceSessionID,
            turnID: sourceTurnID,
            weight: body.estimatedWeight,
            bodyFat: body.estimatedBodyFat,
            waist: nil,
            sourceText: sourceText,
            media: resolvedMedia,
            isCorrection: RecordMergePolicy.isCorrectionOrSupplement(sourceText)
        )
        let analysis = "\(body.postureNote)\n\(body.safetyNote)"
        if let existing = RecordMergePolicy.bodyCandidate(
            for: input,
            entries: fetchBodyEntries(in: context)
        ) {
            RecordMergePolicy.mergeBody(existing, input: input, analysis: analysis)
        } else {
            context.insert(BodyEntry(
                date: sourceDate,
                weight: body.estimatedWeight,
                bodyFat: body.estimatedBodyFat,
                notes: sourceText,
                imagePath: mediaPath,
                mediaAttachments: resolvedMedia,
                analysis: analysis,
                sourceTurnID: sourceTurnID,
                sourceSessionID: sourceSessionID
            ))
        }
    }

    private static func recordWorkout(
        _ result: ConversationResult,
        sourceText: String,
        sourceDate: Date,
        sourceSessionID: UUID?,
        sourceTurnID: UUID?,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) {
        guard let workout = result.workout else { return }
        let setEntries = workout.setEntries ?? legacyWorkoutSetEntries(
            sets: workout.sets,
            reps: workout.reps,
            weight: workout.weight
        )
        let calorieEstimate = WorkoutCalorieCalculator.estimate(
            exercise: workout.exercise,
            intensity: workout.intensity,
            durationMinutes: workout.durationMinutes,
            sets: setEntries?.count ?? workout.sets,
            reps: representativeReps(in: setEntries) ?? workout.reps,
            restSeconds: workout.restSeconds,
            weightKG: WorkoutCalorieCalculator.currentReferenceWeight(in: context)
        )
        let resolvedMedia = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaKind,
            legacyPath: mediaPath
        )
        let input = WorkoutMergeInput(
            date: sourceDate,
            sessionID: sourceSessionID,
            turnID: sourceTurnID,
            exercise: workout.exercise,
            setEntries: setEntries,
            sets: workout.sets,
            reps: workout.reps,
            weight: workout.weight,
            restSeconds: workout.restSeconds,
            durationMinutes: workout.durationMinutes,
            sourceText: sourceText,
            media: resolvedMedia,
            isCorrection: RecordMergePolicy.isCorrectionOrSupplement(sourceText)
        )
        if let existing = RecordMergePolicy.workoutCandidate(
            for: input,
            entries: fetchWorkouts(in: context)
        ) {
            RecordMergePolicy.mergeWorkout(
                existing,
                input: input,
                formScore: workout.formScore,
                intensity: workout.intensity,
                feedback: workout.feedback,
                calorieEstimate: calorieEstimate
            )
        } else {
            context.insert(WorkoutEntry(
                date: sourceDate,
                exercise: workout.exercise,
                sets: workout.sets,
                reps: workout.reps,
                weight: workout.weight,
                setEntries: setEntries,
                restSeconds: workout.restSeconds,
                durationMinutes: workout.durationMinutes,
                notes: sourceText,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: resolvedMedia,
                formScore: workout.formScore,
                intensity: workout.intensity,
                feedback: workout.feedback,
                estimatedCalories: calorieEstimate?.calories,
                calorieMET: calorieEstimate?.met,
                calorieDurationMinutes: calorieEstimate?.durationMinutes,
                calorieDurationEstimated: calorieEstimate?.durationWasEstimated ?? false,
                sourceTurnID: sourceTurnID,
                sourceSessionID: sourceSessionID
            ))
        }
    }

    private static func switchGym(
        _ result: ConversationResult,
        gyms: [GymProfile],
        in context: ModelContext
    ) {
        _ = targetGym(named: result.gymName, gyms: gyms, in: context)
    }

    private static func recordedText(_ source: String, analysis: String) -> String {
        [source.isEmpty ? nil : "原始描述：\(source)", analysis.isEmpty ? nil : "AI 估算：\(analysis)"]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private static func resolvedMediaAttachments(
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

@MainActor
enum DataIntegrityRepair {
    static func finalizeInterruptedAgentTraces(in context: ModelContext) {
        let traces = (try? context.fetch(FetchDescriptor<AgentTrace>())) ?? []
        let interrupted = traces.filter { $0.status == .running }
        let messages = (try? context.fetch(FetchDescriptor<CoachMessage>())) ?? []
        let interruptedMessages = messages.filter { $0.agentStatus == .running }
        guard !interrupted.isEmpty || !interruptedMessages.isEmpty else { return }

        let endedAt = Date()
        let message = "上一次 ReAct Agent 执行未正常结束，可能是 App 被关闭或任务被系统中断。"
        for trace in interrupted {
            trace.apply(.span(AgentTraceSpan(
                kind: .output,
                title: "执行中断",
                status: .failed,
                startedAt: endedAt,
                endedAt: endedAt,
                errorMessage: message
            )))
            trace.apply(.failed(message: message, cancelled: false, at: endedAt))
        }
        for response in interruptedMessages {
            response.agentStatus = .failed
            response.applyAgentEvent(.failed(
                message: message,
                cancelled: false,
                at: endedAt
            ))
            response.text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? message : response.text
            response.replaceAgentEvents(response.agentEvents.map { event in
                guard event.status == .running else { return event }
                var failed = event
                failed.statusRaw = AgentTraceStatus.failed.rawValue
                failed.endedAt = endedAt
                failed.errorMessage = message
                return failed
            })
        }
        try? context.save()
    }

    static func removeUnsupportedInferences(in context: ModelContext) {
        let workouts = (try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? []
        var changed = false

        for workout in workouts
            where workout.mediaKind == .none && !workout.notes.trimmed.isEmpty
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
            where entry.imagePath == nil && !entry.notes.trimmed.isEmpty
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
        let normalized = feedback.trimmed.lowercased()
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
