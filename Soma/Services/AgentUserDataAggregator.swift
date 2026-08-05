import Foundation
import SwiftData

enum AgentUserDataAggregator {
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
            return .success(calorieBuckets(meals: meals, groupBy: groupBy))
        case "frequency":
            return .success(frequencyBuckets(workouts: workouts, groupBy: groupBy))
        case "volume":
            return .success(
                workoutBuckets(
                    workouts: workouts,
                    groupBy: groupBy,
                    in: context,
                    value: volume(of:)
                )
            )
        default:
            return .success(
                workoutBuckets(
                    workouts: workouts,
                    groupBy: groupBy,
                    in: context,
                    value: { Double($0.setCount ?? 0) }
                )
            )
        }
    }

    private static func dateRange(
        from: String?,
        to: String?
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let end = parseDate(to) ?? Date()
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

    private static func volume(of workout: WorkoutEntry) -> Double {
        let entries = workout.setEntries
        if !entries.isEmpty {
            return entries.reduce(0) { sum, entry in
                let reps = Double(entry.reps ?? 0)
                let weight = entry.externalWeightKG ?? 0
                return sum + reps * weight
            }
        }
        guard let sets = workout.sets,
              let reps = workout.reps,
              let weight = workout.weight
        else {
            return 0
        }
        return Double(sets * reps) * weight
    }

    private static func workoutBuckets(
        workouts: [WorkoutEntry],
        groupBy: String,
        in context: ModelContext,
        value: (WorkoutEntry) -> Double
    ) -> String {
        var buckets: [String: Double] = [:]
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
            let amount = value(workout)
            for key in keys {
                buckets[key, default: 0] += amount
            }
        }
        return formatBuckets(buckets)
    }

    private static func frequencyBuckets(
        workouts: [WorkoutEntry],
        groupBy: String
    ) -> String {
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
        let mapped = buckets.mapValues { Double($0.count) }
        return formatBuckets(mapped)
    }

    private static func calorieBuckets(
        meals: [MealEntry],
        groupBy: String
    ) -> String {
        var buckets: [String: Double] = [:]
        for meal in meals {
            let key = groupBy == "week" ? weekKey(meal.date) : dayKey(meal.date)
            buckets[key, default: 0] += Double(meal.calories)
        }
        return formatBuckets(buckets)
    }

    private static func formatBuckets(_ buckets: [String: Double]) -> String {
        guard !buckets.isEmpty else { return "所选范围内没有可聚合的数据。" }
        return buckets.sorted { $0.key > $1.key }.prefix(20).map {
            "\($0.key)：\($0.value.formatted(.number.precision(.fractionLength(0 ... 1))))"
        }.joined(separator: "\n")
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
