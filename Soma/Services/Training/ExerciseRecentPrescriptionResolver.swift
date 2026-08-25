import Foundation
import SwiftData

struct RecentExercisePrescription: Equatable, Sendable {
    var sourceDate: Date
    var setCount: Int?
    var reps: Int?
    var weightKG: Double?
    var restSeconds: Int?
    var firstSetIsWarmup: Bool?

    var summary: String {
        var values: [String] = []
        if let weightKG, let reps {
            let weight = weightKG == 0
                ? "自重"
                : "\(weightKG.formatted()) kg"
            values.append("\(weight) × \(reps)")
        } else {
            if let weightKG {
                values.append(weightKG == 0 ? "自重" : "\(weightKG.formatted()) kg")
            }
            if let reps {
                values.append("\(reps) 次")
            }
        }
        if let setCount {
            values.append("\(setCount) 组")
        }
        if let restSeconds {
            values.append("间歇 \(Self.durationText(restSeconds))")
        }
        return values.joined(separator: " · ")
    }

    private static func durationText(_ seconds: Int) -> String {
        if seconds > 0, seconds.isMultiple(of: 60) {
            return "\(seconds / 60) 分钟"
        }
        return "\(seconds) 秒"
    }
}

enum ExerciseRecentPrescriptionResolver {
    @MainActor
    static func latest(
        exerciseID: UUID,
        in context: ModelContext
    ) -> RecentExercisePrescription? {
        var workoutDescriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.exerciseID == exerciseID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = 100
        let workouts = (try? context.fetch(workoutDescriptor)) ?? []
        let performances = (
            try? context.fetch(FetchDescriptor<ExercisePerformance>(
                predicate: #Predicate { $0.exerciseID == exerciseID }
            ))
        ) ?? []
        let sessions = performances.reduce(into: [UUID: WorkoutSession]()) { result, performance in
            if let session = performance.session {
                result[session.id] = session
                return
            }
            guard result[performance.sessionID] == nil else { return }
            let sessionID = performance.sessionID
            var descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.id == sessionID }
            )
            descriptor.fetchLimit = 1
            if let session = try? context.fetch(descriptor).first {
                result[session.id] = session
            }
        }.values.map { $0 }
        let sets = (
            try? context.fetch(FetchDescriptor<WorkoutSet>(
                predicate: #Predicate {
                    $0.performance?.exerciseID == exerciseID
                }
            ))
        ) ?? []
        return latest(
            exerciseID: exerciseID,
            workouts: workouts,
            sessions: sessions,
            performances: performances,
            sets: sets
        )
    }

    static func latest(
        exerciseID: UUID,
        workouts: [WorkoutEntry],
        sessions: [WorkoutSession],
        performances: [ExercisePerformance],
        sets: [WorkoutSet]
    ) -> RecentExercisePrescription? {
        let performancesByID = Dictionary(uniqueKeysWithValues: performances.map {
            ($0.id, $0)
        })
        var candidates = workouts.compactMap { workout -> RecentExercisePrescription? in
            guard workout.exerciseID == exerciseID else { return nil }
            let completed = workout.sourcePerformanceID.flatMap { performanceID in
                performancesByID[performanceID].map { performance in
                    sets.filter {
                        $0.performanceID == performance.id
                            && $0.status == .completed
                    }
                    .sorted { $0.order < $1.order }
                }
            } ?? []
            let evidence: [WorkoutSetEvidence]
            if completed.count == workout.setEntries.count {
                let working = zip(completed, workout.setEntries)
                    .filter { $0.0.kind != .warmup }
                    .map(\.1)
                evidence = working.isEmpty ? workout.setEntries : working
            } else {
                evidence = workout.setEntries
            }
            return RecentExercisePrescription(
                sourceDate: workout.date,
                setCount: workout.setCount,
                reps: uniform(
                    evidence.compactMap(\.reps),
                    count: evidence.count
                ) ?? workout.representativeReps,
                weightKG: uniform(
                    evidence.compactMap(\.externalWeightKG),
                    count: evidence.count
                ) ?? workout.representativeWeight,
                restSeconds: workout.restSeconds,
                firstSetIsWarmup: completed.first.map { $0.kind == .warmup }
            )
        }

        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map {
            ($0.id, $0)
        })
        let projectedPerformanceIDs = Set(
            workouts.compactMap(\.sourcePerformanceID)
        )
        for performance in performances
            where performance.exerciseID == exerciseID
            && performance.status == .completed
            && !projectedPerformanceIDs.contains(performance.id)
            && !performance.workoutProjectionSuppressed
        {
            guard let session = sessionsByID[performance.sessionID] else {
                continue
            }
            let completed = sets
                .filter {
                    $0.performanceID == performance.id
                        && $0.status == .completed
                }
                .sorted { $0.order < $1.order }
            guard !completed.isEmpty else { continue }
            let working = completed.filter { $0.kind != .warmup }
            let capacitySets = working.isEmpty ? completed : working
            candidates.append(RecentExercisePrescription(
                sourceDate: session.startedAt,
                setCount: completed.count,
                reps: uniform(capacitySets.compactMap(\.actualReps), count: capacitySets.count),
                weightKG: uniform(
                    capacitySets.compactMap(\.actualWeightKG),
                    count: capacitySets.count
                ),
                restSeconds: uniform(
                    completed.compactMap(\.actualRestSeconds),
                    count: completed.count
                ),
                firstSetIsWarmup: completed.first?.kind == .warmup
            ))
        }

        return candidates.max { $0.sourceDate < $1.sourceDate }
    }

    private static func uniform<T: Hashable>(
        _ values: [T],
        count: Int
    ) -> T? {
        guard values.count == count,
              Set(values).count == 1
        else {
            return nil
        }
        return values.first
    }
}
