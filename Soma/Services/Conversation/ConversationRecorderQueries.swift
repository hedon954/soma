import Foundation
import SwiftData

@MainActor
extension ConversationRecorder {
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
            let workouts = fetchWorkouts(in: context, limit: 1)
            let meals = fetchMeals(in: context, limit: 1)
            let body = fetchBodyEntries(in: context, limit: 1)
            let selectedGym = preferredGymID
                .flatMap { fetchGym(id: $0, in: context) }
                ?? currentGym(in: context)
            let equipmentNames = selectedGym.map { gym in
                fetchEquipment(gymID: gym.id, limit: 100, in: context)
                    .map(\.name)
                    .joined(separator: "、")
            }.flatMap(\.nilIfEmpty) ?? "无"
            let workout = workouts.first.map {
                "[id:\($0.businessID ?? 0)] \(workoutSummary($0))"
            } ?? "暂无"
            let todayStart = Calendar.current.startOfDay(for: .now)
            let tomorrow = Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: todayStart
            ) ?? .distantFuture
            let todayMeals = (try? context.fetch(FetchDescriptor<MealEntry>(
                predicate: #Predicate {
                    $0.date >= todayStart && $0.date < tomorrow
                }
            ))) ?? []
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
                "个人信息：\(profile)；当前健身房：\(selectedGym?.name ?? "无")；可用器械：\(equipmentNames)；最近训练：\(workout)；最近饮食：\(latestMeal)；今日摄入：\(todayCalories)；最近体重：\(weight)。"
            )

        case "workouts":
            let values = filteredByDate(
                queryWorkouts(arguments, limit: limit, in: context),
                arguments: arguments,
                date: \.date
            )
            .filter { arguments.recordID == nil || $0.businessID == arguments.recordID }
            .map { entry in
                var value = [
                    "record_id": businessIDValue(entry.businessID),
                    "date": .string(entry.date.ISO8601Format()),
                    "title": .string(entry.exercise),
                    "summary": .string(workoutSummary(entry))
                ] as [String: AgentJSONValue]
                if arguments.projection == "detail" {
                    let definitionID = entry.exerciseDefinition?.businessID
                        ?? entry.exerciseID.flatMap { internalID in
                            exerciseDefinition(
                                internalID: internalID,
                                in: context
                            )?.businessID
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
            let values = filteredByDate(
                queryMeals(arguments, limit: limit, in: context),
                arguments: arguments,
                date: \.date
            )
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
                    value["glycemic_speed"] = entry.glycemicSpeedRaw
                        .map(AgentJSONValue.string) ?? .null
                    value["glycemic_assessment"] = entry.glycemicAssessment.nilIfEmpty
                        .map(AgentJSONValue.string) ?? .null
                    value["recommended_eating_order"] = entry.recommendedEatingOrder.nilIfEmpty
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
                            "fat": item.fat.map(AgentJSONValue.number) ?? .null
                        ])
                    }
                    value["items"] = .array(encodedItems)
                }
                return value
            }
            return pagedResult(values, noun: "饮食记录", arguments: arguments, limit: limit)

        case "body":
            let values = filteredByDate(
                queryBodyEntries(arguments, limit: limit, in: context),
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
            let values = filteredByDate(
                queryWorkouts(
                    arguments,
                    limit: limit,
                    exerciseID: exercise.id,
                    in: context
                ),
                arguments: arguments,
                date: \.date
            )
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

        case "sessions":
            return querySessions(arguments, limit: limit, in: context)

        default:
            return .failure(
                "scope 不支持。可选值：overview、profile、workouts、meals、body、gyms、exercises、exercise_history、programs、sessions。"
            )
        }
    }

    static func fetchGyms(in context: ModelContext) -> [GymProfile] {
        // 仅供 Tool 列表序列化；身份匹配和写入必须使用 mutation 查询。
        var descriptor = FetchDescriptor<GymProfile>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 100
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchEquipment(in context: ModelContext) -> [GymEquipment] {
        // 仅供有界 Tool 列表序列化。
        var descriptor = FetchDescriptor<GymEquipment>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1000
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchGymsForMutation(in context: ModelContext) -> [GymProfile] {
        let descriptor = FetchDescriptor<GymProfile>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchEquipment(
        gymID: UUID,
        limit: Int? = nil,
        in context: ModelContext
    ) -> [GymEquipment] {
        var descriptor = FetchDescriptor<GymEquipment>(
            predicate: #Predicate { $0.gymID == gymID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchGym(id: UUID, in context: ModelContext) -> GymProfile? {
        var descriptor = FetchDescriptor<GymProfile>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func currentGym(in context: ModelContext) -> GymProfile? {
        var currentDescriptor = FetchDescriptor<GymProfile>(
            predicate: #Predicate { $0.isCurrent },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        currentDescriptor.fetchLimit = 1
        if let current = try? context.fetch(currentDescriptor).first {
            return current
        }

        var fallbackDescriptor = FetchDescriptor<GymProfile>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        fallbackDescriptor.fetchLimit = 1
        return try? context.fetch(fallbackDescriptor).first
    }

    static func fetchWorkouts(
        in context: ModelContext,
        limit: Int? = nil
    ) -> [WorkoutEntry] {
        var descriptor = FetchDescriptor<WorkoutEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchMeals(
        in context: ModelContext,
        limit: Int? = nil
    ) -> [MealEntry] {
        var descriptor = FetchDescriptor<MealEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchBodyEntries(
        in context: ModelContext,
        limit: Int? = nil
    ) -> [BodyEntry] {
        var descriptor = FetchDescriptor<BodyEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchProfiles(in context: ModelContext) -> [UserProfile] {
        var descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor)) ?? []
    }

    static func queryWorkouts(
        _ arguments: AgentToolArguments,
        limit: Int,
        exerciseID: UUID? = nil,
        in context: ModelContext
    ) -> [WorkoutEntry] {
        if let recordID = arguments.recordID {
            return workout(businessID: recordID, in: context).map { [$0] } ?? []
        }
        let range = queryDateRange(arguments)
        let sort = [SortDescriptor(
            \WorkoutEntry.date,
            order: arguments.sort == "oldest" ? .forward : .reverse
        )]
        var descriptor: FetchDescriptor<WorkoutEntry> = switch (exerciseID, range.lower, range.upper) {
        case let (exerciseID?, lower?, upper?):
            FetchDescriptor(
                predicate: #Predicate {
                    $0.exerciseID == exerciseID
                        && $0.date >= lower && $0.date < upper
                },
                sortBy: sort
            )
        case let (exerciseID?, lower?, nil):
            FetchDescriptor(
                predicate: #Predicate {
                    $0.exerciseID == exerciseID && $0.date >= lower
                },
                sortBy: sort
            )
        case let (exerciseID?, nil, upper?):
            FetchDescriptor(
                predicate: #Predicate {
                    $0.exerciseID == exerciseID && $0.date < upper
                },
                sortBy: sort
            )
        case let (exerciseID?, nil, nil):
            FetchDescriptor(
                predicate: #Predicate { $0.exerciseID == exerciseID },
                sortBy: sort
            )
        case let (nil, lower?, upper?):
            FetchDescriptor(
                predicate: #Predicate { $0.date >= lower && $0.date < upper },
                sortBy: sort
            )
        case let (nil, lower?, nil):
            FetchDescriptor(
                predicate: #Predicate { $0.date >= lower },
                sortBy: sort
            )
        case let (nil, nil, upper?):
            FetchDescriptor(
                predicate: #Predicate { $0.date < upper },
                sortBy: sort
            )
        case (nil, nil, nil):
            FetchDescriptor(sortBy: sort)
        }
        if arguments.sort != "name" {
            descriptor.fetchLimit = queryFetchLimit(arguments, pageSize: limit)
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    static func queryMeals(
        _ arguments: AgentToolArguments,
        limit: Int,
        in context: ModelContext
    ) -> [MealEntry] {
        if let recordID = arguments.recordID {
            return meal(businessID: recordID, in: context).map { [$0] } ?? []
        }
        let range = queryDateRange(arguments)
        let sort = [SortDescriptor(
            \MealEntry.date,
            order: arguments.sort == "oldest" ? .forward : .reverse
        )]
        var descriptor: FetchDescriptor<MealEntry> = switch (range.lower, range.upper) {
        case let (lower?, upper?):
            FetchDescriptor(
                predicate: #Predicate { $0.date >= lower && $0.date < upper },
                sortBy: sort
            )
        case let (lower?, nil):
            FetchDescriptor(
                predicate: #Predicate { $0.date >= lower },
                sortBy: sort
            )
        case let (nil, upper?):
            FetchDescriptor(
                predicate: #Predicate { $0.date < upper },
                sortBy: sort
            )
        case (nil, nil):
            FetchDescriptor(sortBy: sort)
        }
        if arguments.sort != "name" {
            descriptor.fetchLimit = queryFetchLimit(arguments, pageSize: limit)
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    static func queryBodyEntries(
        _ arguments: AgentToolArguments,
        limit: Int,
        in context: ModelContext
    ) -> [BodyEntry] {
        if let recordID = arguments.recordID {
            return bodyEntry(businessID: recordID, in: context).map { [$0] } ?? []
        }
        let range = queryDateRange(arguments)
        let sort = [SortDescriptor(
            \BodyEntry.date,
            order: arguments.sort == "oldest" ? .forward : .reverse
        )]
        var descriptor: FetchDescriptor<BodyEntry> = switch (range.lower, range.upper) {
        case let (lower?, upper?):
            FetchDescriptor(
                predicate: #Predicate { $0.date >= lower && $0.date < upper },
                sortBy: sort
            )
        case let (lower?, nil):
            FetchDescriptor(
                predicate: #Predicate { $0.date >= lower },
                sortBy: sort
            )
        case let (nil, upper?):
            FetchDescriptor(
                predicate: #Predicate { $0.date < upper },
                sortBy: sort
            )
        case (nil, nil):
            FetchDescriptor(sortBy: sort)
        }
        descriptor.fetchLimit = queryFetchLimit(arguments, pageSize: limit)
        return (try? context.fetch(descriptor)) ?? []
    }

    static func queryDateRange(
        _ arguments: AgentToolArguments
    ) -> (lower: Date?, upper: Date?) {
        let lower = parsedQueryDate(arguments.dateFrom)
        let rawUpper = parsedQueryDate(arguments.dateTo)
        let upper = rawUpper.flatMap { value in
            guard arguments.dateTo?.count == 10 else { return value }
            return Calendar.current.date(byAdding: .day, value: 1, to: value)
        }
        return (lower, upper)
    }

    static func queryFetchLimit(
        _ arguments: AgentToolArguments,
        pageSize: Int
    ) -> Int {
        let offset = cursorOffset(arguments.cursor)
        guard offset != .max else { return pageSize + 1 }
        return offset + pageSize + 1
    }

    static func workout(
        businessID: Int64,
        in context: ModelContext
    ) -> WorkoutEntry? {
        var descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.businessID == businessID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func meal(
        businessID: Int64,
        in context: ModelContext
    ) -> MealEntry? {
        var descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.businessID == businessID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func bodyEntry(
        businessID: Int64,
        in context: ModelContext
    ) -> BodyEntry? {
        var descriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.businessID == businessID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
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
