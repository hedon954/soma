import Foundation
import SwiftData

struct ProgressHistoryFacts: Sendable {
    let records: [ProgressHistoryRecord]
    let profile: ProgressProfileFacts?
}

@ModelActor
actor ProgressHistoryLoader {
    func load(window: ProgressPeriodWindow) async throws -> ProgressHistoryFacts {
        let plannedDays = try await EnergyPlanForecastLoader.load(in: modelContainer)
        let start = Calendar.current.date(byAdding: .day, value: -56, to: window.start) ?? window.start
        let end = window.end
        var workouts = try read(FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }, sortBy: [SortDescriptor(\.date)]
        )) { workout in
            try ProgressHistoryRecord(
                activity: .workout(workout), calories: workout.dailyActivity?[.activeEnergy].value ?? workout.estimatedCalories.map(Double.init),
                calorieMET: workout.calorieMET, activeEnergyKilocalories: workout.dailyActivity?[.activeEnergy].value,
                isDailyActivity: workout.isDailyActivity,
                dailyActivitySource: workout.isDailyActivity ? workout.dailyActivityWinningSource : nil,
                trainingEvidence: trainingEvidence(workout), volume: workout.estimatedVolume,
                logicalSets: Self.workingSetCount(workout), exerciseID: workout.exerciseID,
                durationSeconds: (workout.calorieDurationMinutes ?? workout.durationMinutes.map(Double.init))
                    .map { $0 * 60 }
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
        let windowBodies = try read(FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }, sortBy: [SortDescriptor(\.date)]
        ), transform: { $0 })
        var body = Self.bodyRecords(from: windowBodies)
        // At most one carry-in weight; it supplies the historical formula, not a fabricated chart point.
        let maximumWeight = Double.greatestFiniteMagnitude
        var earlierWeight = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.date < start && ($0.weight ?? 0) > 0 && ($0.weight ?? 0) < maximumWeight },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        earlierWeight.fetchLimit = 1
        body += try modelContext.fetch(earlierWeight).map { Self.bodyRecord(BodyHistoryMeasurement(entries: [$0])) }
        var profileQuery = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        profileQuery.fetchLimit = 1
        let profile = try modelContext.fetch(profileQuery).first.map { profile in
            var facts = try energyFacts(from: start, to: end)
            facts.plannedDays = plannedDays
            return try ProgressProfileFacts(
                updatedAt: profile.updatedAt, birthDate: profile.birthDate, height: profile.height, biologicalSex: profile.biologicalSex,
                baselines: EnergyLifestyleStorage.decode(profile.energyBaselinesData),
                fitnessGoal: FitnessGoal(rawValue: profile.fitnessGoal), energyFacts: facts,
                dailyTargetDeficitKilocalories: profile.dailyTargetDeficitKilocalories
            )
        }
        return ProgressHistoryFacts(records: workouts + meals + body, profile: profile)
    }

    private func energyFacts(from start: Date, to end: Date) throws -> EnergyProjectionFacts {
        var contexts = try read(FetchDescriptor<EnergyContextEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })) { $0 }
        for lifestyle in [true, false] {
            var previous = FetchDescriptor<EnergyContextEntry>(predicate: #Predicate {
                $0.date < start && (lifestyle ? $0.lifestyleData != nil : $0.learningPaused != nil)
            }, sortBy: [SortDescriptor(\.date, order: .reverse)])
            previous.fetchLimit = 1
            contexts += try modelContext.fetch(previous)
        }
        let unique = Dictionary(contexts.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last }).values
        let decoder = JSONDecoder()
        let facts = try unique.map { entry in
            try EnergyContextFacts(date: entry.date, timeZoneIdentifier: entry.timeZoneIdentifier,
                                   lifestyle: entry.lifestyleData.map { try decoder.decode(EnergyLifestyleFacts.self, from: $0) },
                                   confirmation: entry.confirmationData.map { try decoder.decode(EnergyDayConfirmation.self, from: $0) },
                                   learningPaused: entry.learningPaused)
        }
        return try .init(
            contexts: facts,
            activity: latestEvidence(.healthActivity, from: start, to: end).map { try decoder.decode(HealthActivityDayEvidence.self, from: $0.payload) },
            references: latestEvidence(.reference, from: start, to: end, carry: true).map { try decoder.decode(EnergyReferenceDay.self, from: $0.payload) },
            reviews: latestEvidence(.calibration, from: start, to: end, carry: true).map { try decoder.decode(EnergyCalibrationReview.self, from: $0.payload) },
            associations: latestEvidence(.association, from: start, to: end).map { try decoder.decode(EnergyTrainingAssociations.self, from: $0.payload) }
        )
    }

    private func latestEvidence(_ kind: EnergyEvidenceKind, from start: Date, to end: Date, carry: Bool = false) throws -> [EnergyEvidenceEntry] {
        let raw = kind.rawValue
        var rows = try read(FetchDescriptor<EnergyEvidenceEntry>(
            predicate: #Predicate { $0.kindRaw == raw && $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date), SortDescriptor(\.revision, order: .reverse)]
        )) { $0 }
        if carry {
            var prior = FetchDescriptor<EnergyEvidenceEntry>(predicate: #Predicate { $0.kindRaw == raw && $0.date < start },
                                                             sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.revision, order: .reverse)])
            prior.fetchLimit = 1
            rows = try modelContext.fetch(prior) + rows
        }
        var seen: Set<Date> = []
        return rows.filter { seen.insert($0.date).inserted }
    }

    private func trainingEvidence(_ workout: WorkoutEntry) throws -> EnergyTrainingEvent? {
        guard !workout.isDailyActivity else { return nil }
        var intervals: [EnergyTimeInterval] = []
        if let performanceID = workout.sourcePerformanceID {
            intervals = try read(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.performanceID == performanceID })) { set -> EnergyTimeInterval? in
                guard let start = set.startedAt, let end = set.completedAt, end > start else { return nil }
                return .init(start: start, end: end)
            }.compactMap { $0 }
        }
        if !intervals.isEmpty, let sessionID = workout.sourceWorkoutSessionID {
            var sessionQuery = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })
            sessionQuery.fetchLimit = 1
            if let session = try modelContext.fetch(sessionQuery).first, let end = session.endedAt, end > session.startedAt {
                intervals = [.init(start: session.startedAt, end: end)]
            }
        }
        return .init(id: "soma:" + workout.id.uuidString, source: "Soma", activityType: workout.exercise,
                     scope: workout.calorieScope, kilocalories: workout.estimatedCalories.map(Double.init), met: workout.calorieMET,
                     durationHours: (workout.calorieDurationMinutes ?? workout.durationMinutes.map(Double.init)).map { $0 / 60 },
                     start: intervals.map(\.start).min(), end: intervals.map(\.end).max(),
                     sessionIdentity: workout.sourceWorkoutSessionID.map { "soma-session:" + $0.uuidString })
    }

    private func read<Model: PersistentModel, Value>(
        _ query: FetchDescriptor<Model>, transform: (Model) throws -> Value
    ) throws -> [Value] {
        var descriptor = query
        descriptor.fetchLimit = 256
        var result: [Value] = []
        while true {
            try Task.checkCancellation()
            let batch = try modelContext.fetch(descriptor)
            result += try batch.map(transform)
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

    private static func bodyRecords(from entries: [BodyEntry]) -> [ProgressHistoryRecord] {
        BodyMassMeasurementPairing.measurements(from: entries).map(bodyRecord)
    }

    private static func bodyRecord(_ measurement: BodyHistoryMeasurement) -> ProgressHistoryRecord {
        .init(
            activity: .init(
                id: measurement.id,
                kind: .body,
                date: measurement.date,
                title: "身体测量",
                detail: measurement.notes ?? "",
                metric: measurement.weight.map { "\($0.formatted()) kg" }
            ),
            weight: measurement.weight,
            bodyFat: measurement.bodyFat,
            waist: nil
        )
    }
}
