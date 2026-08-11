import Foundation
import SwiftData

/// ADR 0056：跨轮只注入稳定记录引用与十轮外意图 digest，不重复长 Tool observation。
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
        let workouts = ((try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? [])
            .filter {
                $0.sourceSessionID == sessionID && $0.sourceTurnID != excludingTurnID
            }
            .map {
                Fact(
                    date: $0.date,
                    line: "- write workout id=\($0.id.uuidString.lowercased()) title=\($0.exercise) time=\($0.date.ISO8601Format())"
                )
            }
        let meals = ((try? context.fetch(FetchDescriptor<MealEntry>())) ?? [])
            .filter {
                $0.sourceSessionID == sessionID && $0.sourceTurnID != excludingTurnID
            }
            .map {
                Fact(
                    date: $0.date,
                    line: "- write meal id=\($0.id.uuidString.lowercased()) title=\($0.title) time=\($0.date.ISO8601Format())"
                )
            }
        let bodies = ((try? context.fetch(FetchDescriptor<BodyEntry>())) ?? [])
            .filter {
                $0.sourceSessionID == sessionID && $0.sourceTurnID != excludingTurnID
            }
            .map {
                Fact(
                    date: $0.date,
                    line: "- write body id=\($0.id.uuidString.lowercased()) time=\($0.date.ISO8601Format())"
                )
            }
        let lines = (workouts + meals + bodies)
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map(\.line)
        guard !lines.isEmpty else { return nil }
        return "本会话近期记录引用：\n\(lines.joined(separator: "\n"))"
    }

    static func olderTurnDigest(
        messages: [CoachMessage],
        sessionID: UUID,
        excludingTurnID: UUID,
        keepingLatest: Int = 10
    ) -> String? {
        let sessionMessages = messages
            .filter { $0.sessionID == sessionID }
            .sorted { $0.date < $1.date }
        let userTurns = sessionMessages.filter { !$0.isFromCoach && $0.turnID != excludingTurnID }
        guard userTurns.count > keepingLatest else { return nil }
        let older = userTurns.dropLast(keepingLatest).suffix(8)
        let lines = older.map { message -> String in
            let keywords = keywordDigest(message.text)
            let recordHints = sessionMessages
                .filter { $0.isFromCoach && $0.turnID == message.turnID && $0.agentStatus == .succeeded }
                .compactMap(\.recordType?.rawValue)
            let records = recordHints.isEmpty
                ? ""
                : "；落库 \(recordHints.joined(separator: "/"))"
            return "- \(keywords)\(records)"
        }
        guard !lines.isEmpty else { return nil }
        return "更早轮次摘要：\n\(lines.joined(separator: "\n"))"
    }

    private static func keywordDigest(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "（无文字）"
        }
        if trimmed.count <= 36 {
            return trimmed
        }
        return String(trimmed.prefix(36)) + "…"
    }
}
