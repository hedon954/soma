import Foundation
import SwiftData

@MainActor
enum LocalEnergyTraining {
    static func intervals(in window: DailyActivityWindow, context: ModelContext) throws -> [EnergyTimeInterval] {
        guard let first = window.days.first, let last = window.days.last else { return [] }
        let start = first.start, end = last.end
        let sessions = try read(FetchDescriptor<WorkoutSession>(predicate: #Predicate {
            $0.startedAt < end && ($0.endedAt ?? end) > start
        }), context: context)
        let sessionIDs = sessions.map(\.id)
        guard !sessionIDs.isEmpty else { return [] }
        let performances = try read(FetchDescriptor<ExercisePerformance>(predicate: #Predicate { sessionIDs.contains($0.sessionID) }), context: context)
        let performanceIDs = performances.map(\.id)
        guard !performanceIDs.isEmpty else { return [] }
        let sets = try read(FetchDescriptor<WorkoutSet>(predicate: #Predicate { performanceIDs.contains($0.performanceID) }), context: context)
        let measured = Set(sets.compactMap { set -> UUID? in
            guard let start = set.startedAt, let end = set.completedAt, end > start else { return nil }
            return set.performanceID
        })
        let measuredSessions = Set(performances.filter { measured.contains($0.id) }.map(\.sessionID))
        return sessions.compactMap { session in
            // Materialized manual records carry zero-length timestamps, not measured session bounds.
            guard measuredSessions.contains(session.id), let ended = session.endedAt, ended > session.startedAt else { return nil }
            return .init(start: session.startedAt, end: ended)
        }
    }

    private static func read<Model: PersistentModel>(_ request: FetchDescriptor<Model>, context: ModelContext) throws -> [Model] {
        var query = request
        query.fetchLimit = 256
        var result: [Model] = []
        while true {
            try Task.checkCancellation()
            let page = try context.fetch(query)
            result += page
            if page.count < 256 {
                return result
            }
            query.fetchOffset = (query.fetchOffset ?? 0) + page.count
        }
    }
}
