import Foundation
import SwiftData

struct WorkoutSharePosterModel: Equatable, Identifiable {
    var id = UUID()
    var dateText: String
    var title: String
    var focusMuscles: [String]
    var durationText: String
    var volumeValue: String
    var exerciseCount: Int
    var completedSets: Int
    var partialSets: Int = 0
    var failedSets: Int = 0
    var estimatedCalories: Int?
    var recordedWeightMissing = false
    var intensities: [MuscleGroup: Double]
    var exercises: [ExerciseLine]

    struct ExerciseLine: Equatable, Identifiable {
        var id: UUID
        var name: String
        var setCount: Int
        var partialSetCount: Int = 0
        /// Load only, without the set-count prefix (e.g. `自重 × 5`).
        var loadSummary: String
    }
}

/// The only aggregation path for workout share posters. A plan execution and a
/// natural day differ only in how they select `WorkoutEntry` records and supply
/// scope metadata; exercise, muscle, volume, calorie and duration projection is shared.
enum WorkoutSharePosterBuilder {
    private struct Scope {
        var date: Date
        var calendar: Calendar
        var title: String?
        var durationText: String?
        var completedSets: Int?
        var partialSets: Int
        var failedSets: Int
        var exerciseCount: Int?
        var hasCompleteWorkoutBatch: Bool
        var recordedWeightMissing: Bool
        var partialSetsByWorkoutID: [UUID: Int]
    }

    @MainActor
    static func makeModel(
        session: WorkoutSession,
        in context: ModelContext
    ) -> WorkoutSharePosterModel {
        let summary = TrainingPlanStore.summary(for: session)
        let performances = session.performances.sorted { $0.order < $1.order }
        let workouts: [WorkoutEntry] = performances.compactMap { performance -> WorkoutEntry? in
            guard !performance.workoutProjectionSuppressed else { return nil }
            return performance.projectedWorkout
        }
        let partialSetsByWorkoutID = performances.reduce(
            into: [UUID: Int]()
        ) { result, performance in
            guard !performance.workoutProjectionSuppressed,
                  let workoutID = performance.projectedWorkout?.id
            else { return }
            result[workoutID] = performance.workoutSets.count {
                $0.status == .partial
            }
        }
        let scope = Scope(
            date: session.startedAt,
            calendar: .current,
            title: programDisplayName(for: session, in: context),
            durationText: summary.durationText,
            completedSets: summary.completedSets,
            partialSets: summary.partialSets,
            failedSets: summary.failedSets,
            exerciseCount: summary.exerciseCount,
            hasCompleteWorkoutBatch: workouts.count == summary.exerciseCount,
            recordedWeightMissing: WorkoutCalorieCalculator.latestRecordedWeight(
                at: session.startedAt,
                in: context
            ) == nil,
            partialSetsByWorkoutID: partialSetsByWorkoutID
        )
        return makeModel(workouts: workouts, scope: scope)
    }

