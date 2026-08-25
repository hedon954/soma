import Foundation
import SwiftData

struct ExerciseLibraryRecentWorkout: Equatable, Sendable {
    let date: Date
    let summary: String
}

/// Replaces one live SwiftData query per visible exercise row with one bounded,
/// background pass. The list can now materialize rows without query fan-out.
@ModelActor
actor ExerciseRecentWorkoutSnapshotLoader {
    func load(limit: Int = 5000) throws -> [UUID: ExerciseLibraryRecentWorkout] {
        var descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.exerciseID != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = max(limit, 1)
        let workouts = try modelContext.fetch(descriptor)
        try Task.checkCancellation()

        var latestByExerciseID: [UUID: ExerciseLibraryRecentWorkout] = [:]
        latestByExerciseID.reserveCapacity(min(workouts.count, 500))
        for workout in workouts {
            try Task.checkCancellation()
            guard let exerciseID = workout.exerciseID,
                  latestByExerciseID[exerciseID] == nil
            else {
                continue
            }
            latestByExerciseID[exerciseID] = ExerciseLibraryRecentWorkout(
                date: workout.date,
                summary: ExerciseQuickFill.text(for: workout)
            )
        }
        return latestByExerciseID
    }
}
