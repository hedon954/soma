import Foundation
import SwiftData

@MainActor
enum GuidedWorkoutRecordStore {
    @discardableResult
    static func materialize(
        performance: ExercisePerformance,
        session: WorkoutSession,
        in context: ModelContext
    ) throws -> WorkoutEntry? {
        guard !performance.workoutProjectionSuppressed else { return nil }
        if let existing = try context.fetch(FetchDescriptor<WorkoutEntry>())
            .first(where: { $0.sourcePerformanceID == performance.id })
        {
            return existing
        }

        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
            .filter { $0.performanceID == performance.id }
            .sorted { $0.order < $1.order }
        guard !sets.isEmpty,
              sets.allSatisfy({ $0.status == .completed || $0.status == .skipped })
        else {
            return nil
        }

        let completed = sets.filter { $0.status == .completed }
        guard !completed.isEmpty else { return nil }

        let attachments = stableVideoAttachments(
            completed.compactMap(\.recordedVideoPath)
                + [performance.activeVideoPath].compactMap { $0 }
        )
        let entry = WorkoutEntry(
            date: session.startedAt,
            exercise: performance.exerciseName,
            exerciseID: performance.exerciseID,
            setEntries: completed.map { set in
                WorkoutSetEvidence(
                    reps: validReps(set.actualReps),
                    externalWeightKG: validWeight(set.actualWeightKG)
                )
            },
            restSeconds: uniform(
                completed.compactMap(\.actualRestSeconds),
                count: completed.count
            ),
            notes: performance.notes,
            mediaAttachments: attachments,
            sourceWorkoutSessionID: session.id,
            sourcePerformanceID: performance.id
        )
        context.insert(entry)
        return entry
    }

    static func delete(
        _ workout: WorkoutEntry,
        in context: ModelContext
    ) throws {
        if let performanceID = workout.sourcePerformanceID,
           let performance = try context
           .fetch(FetchDescriptor<ExercisePerformance>())
           .first(where: { $0.id == performanceID })
        {
            performance.workoutProjectionSuppressed = true
        }
        context.delete(workout)
        try context.save()
    }

    @discardableResult
    static func backfill(in context: ModelContext) -> Int {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let existingPerformanceIDs = Set(
            ((try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? [])
                .compactMap(\.sourcePerformanceID)
        )
        let performances = (
            (try? context.fetch(FetchDescriptor<ExercisePerformance>())) ?? []
        ).filter { !existingPerformanceIDs.contains($0.id) }

        var created = 0
        for performance in performances {
            guard let session = sessionsByID[performance.sessionID],
                  (try? materialize(
                      performance: performance,
                      session: session,
                      in: context
                  )) != nil
            else {
                continue
            }
            created += 1
        }
        if created > 0 {
            try? context.save()
        }
        return created
    }

    private static func validReps(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func validWeight(_ value: Double?) -> Double? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private static func uniform<T: Hashable>(
        _ values: [T],
        count: Int
    ) -> T? {
        guard values.count == count, Set(values).count == 1 else { return nil }
        return values.first
    }

    private static func stableVideoAttachments(
        _ paths: [String]
    ) -> [MediaAttachmentReference] {
        var seen = Set<String>()
        return paths.compactMap { path in
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return MediaAttachmentReference(kind: .video, path: path)
        }
    }
}
