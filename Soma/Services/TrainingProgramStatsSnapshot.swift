import Foundation
import SwiftData

struct TrainingProgramStatsSnapshot: Equatable, Sendable {
    let summariesBySessionID: [UUID: TrainingSessionSummary]

    static let empty = TrainingProgramStatsSnapshot(summariesBySessionID: [:])
}

/// Training statistics are secondary, collapsed content. Fetching them must not
/// participate in the training root or program-detail first frame.
@ModelActor
actor TrainingProgramStatsSnapshotLoader {
    func load(
        programID: UUID,
        limit: Int = 12
    ) throws -> TrainingProgramStatsSnapshot {
        try Task.checkCancellation()
        let completed = WorkoutSessionStatus.completed.rawValue
        let abandoned = WorkoutSessionStatus.abandoned.rawValue
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate {
                $0.programID == programID
                    && ($0.statusRaw == completed || $0.statusRaw == abandoned)
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(limit, 1)
        let sessions = try modelContext.fetch(descriptor)
        try Task.checkCancellation()

        return try TrainingProgramStatsSnapshot(
            summariesBySessionID: summaries(for: sessions)
        )
    }

    func load(sessionID: UUID) throws -> TrainingSessionSummary? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        descriptor.fetchLimit = 1
        guard let session = try modelContext.fetch(descriptor).first else {
            return nil
        }
        return try summaries(for: [session])[sessionID]
    }

    private func summaries(
        for sessions: [WorkoutSession]
    ) throws -> [UUID: TrainingSessionSummary] {
        var summaries: [UUID: TrainingSessionSummary] = [:]
        summaries.reserveCapacity(sessions.count)
        for session in sessions {
            try Task.checkCancellation()
            let performances = session.performances
            let sets = performances.flatMap(\.workoutSets)
            let efforts = sets.flatMap(\.efforts)
            let workoutsByPerformanceID = performances.reduce(
                into: [UUID: WorkoutEntry]()
            ) { result, performance in
                guard !performance.workoutProjectionSuppressed,
                      let workout = performance.projectedWorkout
                else {
                    return
                }
                result[performance.id] = workout
            }
            summaries[session.id] = TrainingSessionSummaryCalculator.make(
                session: session,
                performances: performances,
                sets: sets,
                efforts: efforts,
                workoutsByPerformanceID: workoutsByPerformanceID
            )
        }
        return summaries
    }
}

enum TrainingSessionSummaryCalculator {
    static func make(
        session: WorkoutSession?,
        performances: [ExercisePerformance],
        sets: [WorkoutSet],
        efforts: [WorkoutEffort],
        workoutsByPerformanceID: [UUID: WorkoutEntry]
    ) -> TrainingSessionSummary {
        let projectedWorkouts = Array(workoutsByPerformanceID.values)
        let summaryEnd = session?.endedAt
            ?? sets.compactMap(\.completedAt).max()
            ?? session?.startedAt
            ?? .now
        let mediaPaths = Set(
            sets.compactMap(\.recordedVideoPath)
                + efforts.compactMap(\.recordedVideoPath)
                + performances.compactMap(\.activeVideoPath)
                + projectedWorkouts.flatMap(\.mediaAttachments).map(\.path)
        )
        let setsByPerformanceID = Dictionary(grouping: sets, by: \.performanceID)
        let effortsBySetID = Dictionary(grouping: efforts, by: \.workoutSetID)
        let exerciseSummaries = performances
            .sorted { $0.order < $1.order }
            .map { performance in
                let performanceSets = setsByPerformanceID[performance.id] ?? []
                let projectedWorkout = workoutsByPerformanceID[performance.id]
                let performanceEfforts = performanceSets.flatMap {
                    effortsBySetID[$0.id] ?? []
                }
                return TrainingExerciseSummary(
                    id: performance.id,
                    name: performance.exerciseName,
                    completedSets: performanceSets.count {
                        $0.status == .completed
                    },
                    partialSets: performanceSets.count {
                        $0.status == .partial
                    },
                    skippedSets: performanceSets.count {
                        $0.status == .skipped
                    },
                    failedSets: performanceSets.count {
                        $0.status == .failed
                    },
                    completedVolume: performance.workoutProjectionSuppressed
                        ? 0
                        : projectedWorkout?.estimatedVolume
                        ?? completedVolume(
                            sets: performanceSets,
                            efforts: performanceEfforts
                        )
                )
            }
        let caloriePerformanceIDs = Set(exerciseSummaries.filter {
            $0.completedSets > 0 || $0.partialSets > 0
        }.map(\.id))
        let calorieValues = caloriePerformanceIDs.compactMap {
            workoutsByPerformanceID[$0]?.estimatedCalories
        }
        let sessionCalories = !caloriePerformanceIDs.isEmpty
            && calorieValues.count == caloriePerformanceIDs.count
            ? calorieValues.reduce(0, +)
            : nil
        return TrainingSessionSummary(
            completedSets: exerciseSummaries.reduce(0) { $0 + $1.completedSets },
            partialSets: exerciseSummaries.reduce(0) { $0 + $1.partialSets },
            skippedSets: sets.count { $0.status == .skipped },
            failedSets: sets.count { $0.status == .failed },
            completedVolume: exerciseSummaries.reduce(0) { $0 + $1.completedVolume },
            exerciseCount: exerciseSummaries.count {
                $0.completedSets > 0 || $0.partialSets > 0
            },
            durationSeconds: max(
                Int(summaryEnd.timeIntervalSince(session?.startedAt ?? summaryEnd)),
                0
            ),
            recordedVideoCount: mediaPaths.count,
            estimatedCalories: sessionCalories,
            exercises: exerciseSummaries
        )
    }

    private static func completedVolume(
        sets: [WorkoutSet],
        efforts: [WorkoutEffort]
    ) -> Double {
        let effortVolume = efforts.compactMap(\.completedVolume).reduce(0, +)
        let hasCompletedEffort = efforts.contains { $0.status == .completed }
        return hasCompletedEffort
            ? effortVolume
            : sets.compactMap(\.completedVolume).reduce(0, +)
    }
}
