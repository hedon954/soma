import Foundation
import SwiftData

/// ADR 0080：删除对话 Session 的聊天图，不删除业务记录。
@MainActor
enum ConversationSessionDeletion {
    enum Outcome: Equatable, Sendable {
        case deleted
        case refusedBusy
        case notFound
    }

    static func delete(
        sessionID: UUID,
        processingSessionID: UUID?,
        in context: ModelContext
    ) throws -> Outcome {
        if processingSessionID == sessionID {
            return .refusedBusy
        }

        var sessionDescriptor = FetchDescriptor<ConversationSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        sessionDescriptor.fetchLimit = 1
        guard let session = try context.fetch(sessionDescriptor).first else {
            return .notFound
        }

        let sessionJobs = try context.fetch(FetchDescriptor<AgentJob>(
            predicate: #Predicate { $0.sessionID == sessionID }
        ))
        if sessionJobs.contains(where: { !$0.state.isTerminal }) {
            return .refusedBusy
        }

        let sessionMessages = try context.fetch(FetchDescriptor<CoachMessage>(
            predicate: #Predicate { $0.sessionID == sessionID }
        ))
        let jobIDs = Set(sessionJobs.map(\.id))
        let turnIDs = Set(sessionJobs.map(\.turnID))
            .union(sessionMessages.compactMap(\.turnID))
        let traceIDs = Set(sessionMessages.compactMap(\.agentTraceID))
        let candidateMedia = Set(
            sessionJobs.flatMap(\.mediaAttachments).map(\.path)
                + sessionMessages.flatMap(\.mediaAttachments).map(\.path)
        )

        try context.transaction {
            for message in sessionMessages {
                context.delete(message)
            }
            for job in sessionJobs {
                context.delete(job)
            }

            var eventsByID: [UUID: PersistentAgentEvent] = [:]
            for jobID in jobIDs {
                let events = try context.fetch(FetchDescriptor<PersistentAgentEvent>(
                    predicate: #Predicate { $0.jobID == jobID }
                ))
                events.forEach { eventsByID[$0.id] = $0 }
            }
            for turnID in turnIDs {
                let events = try context.fetch(FetchDescriptor<PersistentAgentEvent>(
                    predicate: #Predicate { $0.turnID == turnID }
                ))
                events.forEach { eventsByID[$0.id] = $0 }
            }
            for event in eventsByID.values {
                context.delete(event)
            }

            var tracesByID: [UUID: AgentTrace] = [:]
            for traceID in traceIDs {
                let traces = try context.fetch(FetchDescriptor<AgentTrace>(
                    predicate: #Predicate { $0.id == traceID }
                ))
                traces.forEach { tracesByID[$0.id] = $0 }
            }
            for turnID in turnIDs {
                let traces = try context.fetch(FetchDescriptor<AgentTrace>(
                    predicate: #Predicate { $0.turnID == turnID }
                ))
                traces.forEach { tracesByID[$0.id] = $0 }
            }
            for trace in tracesByID.values {
                context.delete(trace)
            }

            for turnID in turnIDs {
                let receipts = try context.fetch(FetchDescriptor<AgentMutationReceipt>(
                    predicate: #Predicate { $0.turnID == turnID }
                ))
                receipts.forEach(context.delete)
            }

            let summaries = try context.fetch(FetchDescriptor<ConversationCompactionSummary>(
                predicate: #Predicate { $0.sessionID == sessionID }
            ))
            summaries.forEach(context.delete)

            context.delete(session)
            try context.save()
        }

        let retained = try MediaReferenceStore.referencedPaths(in: context)
        _ = PersonalDataStore.reclaimMedia(candidateMedia, excluding: retained)
        return .deleted
    }

    static func delete(
        _ session: ConversationSession,
        dataSpace: DataSpace,
        processingSessionID: UUID?,
        controller: ConversationSessionController,
        in context: ModelContext
    ) throws -> Outcome {
        let deletedID = session.id
        let wasActive = controller.activeSessionID == deletedID
        let outcome = try delete(
            sessionID: deletedID,
            processingSessionID: processingSessionID,
            in: context
        )
        guard outcome == .deleted, wasActive else { return outcome }
        controller.activateFallbackAfterDeletion(dataSpace: dataSpace, in: context)
        return outcome
    }
}
