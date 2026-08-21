import Foundation
import SwiftData

@MainActor
enum ConversationRecorder {
    static func executeAgentTool(
        _ call: AgentToolCall,
        sourceText: String,
        sourceDate: Date = .now,
        sourceSessionID: UUID? = nil,
        sourceTurnID: UUID? = nil,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference] = [],
        preferredGymID _: UUID? = nil,
        in context: ModelContext
    ) -> AgentToolResult {
        try? BusinessIDAllocator.assignMissingIDs(in: context)
        let occurredAt: Date?
        if let raw = call.arguments.occurredAt {
            guard let parsed = parsedOccurredAt(raw) else {
                return .failure(
                    "occurred_at 必须是带时区的 ISO-8601 时间。",
                    code: "invalid_argument",
                    field: "occurred_at",
                    expected: "ISO-8601 timestamp with timezone"
                )
            }
            occurredAt = parsed
        } else {
            occurredAt = nil
        }
        let resolvedSourceDate = occurredAt ?? sourceDate
        if call.name.isTypedV3 {
            return executeTypedAgentTool(
                call,
                source: TypedAgentToolSource(
                    text: sourceText,
                    date: resolvedSourceDate,
                    explicitOccurredAt: occurredAt,
                    sessionID: sourceSessionID,
                    turnID: sourceTurnID,
                    mediaKind: mediaKind,
                    mediaPath: mediaPath,
                    mediaAttachments: mediaAttachments
                ),
                in: context
            )
        }
        return switch call.name {
        case .searchExercises, .createExercise, .updateExercise,
             .archiveExercise, .mergeExercises, .listWorkouts,
             .getWorkout, .createWorkout, .updateWorkout, .deleteWorkout, .listMeals,
             .getMeal, .createMeal, .updateMeal, .deleteMeal, .listBodyEntries,
             .getBodyEntry, .createBodyEntry, .deleteBodyEntry,
             .updateBody,
             .listPrograms, .getProgram, .createProgram,
             .createProgramVersion, .archiveProgram, .deleteProgram,
             .startProgram:
            .failure("v3 Tool 路由异常。", code: "internal_error")
        case .loadSkill:
            .failure("load_skill 应由 Agent 运行时处理。")
        case .submitFeedback:
            .failure("submit_feedback 应由 Agent 运行时异步处理。")
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
        case .recordPerformanceAnalysis:
            recordPerformanceAnalysis(
                call.arguments,
                sourceTurnID: sourceTurnID,
                in: context
            )
        }
    }

    static func parsedOccurredAt(_ value: String) -> Date? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.contains("T"),
              normalized.hasSuffix("Z")
              || normalized.dropFirst(10).contains("+")
              || normalized.dropFirst(10).contains("-")
        else {
            return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: normalized)
            ?? ISO8601DateFormatter().date(from: normalized)
    }

    static func queryUserData(
        _ arguments: AgentToolArguments,
        preferredGymID: UUID?,
        in context: ModelContext
    ) -> AgentToolResult {
        try? BusinessIDAllocator.assignMissingIDs(in: context)
        let scope = arguments.scope?.lowercased() ?? "overview"
        let limit = min(max(arguments.limit ?? 3, 1), 10)
        if let failure = queryValidationFailure(scope: scope, arguments: arguments) {
            return failure
        }

        switch scope {
        case "aggregate":
            return AgentUserDataAggregator.aggregate(
                arguments: arguments,
                in: context
            )

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
                "[id:\($0.businessID ?? 0)] \(workoutSummary($0))"
            } ?? "暂无"
            let todayMeals = meals.filter {
                Calendar.current.isDateInToday($0.date)
            }
            let knownTodayCalories = todayMeals.compactMap(\.calories)
            let todayCalories = knownTodayCalories.count == todayMeals.count
                ? "\(knownTodayCalories.reduce(0, +))kcal"
                : "存在未估算记录"
            let weight = body.first.map {
                let value = $0.weight.map { String(format: "%.1fkg", $0) } ?? "仅体态资料"
                return "[id:\($0.businessID ?? 0)] \(value)"
            } ?? "暂无"
            let profile = fetchProfiles(in: context).first.map(profileSummary) ?? "暂无"
            let latestMeal = meals.first.map {
                "[id:\($0.businessID ?? 0)] \($0.mealType.rawValue) \($0.title)"
            } ?? "暂无"
            return .success(
                "个人信息：\(profile)；当前健身房：\(gym?.name ?? "无")；可用器械：\(equipmentNames)；最近训练：\(workout)；最近饮食：\(latestMeal)；今日摄入：\(todayCalories)；最近体重：\(weight)。"
            )

        case "workouts":
            let values = filteredByDate(fetchWorkouts(in: context), arguments: arguments, date: \.date)
                .filter { arguments.recordID == nil || $0.businessID == arguments.recordID }
                .map { entry in
                    var value = [
                        "record_id": businessIDValue(entry.businessID),
                        "date": .string(entry.date.ISO8601Format()),
                        "title": .string(entry.exercise),
                        "summary": .string(workoutSummary(entry))
                    ] as [String: AgentJSONValue]
                    if arguments.projection == "detail" {
                        let definitions = (try? context.fetch(
                            FetchDescriptor<ExerciseDefinition>()
                        )) ?? []
                        let definitionID = entry.exerciseID.flatMap { internalID in
                            definitions.first(where: { $0.id == internalID })?.businessID
                        }
                        value["exercise_id"] = businessIDValue(definitionID)
                        value["set_entries"] = .array(entry.setEntries.map { set in
                            .object([
                                "reps": set.reps.map { .number(Double($0)) } ?? .null,
                                "external_weight_kg": set.externalWeightKG
                                    .map(AgentJSONValue.number) ?? .null
                            ])
                        })
                        value["rest_seconds"] = entry.restSeconds
                            .map { .number(Double($0)) } ?? .null
                        value["duration_minutes"] = entry.durationMinutes
                            .map { .number(Double($0)) } ?? .null
                        value["feedback"] = entry.feedback?.nilIfEmpty
                            .map(AgentJSONValue.string) ?? .null
                    }
                    return value
                }
            return pagedResult(values, noun: "训练记录", arguments: arguments, limit: limit)

        case "meals":
            let values = filteredByDate(fetchMeals(in: context), arguments: arguments, date: \.date)
                .filter { arguments.recordID == nil || $0.businessID == arguments.recordID }
                .map { entry in
                    var value = [
                        "record_id": businessIDValue(entry.businessID),
                        "date": .string(entry.date.ISO8601Format()),
                        "meal_type": .string(entry.mealType.rawValue),
                        "title": .string(entry.title),
                        "calories": entry.calories.map { .number(Double($0)) } ?? .null
                    ] as [String: AgentJSONValue]
                    if arguments.projection == "detail" {
                        value["protein"] = entry.protein.map(AgentJSONValue.number) ?? .null
                        value["carbs"] = entry.carbs.map(AgentJSONValue.number) ?? .null
                        value["fat"] = entry.fat.map(AgentJSONValue.number) ?? .null
                        value["total_sugar"] = entry.totalSugar
                            .map(AgentJSONValue.number) ?? .null
                        value["glycemic_speed"] = entry.glycemicSpeedRaw
                            .map(AgentJSONValue.string) ?? .null
                        value["glycemic_assessment"] = entry.glycemicAssessment.nilIfEmpty
                            .map(AgentJSONValue.string) ?? .null
                        value["note"] = entry.notes.nilIfEmpty
                            .map(AgentJSONValue.string) ?? .null
                        let encodedItems: [AgentJSONValue] = entry.items.map { item in
                            .object([
                                "id": .string(item.id.uuidString),
                                "name": .string(item.name),
                                "portion_description": item.portionDescription
                                    .map(AgentJSONValue.string) ?? .null,
                                "calories": item.calories
                                    .map { .number(Double($0)) } ?? .null,
                                "protein": item.protein.map(AgentJSONValue.number) ?? .null,
                                "carbs": item.carbs.map(AgentJSONValue.number) ?? .null,
                                "fat": item.fat.map(AgentJSONValue.number) ?? .null,
                                "total_sugar": item.totalSugar
                                    .map(AgentJSONValue.number) ?? .null
                            ])
                        }
                        value["items"] = .array(encodedItems)
                    }
                    return value
                }
            return pagedResult(values, noun: "饮食记录", arguments: arguments, limit: limit)

        case "body":
            let values = filteredByDate(
                fetchBodyEntries(in: context),
                arguments: arguments,
                date: \.date
            )
            .filter { arguments.recordID == nil || $0.businessID == arguments.recordID }
            .map { entry in
                var value = [
                    "record_id": businessIDValue(entry.businessID),
                    "date": .string(entry.date.ISO8601Format()),
                    "weight": entry.weight.map(AgentJSONValue.number) ?? .null,
                    "body_fat": entry.bodyFat.map(AgentJSONValue.number) ?? .null,
                    "waist": entry.waist.map(AgentJSONValue.number) ?? .null
                ] as [String: AgentJSONValue]
                if arguments.projection == "detail" {
                    value["analysis"] = entry.analysis.nilIfEmpty
                        .map(AgentJSONValue.string) ?? .null
                }
                return value
            }
            return pagedResult(values, noun: "身体记录", arguments: arguments, limit: limit)

        case "profile":
            let values = fetchProfiles(in: context).map {
                [
                    "record_id": businessIDValue($0.businessID),
                    "summary": .string(profileSummary($0))
                ] as [String: AgentJSONValue]
            }
            return pagedResult(values, noun: "个人资料", arguments: arguments, limit: limit)

        case "gyms":
            let gyms = fetchGyms(in: context)
            let equipment = fetchEquipment(in: context)
            let values = gyms.map { gym in
                let names = equipment.filter { $0.gymID == gym.id }.map(\.name).joined(separator: "、")
                return [
                    "record_id": businessIDValue(gym.businessID),
                    "name": .string(gym.name),
                    "is_current": .bool(gym.isCurrent),
                    "equipment": .string(names.nilIfEmpty ?? "暂无")
                ] as [String: AgentJSONValue]
            }
            return pagedResult(values, noun: "健身房", arguments: arguments, limit: limit)

        case "exercises":
            let exactExerciseID = arguments.exerciseID
            let query = arguments.query?.trimmed.nilIfEmpty
            guard exactExerciseID != nil || query != nil else {
                return .failure("动作库查询必须提供 query 或精确 exercise_id，不再返回全库。")
            }
            let values = ExerciseLibraryStore.nameReferences(in: context)
                .filter { reference in
                    exactExerciseID.map { reference.id == $0 }
                        ?? reference.name.localizedCaseInsensitiveContains(query ?? "")
                }
                .map {
                    [
                        "exercise_id": .number(Double($0.id)),
                        "name": .string($0.name)
                    ] as [String: AgentJSONValue]
                }
            return pagedResult(values, noun: "动作", arguments: arguments, limit: limit)

        case "exercise_history":
            guard let businessID = arguments.exerciseID,
                  let exercise = try? ExerciseLibraryStore.definition(
                      businessID: businessID,
                      in: context
                  )
            else {
                return .failure("exercise_history 需要有效的 exercise_id。")
            }
            let values = filteredByDate(fetchWorkouts(in: context), arguments: arguments, date: \.date)
                .filter { $0.exerciseID == exercise.id }
                .map {
                    [
                        "record_id": businessIDValue($0.businessID),
                        "date": .string($0.date.ISO8601Format()),
                        "summary": .string(workoutSummary($0))
                    ] as [String: AgentJSONValue]
                }
            return pagedResult(values, noun: "动作训练历史", arguments: arguments, limit: limit)

        case "programs":
            return queryPrograms(arguments, limit: limit, in: context)

        case "templates":
            return queryTemplates(arguments, limit: limit, in: context)

        case "sessions":
            return querySessions(arguments, limit: limit, in: context)

        default:
            return .failure(
                "scope 不支持。可选值：overview、profile、workouts、meals、body、gyms、exercises、exercise_history、programs、templates、sessions。"
            )
        }
    }

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
        guard let entry = fetchWorkouts(in: context).first(where: { $0.businessID == id }) else {
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
        guard let entry = fetchMeals(in: context).first(where: { $0.businessID == id }) else {
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
        guard let entry = fetchBodyEntries(in: context).first(where: { $0.businessID == id }) else {
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
            guard let entry = fetchWorkouts(in: context).first(where: { $0.businessID == id }) else {
                return .failure("没有找到指定训练记录，请重新查询。")
            }
            do {
                try GuidedWorkoutRecordStore.delete(entry, in: context)
            } catch {
                return .failure("删除训练记录失败：\(error.localizedDescription)")
            }
        case "meal":
            guard let entry = fetchMeals(in: context).first(where: { $0.businessID == id }) else {
                return .failure("没有找到指定饮食记录，请重新查询。")
            }
            context.delete(entry)
        case "body":
            guard let entry = fetchBodyEntries(in: context).first(where: { $0.businessID == id }) else {
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
        let imageAttachments = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaKind,
            legacyPath: mediaPath
        ).filter { $0.kind == .image }
        if arguments.mediaSource == AgentToolMediaAttribution.recentGymTurn,
           imageAttachments.isEmpty
        {
            return .failure("没有找到紧邻上一轮的健身房照片，请重新附加照片后再试。")
        }

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
        let photoDetail = imageAttachments.isEmpty
            ? ""
            : "，并保存 \(imageAttachments.count) 张照片"
        return .success(
            "已更新健身房「\(target.name)」：\(detail)\(photoDetail)。",
            recordRefs: [gymReference(target)],
            recordType: .gym
        )
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

    private static func recordID(
        from arguments: AgentToolArguments
    ) -> Int64? {
        arguments.recordID
    }

    private static func resolveExercise(
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

    private static func businessIDValue(_ id: Int64?) -> AgentJSONValue {
        id.map { .number(Double($0)) } ?? .null
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

    static func recordGym(
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

    static func recordMeal(
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
        context.insert(MealEntry(
            date: sourceDate,
            mealType: type,
            title: meal.title,
            calories: meal.calories,
            protein: meal.protein,
            carbs: meal.carbs,
            fat: meal.fat,
            notes: recordedText(sourceText, analysis: meal.note),
            imagePath: mediaPath,
            mediaAttachments: resolvedMedia,
            confidence: meal.confidence,
            sourceTurnID: sourceTurnID,
            sourceSessionID: sourceSessionID
        ))
    }

    static func recordBody(
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
        let analysis = "\(body.postureNote)\n\(body.safetyNote)"
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

    static func recordWorkout(
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
        let definition = try? ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: workout.exercise,
            in: context
        )
        let setEntries = workout.setEntries ?? legacyWorkoutSetEntries(
            sets: workout.sets,
            reps: workout.reps,
            weight: workout.weight
        )
        let sets = setEntries?.count ?? workout.sets
        let reps = representativeReps(in: setEntries) ?? workout.reps
        let durationMinutes = WorkoutCalorieCalculator.sanitizedActualDurationMinutes(
            workout.durationMinutes,
            sets: sets,
            reps: reps,
            restSeconds: workout.restSeconds
        )
        let calorieEstimate = WorkoutCalorieCalculator.estimate(
            exercise: workout.exercise,
            intensity: workout.intensity,
            durationMinutes: durationMinutes,
            sets: sets,
            reps: reps,
            restSeconds: workout.restSeconds,
            weightKG: WorkoutCalorieCalculator.currentReferenceWeight(in: context)
        )
        let resolvedMedia = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaKind,
            legacyPath: mediaPath
        )
        context.insert(WorkoutEntry(
            date: sourceDate,
            exercise: definition?.canonicalName ?? workout.exercise,
            exerciseID: definition?.id,
            sets: workout.sets,
            reps: workout.reps,
            weight: workout.weight,
            setEntries: setEntries,
            restSeconds: workout.restSeconds,
            durationMinutes: durationMinutes,
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

    static func switchGym(
        _ result: ConversationResult,
        gyms: [GymProfile],
        in context: ModelContext
    ) {
        _ = targetGym(named: result.gymName, gyms: gyms, in: context)
    }

    private struct ValidatedGlycemicAssessment {
        var speed: MealGlycemicSpeed
        var text: String
    }

    private enum GlycemicAssessmentValidation {
        case success(ValidatedGlycemicAssessment?)
        case failure(String)
    }

    private static func validatedGlycemicAssessment(
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
