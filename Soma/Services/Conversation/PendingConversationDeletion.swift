import Foundation
import SwiftData

enum PendingConversationDeletionError: LocalizedError {
    case busy, unavailable, remoteUnavailable, remoteCancellationFailed, saveFailed

    var errorDescription: String? {
        switch self {
        case .busy: "消息仍在处理中。请先停止当前回复，再删除暂存消息。"
        case .unavailable: "这条消息已不在暂存队列中，请关闭暂存管理后重新查看。"
        case .remoteUnavailable: "暂时无法连接后台处理服务，尚未删除消息。请恢复后台处理配置后重试删除。"
        case .remoteCancellationFailed: "未能确认后台任务已停止，暂存消息仍保留。请检查网络后重试删除。"
        case .saveFailed: "未能保存删除结果，暂存消息仍保留。请检查可用存储空间后重试删除。"
        }
    }
}

@MainActor
enum PendingConversationDeletion {
    static func isDeletable(_ job: AgentJob) -> Bool {
        [.staged, .waitingForUser, .queued, .waitingForNetwork].contains(job.state)
    }

    static func jobs(dataSpace: DataSpace, turnID: UUID? = nil, in context: ModelContext) throws -> [AgentJob] {
        let space = dataSpace.rawValue
        let jobs = try context.fetch(FetchDescriptor<AgentJob>(
            predicate: #Predicate { $0.dataSpaceRaw == space },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
        return jobs.filter { isDeletable($0) && (turnID == nil || $0.turnID == turnID) }
    }

    static func cancelRemote(_ remoteJobID: String) async throws {
        guard let endpoint = RemoteAgentPreference.baseURL() else {
            throw PendingConversationDeletionError.remoteUnavailable
        }
        do {
            try await RemoteAgentClient(baseURL: endpoint).cancel(remoteJobID: remoteJobID)
        } catch {
            throw PendingConversationDeletionError.remoteCancellationFailed
        }
    }

    /// The caller blocks the runner until remote cancellation and the local transaction finish.
    static func remove(
        _ jobs: [AgentJob],
        in context: ModelContext,
        protectedMediaPaths: Set<String> = []
    ) throws {
        var candidateMedia = Set(jobs.flatMap(\.mediaAttachments).map(\.path))
        do {
            try context.transaction {
                for job in jobs {
                    let turnID = job.turnID
                    let jobID = job.id
                    let messages = try context.fetch(FetchDescriptor<CoachMessage>(
                        predicate: #Predicate { $0.turnID == turnID }
                    ))
                    candidateMedia.formUnion(messages.flatMap(\.mediaAttachments).map(\.path))
                    let events = try context.fetch(FetchDescriptor<PersistentAgentEvent>(
                        predicate: #Predicate { $0.jobID == jobID }
                    ))
                    let traces = try context.fetch(FetchDescriptor<AgentTrace>(
                        predicate: #Predicate { $0.turnID == turnID }
                    ))
                    events.forEach(context.delete)
                    traces.forEach(context.delete)
                    messages.forEach(context.delete)
                    context.delete(job)
                }
                try context.save()
            }
        } catch {
            context.rollback()
            throw PendingConversationDeletionError.saveFailed
        }
        // A failed reference scan must leave files in place. It cannot undo a committed deletion.
        if let retained = try? MediaReferenceStore.referencedPaths(in: context) {
            _ = PersonalDataStore.reclaimMedia(candidateMedia, excluding: retained.union(protectedMediaPaths))
        }
    }
}
