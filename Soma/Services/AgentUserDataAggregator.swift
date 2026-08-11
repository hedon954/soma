import Foundation
import SwiftData

@MainActor
enum AgentUserDataAggregator {
    private struct Bucket {
        var value: Double = 0
        var knownCount = 0
        var missingCount = 0
    }

    static func aggregate(
        arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let groupBy = arguments.groupBy?.lowercased(),
              ["day", "week", "muscle_group", "exercise"].contains(groupBy)
        else {
            return .failure("aggregate 需要 group_by：day、week、muscle_group 或 exercise。")
        }
        let metric = arguments.metric?.lowercased() ?? "sets"
        guard ["sets", "volume", "calories", "frequency"].contains(metric) else {
            return .failure("metric 仅支持 sets、volume、calories、frequency。")
        }
        if metric == "calories", !["day", "week"].contains(groupBy) {
            return .failure("calories 只支持按 day 或 week 聚合。")
        }
        if metric == "frequency", groupBy == "muscle_group" {
            return .failure("frequency 不支持 muscle_group；请改用 day、week 或 exercise。")
        }
        let range = dateRange(from: arguments.dateFrom, to: arguments.dateTo)
        let workouts = ((try? context.fetch(
            FetchDescriptor<WorkoutEntry>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        )) ?? []).filter {
            $0.externalSource == nil
                && $0.date >= range.start
                && $0.date <= range.end
        }
        let meals = ((try? context.fetch(
            FetchDescriptor<MealEntry>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        )) ?? []).filter {
            $0.date >= range.start && $0.date <= range.end
        }

        switch metric {
        case "calories" where groupBy == "day" || groupBy == "week":
            return result(
                calorieBuckets(meals: meals, groupBy: groupBy),
                arguments: arguments
            )
        case "frequency":
            return result(
                frequencyBuckets(workouts: workouts, groupBy: groupBy),
                arguments: arguments
            )
        case "volume":
            return result(
                workoutBuckets(
                    workouts: workouts,
                    groupBy: groupBy,
                    in: context,
                    value: volume(of:)
                ),
                arguments: arguments
            )
        default:
            return result(
                workoutBuckets(
                    workouts: workouts,
                    groupBy: groupBy,
                    in: context,
                    value: { $0.setCount.map(Double.init) }
                ),
                arguments: arguments
            )
        }
    }

    private static func dateRange(
        from: String?,
        to: String?
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let rawEnd = parseDate(to) ?? Date()
        let end = if to?.count == 10 {
            calendar.date(byAdding: .day, value: 1, to: rawEnd)?
                .addingTimeInterval(-0.001) ?? rawEnd
        } else {
            rawEnd
        }
        let start = parseDate(from)
            ?? calendar.date(byAdding: .day, value: -28, to: end)
            ?? end
        return (start, end)
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = iso.date(from: String(raw.prefix(10))) {
            return date
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(raw.prefix(10)))
    }

    private static func volume(of workout: WorkoutEntry) -> Double? {
        let entries = workout.setEntries
        if !entries.isEmpty {
            let complete = entries.compactMap { entry -> Double? in
                guard let reps = entry.reps,
                      let weight = entry.externalWeightKG
                else { return nil }
                return Double(reps) * weight
            }
            guard complete.count == entries.count else { return nil }
            return complete.reduce(0, +)
        }
        guard let sets = workout.sets,
              let reps = workout.reps,
              let weight = workout.weight
        else {
            return nil
        }
        return Double(sets * reps) * weight
    }

    private static func workoutBuckets(
        workouts: [WorkoutEntry],
        groupBy: String,
        in context: ModelContext,
        value: (WorkoutEntry) -> Double?
    ) -> [String: Bucket] {
        var buckets: [String: Bucket] = [:]
        let definitions = (try? context.fetch(FetchDescriptor<ExerciseDefinition>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        for workout in workouts {
            let keys: [String]
            switch groupBy {
            case "day":
                keys = [dayKey(workout.date)]
            case "week":
                keys = [weekKey(workout.date)]
            case "exercise":
                keys = [workout.exercise]
            case "muscle_group":
                let muscles = workout.exerciseID.flatMap { byID[$0]?.primaryMuscles } ?? []
                let groups = MuscleGroupMapping.resolve(muscles)
                keys = groups.isEmpty
                    ? ["未映射"]
                    : groups.map(\.displayName)
            default:
                keys = [dayKey(workout.date)]
            }
            for key in keys {
                if let amount = value(workout) {
                    buckets[key, default: Bucket()].value += amount
                    buckets[key, default: Bucket()].knownCount += 1
                } else {
                    buckets[key, default: Bucket()].missingCount += 1
                }
            }
        }
        return buckets
    }

    private static func frequencyBuckets(
        workouts: [WorkoutEntry],
        groupBy: String
    ) -> [String: Bucket] {
        var buckets: [String: Set<Date>] = [:]
        for workout in workouts {
            let key: String = switch groupBy {
            case "week":
                weekKey(workout.date)
            case "exercise":
                workout.exercise
            default:
                dayKey(workout.date)
            }
            buckets[key, default: []].insert(
                Calendar.current.startOfDay(for: workout.date)
            )
        }
        return buckets.mapValues {
            Bucket(value: Double($0.count), knownCount: $0.count)
        }
    }

    private static func calorieBuckets(
        meals: [MealEntry],
        groupBy: String
    ) -> [String: Bucket] {
        var buckets: [String: Bucket] = [:]
        for meal in meals {
            let key = groupBy == "week" ? weekKey(meal.date) : dayKey(meal.date)
            if let calories = meal.calories {
                buckets[key, default: Bucket()].value += Double(calories)
                buckets[key, default: Bucket()].knownCount += 1
            } else {
                buckets[key, default: Bucket()].missingCount += 1
            }
        }
        return buckets
    }

    private static func result(
        _ buckets: [String: Bucket],
        arguments: AgentToolArguments
    ) -> AgentToolResult {
        let items = buckets.sorted { $0.key > $1.key }.map { key, bucket in
            [
                "group": .string(key),
                "value": bucket.knownCount > 0
                    ? .number(bucket.value)
                    : .null,
                "missing_count": .number(Double(bucket.missingCount))
            ] as [String: AgentJSONValue]
        }
        return ConversationRecorder.pagedResult(
            items,
            noun: "聚合结果",
            arguments: arguments,
            limit: min(max(arguments.limit ?? 3, 1), 10)
        )
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func weekKey(_ date: Date) -> String {
        let calendar = Calendar(identifier: .iso8601)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }
}
