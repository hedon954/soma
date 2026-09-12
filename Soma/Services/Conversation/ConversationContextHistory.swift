import Foundation
import SwiftData

@MainActor
enum ConversationContextHistory {
    static func trustedTimes(sessionID: UUID, in context: ModelContext) -> [UUID: TrustedTurnContext] {
        var descriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 128
        var result: [UUID: TrustedTurnContext] = [:]
        while let page = try? context.fetch(descriptor), !page.isEmpty {
            for job in page {
                if let time = job.contextSnapshot?.envelope?.trustedTime {
                    result[job.turnID] = time
                }
            }
            if page.count < 128 {
                break
            }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + page.count
        }
        return result
    }

    static func canonicalTurns(sessionID: UUID, in context: ModelContext) -> [UUID: AgentCanonicalTurn] {
        var descriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 128
        var result: [UUID: AgentCanonicalTurn] = [:]
        while let page = try? context.fetch(descriptor), !page.isEmpty {
            for job in page where job.state == .succeeded {
                if let turn = job.contextSnapshot?.canonicalTurn {
                    result[job.turnID] = turn
                }
            }
            if page.count < 128 {
                break
            }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + page.count
        }
        return result
    }

    /// Read only conversation messages in bounded database pages. Extra attempts must
    /// not displace the latest thirty user turns as an arbitrary 80-message limit did.
    static func messages(sessionID: UUID, in context: ModelContext) -> [CoachMessage] {
        var descriptor = FetchDescriptor<CoachMessage>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.date), SortDescriptor(\.id)]
        )
        descriptor.fetchLimit = 128
        var result: [CoachMessage] = []
        while let page = try? context.fetch(descriptor), !page.isEmpty {
            result.append(contentsOf: page)
            if page.count < 128 {
                break
            }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + page.count
        }
        return result
    }
}
