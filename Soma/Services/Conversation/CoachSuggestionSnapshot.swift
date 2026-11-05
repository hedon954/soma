import Foundation
import SwiftData

struct CoachSuggestionSnapshot: Equatable, Sendable {
    let exercises: [ExerciseInputSuggestionBuilder.ExerciseInput]
    let recentCapacities: [ExerciseInputSuggestionBuilder.RecentCapacityInput]
    let latestWorkoutExerciseName: String?

    static let empty = CoachSuggestionSnapshot(
        exercises: [],
        recentCapacities: [],
        latestWorkoutExerciseName: nil
    )
}

/// 输入建议是次要内容。它不能让教练根页面持有数千个 SwiftData 模型，
/// 也不能在任意 SwiftUI body 更新时重新做 Set/Dictionary/grouping 聚合。
@ModelActor
actor CoachSuggestionSnapshotLoader {
    func load() throws -> CoachSuggestionSnapshot {
        try Task.checkCancellation()

        var definitionDescriptor = FetchDescriptor<ExerciseDefinition>(
            sortBy: [SortDescriptor(\.canonicalName)]
        )
        definitionDescriptor.fetchLimit = 2000

        var workoutDescriptor = FetchDescriptor<WorkoutEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = 140

        var sessionDescriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        sessionDescriptor.fetchLimit = 40

        let definitions = try modelContext.fetch(definitionDescriptor)
        let workouts = try modelContext.fetch(workoutDescriptor).filter { !$0.isDailyActivity }
        try Task.checkCancellation()
        let sessions = try modelContext.fetch(sessionDescriptor)
        // 只遍历最近会话的当前关系图。全库固定上限会让无关旧行抢占配额，
        // 数据越多越容易漏掉真正需要的最近记录，也会白白物化数千个对象。
        let performances = sessions
            .flatMap(\.performances)
            .sorted { lhs, rhs in lhs.order < rhs.order }
        let sets = performances
            .flatMap(\.workoutSets)
            .sorted { lhs, rhs in lhs.order < rhs.order }
        try Task.checkCancellation()

        let exercises = definitions.map {
            ExerciseInputSuggestionBuilder.ExerciseInput(
                id: $0.id,
                name: $0.canonicalName,
                isArchived: $0.isArchived
            )
        }
        let legacy = workouts.compactMap(Self.legacyCapacity)
        let projectedPerformanceIDs = Set(workouts.compactMap(\.sourcePerformanceID))
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let setsByPerformanceID = Dictionary(grouping: sets, by: \.performanceID)
        let guided = performances.compactMap { performance in
            Self.guidedCapacity(
                performance,
                projectedPerformanceIDs: projectedPerformanceIDs,
                sessionsByID: sessionsByID,
                setsByPerformanceID: setsByPerformanceID
            )
        }

        return CoachSuggestionSnapshot(
            exercises: exercises,
            recentCapacities: legacy + guided,
            latestWorkoutExerciseName: workouts.first?.exercise
        )
    }

    private static func legacyCapacity(
        _ workout: WorkoutEntry
    ) -> ExerciseInputSuggestionBuilder.RecentCapacityInput? {
        guard let exerciseID = workout.exerciseID else { return nil }
        return ExerciseInputSuggestionBuilder.RecentCapacityInput(
            exerciseID: exerciseID,
            date: workout.date,
            text: ExerciseQuickFill.text(for: workout),
            recordDraft: ExerciseQuickRecordDraft(
                exerciseID: exerciseID,
                exerciseName: workout.exercise,
                setEntries: workout.setEntries,
                restSeconds: workout.restSeconds,
                durationMinutes: workout.durationMinutes
            )
        )
    }

    private static func guidedCapacity(
        _ performance: ExercisePerformance,
        projectedPerformanceIDs: Set<UUID>,
        sessionsByID: [UUID: WorkoutSession],
        setsByPerformanceID: [UUID: [WorkoutSet]]
    ) -> ExerciseInputSuggestionBuilder.RecentCapacityInput? {
        guard !projectedPerformanceIDs.contains(performance.id),
              !performance.workoutProjectionSuppressed,
              let session = sessionsByID[performance.sessionID]
        else {
            return nil
        }
        let performanceSets = setsByPerformanceID[performance.id] ?? []
        return ExerciseInputSuggestionBuilder.RecentCapacityInput(
            exerciseID: performance.exerciseID,
            date: session.startedAt,
            text: ExerciseQuickFill.text(for: performanceSets),
            recordDraft: guidedQuickRecordDraft(
                performance: performance,
                sets: performanceSets
            )
        )
    }

    private static func guidedQuickRecordDraft(
        performance: ExercisePerformance,
        sets: [WorkoutSet]
    ) -> ExerciseQuickRecordDraft? {
        let completed = sets
            .filter { $0.status == .completed }
            .sorted { $0.order < $1.order }
        guard !completed.isEmpty else { return nil }
        let rests = completed.compactMap(\.actualRestSeconds)
        let rest = rests.count == completed.count && Set(rests).count == 1
            ? rests.first
            : nil
        return ExerciseQuickRecordDraft(
            exerciseID: performance.exerciseID,
            exerciseName: performance.exerciseName,
            setEntries: completed.map {
                WorkoutSetEvidence(
                    reps: $0.actualReps,
                    externalWeightKG: $0.actualWeightKG
                )
            },
            restSeconds: rest,
            durationMinutes: nil
        )
    }
}
