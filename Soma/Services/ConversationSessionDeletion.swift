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

        let sessions = try context.fetch(FetchDescriptor<ConversationSession>())
        guard sessions.contains(where: { $0.id == sessionID }) else {
            return .notFound
        }

        let jobs = try context.fetch(FetchDescriptor<AgentJob>())
        let sessionJobs = jobs.filter { $0.sessionID == sessionID }
        if sessionJobs.contains(where: { !$0.state.isTerminal }) {
            return .refusedBusy
        }

        let messages = try context.fetch(FetchDescriptor<CoachMessage>())
        let sessionMessages = messages.filter { $0.sessionID == sessionID }
        let jobIDs = Set(sessionJobs.map(\.id))
        let turnIDs = Set(sessionJobs.map(\.turnID))
            .union(sessionMessages.compactMap(\.turnID))
        let traceIDs = Set(sessionMessages.compactMap(\.agentTraceID))
        let oldMedia = try PersonalDataSnapshot.capture(from: context).referencedMediaPaths

        try context.transaction {
            for message in sessionMessages {
                context.delete(message)
            }
            for job in sessionJobs {
                context.delete(job)
            }

            let events = try context.fetch(FetchDescriptor<PersistentAgentEvent>())
            for event in events
                where jobIDs.contains(event.jobID) || turnIDs.contains(event.turnID)
            {
                context.delete(event)
            }

            let traces = try context.fetch(FetchDescriptor<AgentTrace>())
            for trace in traces where shouldDeleteTrace(
                trace,
                turnIDs: turnIDs,
                traceIDs: traceIDs
            ) {
                context.delete(trace)
            }

            let receipts = try context.fetch(FetchDescriptor<AgentMutationReceipt>())
            for receipt in receipts where turnIDs.contains(receipt.turnID) {
                context.delete(receipt)
            }

            let summaries = try context.fetch(
                FetchDescriptor<ConversationCompactionSummary>()
            )
            for summary in summaries where summary.sessionID == sessionID {
                context.delete(summary)
            }

            for session in sessions where session.id == sessionID {
                context.delete(session)
            }
            try context.save()
        }

        let retained = try PersonalDataSnapshot.capture(from: context).referencedMediaPaths
        _ = PersonalDataStore.reclaimMedia(oldMedia, excluding: retained)
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

    private static func shouldDeleteTrace(
        _ trace: AgentTrace,
        turnIDs: Set<UUID>,
        traceIDs: Set<UUID>
    ) -> Bool {
        if traceIDs.contains(trace.id) {
            return true
        }
        guard let turnID = trace.turnID else { return false }
        return turnIDs.contains(turnID)
    }
}
