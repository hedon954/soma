import Foundation
import SwiftData

enum TrainingCompletionEvidence {
    /// Use only reliably matched actual training days. Missing identifiers and partial history produce no suggestion.
    static func matchesUsualSession(today: [UUID: Int], history: [[UUID: Int]]) -> Bool {
        guard today.count >= 2 else { return false }
        let comparable = Array(history.filter { day in
            guard day.count >= 2 else { return false }
            let common = day.keys.filter { today[$0] != nil }.count
            return common * 5 >= day.count * 4 && common * 5 >= today.count * 4
        }.prefix(6))
        guard comparable.count >= 3 else { return false }
        let fulfilled = comparable.filter { prior in
            prior.allSatisfy { exercise, sets in
                // A suggestion requires completed work for every exercise in the comparable routine.
                today[exercise, default: 0] >= sets
            }
        }
        return fulfilled.count * 2 >= comparable.count
    }
}

@ModelActor
actor TrainingCompletionEvidenceLoader {
    func hasUsualCompletedSession(on date: Date, calendar: Calendar = .current) throws -> Bool {
        let today = calendar.startOfDay(for: date)
        guard let first = calendar.date(byAdding: .day, value: -56, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today)
        else { return false }
        var query = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.date >= first && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        query.fetchLimit = 600
        let workouts = try modelContext.fetch(query)
        try Task.checkCancellation()
        var days: [Date: [UUID: Int]] = [:]
        for workout in workouts {
            guard !workout.isDailyActivity, let id = workout.exerciseID,
                  let count = workout.setCount, count > 0
            else { continue }
            days[calendar.startOfDay(for: workout.date), default: [:]][id, default: 0] += count
        }
        guard let current = days.removeValue(forKey: today) else { return false }
        let history = days.sorted { $0.key > $1.key }.map(\.value)
        return TrainingCompletionEvidence.matchesUsualSession(today: current, history: history)
    }
}
