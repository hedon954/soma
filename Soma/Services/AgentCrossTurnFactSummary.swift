import Foundation
import SwiftData

/// ADR 0047：从持久 tool span 提取跨轮写入事实，以及十轮外的意图 digest。
@MainActor
enum AgentCrossTurnFactSummary {
    static func recentMutationFacts(
        sessionID: UUID,
        excludingTurnID: UUID,
        limit: Int = 8,
        in context: ModelContext
    ) -> String? {
        let jobs = ((try? context.fetch(FetchDescriptor<AgentJob>())) ?? [])
            .filter { $0.sessionID == sessionID }
            .sorted { $0.createdAt > $1.createdAt }
        var lines: [String] = []
        for job in jobs where job.turnID != excludingTurnID {
            let events = AgentJobStore.events(for: job.id, in: context)
            for event in events.reversed() {
                guard event.kind == .span,
                      let span = event.payload.span,
                      span.kind == .tool,
                      span.status == .succeeded,
                      let output = span.output?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !output.isEmpty
                else {
                    continue
                }
                lines.append("- \(span.title)：\(String(output.prefix(160)))")
                if lines.count >= limit {
                    break
                }
            }
            if lines.count >= limit {
                break
            }
        }
        guard !lines.isEmpty else { return nil }
        return "本会话近期工具写入：\n\(lines.joined(separator: "\n"))"
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
