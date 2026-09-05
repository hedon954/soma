import Foundation
import SwiftData

struct ProgressHistoryFacts: Sendable {
    let records: [ProgressHistoryRecord]
    let profile: ProgressProfileFacts?
}

@ModelActor
actor ProgressHistoryLoader {
    func load(window: ProgressPeriodWindow) throws -> ProgressHistoryFacts {
        let start = window.start
        let end = window.end
        var workouts = try read(FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }, sortBy: [SortDescriptor(\.date)]
        )) { workout in
            ProgressHistoryRecord(
                activity: .workout(workout), calories: workout.estimatedCalories.map(Double.init), volume: workout.estimatedVolume,
                logicalSets: Self.workingSetCount(workout), exerciseID: workout.exerciseID,
                durationSeconds: workout.durationMinutes.map { Double($0) * 60 }
            )
        }
        var definitions: [UUID: ExerciseContent] = [:]
        for id in Set(workouts.compactMap(\.exerciseID)) {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<ExerciseDefinition>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let exercise = try modelContext.fetch(descriptor).first {
                definitions[id] = .init(coachingNotes: "", primaryMuscles: exercise.primaryMuscles,
                                        secondaryMuscles: exercise.secondaryMuscles, movementPatterns: [])
            }
        }
        for index in workouts.indices {
            guard let id = workouts[index].exerciseID, let definition = definitions[id] else { continue }
            workouts[index].primaryMuscles = definition.primaryMuscles
            workouts[index].secondaryMuscles = definition.secondaryMuscles
        }
        let meals = try read(FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }, sortBy: [SortDescriptor(\.date)]
        )) { meal in
            let totals = meal.items.isEmpty ? nil : MealNutritionTotals.derive(from: meal.items)
            return ProgressHistoryRecord(
                activity: .init(id: meal.id, kind: .meal, date: meal.date, title: meal.title, detail: meal.mealType.rawValue, metric: nil),
                calories: (totals?.knownCalories ?? meal.calories).map(Double.init),
                protein: totals?.knownProtein ?? meal.protein, carbs: totals?.knownCarbs ?? meal.carbs, fat: totals?.knownFat ?? meal.fat,
                caloriesArePartial: totals.map { !$0.caloriesIsComplete } ?? (meal.calories == nil)
            )
        }
        var body = try read(FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }, sortBy: [SortDescriptor(\.date)]
        ), transform: Self.bodyRecord)
        // At most one carry-in weight; it supplies the historical formula, not a fabricated chart point.
        let maximumWeight = Double.greatestFiniteMagnitude
        var earlierWeight = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.date < start && ($0.weight ?? 0) > 0 && ($0.weight ?? 0) < maximumWeight },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        earlierWeight.fetchLimit = 1
        body += try modelContext.fetch(earlierWeight).map(Self.bodyRecord)
        var profileQuery = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        profileQuery.fetchLimit = 1
        let profile = try modelContext.fetch(profileQuery).first.map { profile in
            try ProgressProfileFacts(
                updatedAt: profile.updatedAt, birthDate: profile.birthDate, height: profile.height, biologicalSex: profile.biologicalSex,
                baselines: EnergyLifestyleStorage.decode(profile.energyBaselinesData)
            )
        }
        return ProgressHistoryFacts(records: workouts + meals + body, profile: profile)
    }

    private func read<Model: PersistentModel, Value>(
        _ query: FetchDescriptor<Model>, transform: (Model) -> Value
    ) throws -> [Value] {
        var descriptor = query
        descriptor.fetchLimit = 256
        var result: [Value] = []
        while true {
            try Task.checkCancellation()
            let batch = try modelContext.fetch(descriptor)
            result += batch.map(transform)
            guard batch.count == 256 else { return result }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + batch.count
        }
    }

    private static func workingSetCount(_ workout: WorkoutEntry) -> Int {
        let entries = workout.setEntries.filter { $0.kind != .warmup }
        guard !entries.isEmpty else { return workout.setEntries.isEmpty ? max(workout.sets ?? 0, 0) : 0 }
        let indexed = Set(entries.compactMap(\.logicalSetIndex))
        return indexed.count + entries.count(where: { $0.logicalSetIndex == nil })
    }

    private static func bodyRecord(_ entry: BodyEntry) -> ProgressHistoryRecord {
        .init(
            activity: .init(id: entry.id, kind: .body, date: entry.date, title: "身体测量", detail: entry.notes, metric: entry.weight.map { "\($0.formatted()) kg" }),
            weight: entry.weight, bodyFat: entry.bodyFat, waist: entry.waist
        )
    }
}
