import Foundation
import SwiftData

/// ADR 0056：跨轮只注入稳定记录引用；较早对话由统一窗口摘要管理。
@MainActor
enum AgentCrossTurnFactSummary {
    static func recentMutationFacts(
        sessionID: UUID,
        excludingTurnID: UUID,
        limit: Int = 8,
        in context: ModelContext
    ) -> String? {
        struct Fact {
            var date: Date
            var line: String
        }
        var workoutDescriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.sourceSessionID == sessionID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = limit
        let workouts = ((try? context.fetch(workoutDescriptor)) ?? [])
            .filter { $0.sourceTurnID != excludingTurnID }
            .compactMap { workout -> Fact? in
                AgentFacingRecordID.factLine(
                    kind: "workout",
                    businessID: workout.businessID,
                    title: workout.exercise,
                    date: workout.date
                ).map { Fact(date: workout.date, line: $0) }
            }
        var mealDescriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.sourceSessionID == sessionID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        mealDescriptor.fetchLimit = limit
        let meals = ((try? context.fetch(mealDescriptor)) ?? [])
            .filter { $0.sourceTurnID != excludingTurnID }
            .compactMap { meal -> Fact? in
                AgentFacingRecordID.factLine(
                    kind: "meal",
                    businessID: meal.businessID,
                    title: meal.title,
                    date: meal.date
                ).map { Fact(date: meal.date, line: $0) }
            }
        var bodyDescriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.sourceSessionID == sessionID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        bodyDescriptor.fetchLimit = limit
        let bodies = ((try? context.fetch(bodyDescriptor)) ?? [])
            .filter { $0.sourceTurnID != excludingTurnID }
            .compactMap { body -> Fact? in
                AgentFacingRecordID.factLine(
                    kind: "body",
                    businessID: body.businessID,
                    title: nil,
                    date: body.date
                ).map { Fact(date: body.date, line: $0) }
            }
        let lines = (workouts + meals + bodies)
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map(\.line)
        guard !lines.isEmpty else { return nil }
        return "本会话近期记录引用：\n\(lines.joined(separator: "\n"))"
    }
}