    /// Fetches the complete natural-day batch instead of reusing the paginated
    /// rows currently visible in workout history.
    @MainActor
    static func makeModel(
        forDay day: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws -> WorkoutSharePosterModel? {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }
        var descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { workout in
                workout.date >= start && workout.date < end
            },
            sortBy: [SortDescriptor(\.date)]
        )
        descriptor.fetchLimit = 0
        let workouts = try context.fetch(descriptor)
        guard !workouts.isEmpty else { return nil }
        ExerciseLibraryStore.linkExistingExercises(for: workouts, in: context)
        let scope = Scope(
            date: start,
            calendar: calendar,
            title: nil,
            durationText: nil,
            completedSets: nil,
            partialSets: 0,
            failedSets: 0,
            exerciseCount: nil,
            hasCompleteWorkoutBatch: true,
            recordedWeightMissing: WorkoutCalorieCalculator.latestRecordedWeight(
                at: workouts.map(\.date).min() ?? start,
                in: context
            ) == nil,
            partialSetsByWorkoutID: [:]
        )
        return makeModel(workouts: workouts, scope: scope)
    }

    private static func makeModel(
        workouts: [WorkoutEntry],
        scope: Scope
    ) -> WorkoutSharePosterModel {
        let intensityInputs = workouts.map { workout in
            let definition = workout.exerciseDefinition
            return (
                primary: definition?.primaryMuscles ?? [],
                secondary: definition?.secondaryMuscles ?? [],
                sets: max(workout.setCount ?? 0, 1)
            )
        }
        let intensities = MuscleMapView.intensities(exercises: intensityInputs)
        let focusMuscles = topMuscleNames(from: intensities, limit: 3)
        let exerciseLines = workouts.map { workout in
            WorkoutSharePosterModel.ExerciseLine(
                id: workout.id,
                name: workout.exercise,
                setCount: workout.setCount ?? 0,
                partialSetCount: scope.partialSetsByWorkoutID[workout.id] ?? 0,
                loadSummary: evidenceLoadSummary(workout.setEntries)
            )
        }
        let volumes = workouts.compactMap(\.estimatedVolume)
        let volumeValue = volumes.isEmpty
            ? "—"
            : volumes.reduce(0, +).formatted(
                .number.precision(.fractionLength(0 ... 1))
            )
        let calorieValues = workouts.compactMap(\.estimatedCalories)
        let estimatedCalories = !workouts.isEmpty
            && scope.hasCompleteWorkoutBatch
            && calorieValues.count == workouts.count
            ? calorieValues.reduce(0, +)
            : nil
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = scope.calendar
        formatter.timeZone = scope.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd EEE"
        let focusTitle = focusMuscles.prefix(2).joined(separator: " · ")

        return WorkoutSharePosterModel(
            dateText: formatter.string(from: scope.date),
            title: scope.title
                ?? (focusTitle.isEmpty ? nil : focusTitle)
                ?? "本次训练",
            focusMuscles: focusMuscles,
            durationText: scope.durationText ?? durationText(for: workouts),
            volumeValue: volumeValue,
            exerciseCount: scope.exerciseCount ?? workouts.count,
            completedSets: scope.completedSets
                ?? workouts.compactMap(\.setCount).reduce(0, +),
            partialSets: scope.partialSets,
            failedSets: scope.failedSets,
            estimatedCalories: estimatedCalories,
            recordedWeightMissing: scope.recordedWeightMissing,
            intensities: intensities,
            exercises: exerciseLines
        )
    }

    private static func durationText(for workouts: [WorkoutEntry]) -> String {
        var totalMinutes = 0.0
        var hasEstimatedDuration = false
        for workout in workouts {
            if let duration = workout.durationMinutes, duration > 0 {
                totalMinutes += Double(duration)
            } else if let duration = workout.calorieDurationMinutes, duration > 0 {
                totalMinutes += duration
                hasEstimatedDuration = hasEstimatedDuration
                    || workout.calorieDurationEstimated
            } else {
                return "—"
            }
        }
        guard totalMinutes > 0 else { return "—" }
        let totalSeconds = Int((totalMinutes * 60).rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let value = if minutes > 0, seconds > 0 {
            "\(minutes) 分 \(seconds) 秒"
        } else if minutes > 0 {
            "\(minutes) 分"
        } else {
            "\(seconds) 秒"
        }
        return hasEstimatedDuration ? "约 \(value)" : value
    }

    private static func topMuscleNames(
        from intensities: [MuscleGroup: Double],
        limit: Int
    ) -> [String] {
        intensities
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                lhs.value == rhs.value
                    ? lhs.key.rawValue < rhs.key.rawValue
                    : lhs.value > rhs.value
            }
            .prefix(limit)
            .map(\.key.displayName)
    }

    /// Plan name only.
    @MainActor
    static func programDisplayName(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> String? {
        let snapshot = session.programNameSnapshot?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let snapshot, !snapshot.isEmpty {
            return snapshot
        }
        guard let label = TrainingPlanStore.programSourceLabel(
            for: session,
            in: context
        ) else {
            return nil
        }
        if let range = label.range(of: #" · v\d+$"#, options: .regularExpression) {
            return String(label[..<range.lowerBound])
        }
        return label
    }

    /// Compact load summary for the share poster (set count shown separately).
    static func loadSummary(for sets: [WorkoutSet]) -> String {
        let loads = sets.map(loadToken(for:))
        guard let first = loads.first else { return "—" }
        if loads.allSatisfy({ $0 == first }) {
            return first
        }
        let visible = loads.prefix(4)
        let joined = visible.joined(separator: " · ")
        return loads.count > visible.count ? "\(joined) 等" : joined
    }

    /// Full one-line summary used by tests / callers that want set count inline.
    static func exerciseSummary(for sets: [WorkoutSet]) -> String {
        guard !sets.isEmpty else { return "0组" }
        return "\(sets.count)组 · \(loadSummary(for: sets))"
    }

    static func evidenceLoadSummary(
        _ evidence: [WorkoutSetEvidence]
    ) -> String {
        guard !evidence.isEmpty else { return "—" }
        let grouped = Dictionary(grouping: evidence) {
            $0.logicalSetIndex ?? 0
        }
        let tokens = grouped.keys.sorted().map { key in
            let values = grouped[key, default: []]
            return values.map(evidenceLoadToken).joined(separator: " / ")
        }
        let visible = tokens.prefix(4).joined(separator: " · ")
        return tokens.count > 4 ? "\(visible) 等" : visible
    }

    private static func loadToken(for set: WorkoutSet) -> String {
        let weight = set.actualWeightKG ?? set.plannedWeightKG
        if set.plannedTargetKind == .duration {
            let seconds = set.actualDurationSeconds ?? set.plannedDurationSeconds
            let duration = seconds.map { "\($0)秒" } ?? "时长未记录"
            if let weight, weight > 0 {
                return "\(weight.formatted(.number.precision(.fractionLength(0 ... 1))))kg · \(duration)"
            }
            return duration
        }
        let reps = set.actualReps ?? set.plannedReps
        let repsText = reps.map(String.init) ?? "—"
        if let weight, weight > 0 {
            let weightText = weight.formatted(.number.precision(.fractionLength(0 ... 1)))
            return "\(weightText)kg × \(repsText)"
        }
        return "自重 × \(repsText)"
    }

    private static func evidenceLoadToken(
        _ evidence: WorkoutSetEvidence
    ) -> String {
        var tokens: [String] = []
        switch evidence.side {
        case .some(.left):
            tokens.append("左")
        case .some(.right):
            tokens.append("右")
        case nil, .some(.none):
            break
        }
        if let weight = evidence.externalWeightKG, weight > 0 {
            tokens.append(
                "\(weight.formatted(.number.precision(.fractionLength(0 ... 1))))kg"
            )
        } else {
            tokens.append("自重")
        }
        if let reps = evidence.reps {
            tokens.append("× \(reps)")
        } else if let duration = evidence.durationSeconds {
            tokens.append("· \(duration)秒")
        }
        return tokens.joined(separator: " ")
    }
}
