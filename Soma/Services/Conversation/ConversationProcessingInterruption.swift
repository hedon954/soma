import Foundation
import SwiftData

@MainActor
extension ConversationProcessingService {
    /// 用户主动中断与可见失败共用 waitingForUser 屏障：保留已完成 step 和本地写入，
    /// 同一气泡出现重试入口，后续 FIFO 消息不会越过它自动执行。
    @discardableResult
    func interruptActiveProcessing(
        context: ConversationProcessingContext
    ) -> Bool {
        guard isProcessing,
              dataSpace == context.dataSpace,
              sessionID == context.session.id,
              let activeJobID
        else {
            return false
        }
        var descriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate { $0.id == activeJobID }
        )
        descriptor.fetchLimit = 1
        guard let job = try? context.modelContext.fetch(descriptor).first,
              [.running, .remoteRunning, .waitingForDevice]
              .contains(job.state)
        else {
            return false
        }

        let responseMessage: CoachMessage = if let responseID = job.responseMessageID,
                                               let existing = ConversationTurnPersistence.message(
                                                   id: responseID,
                                                   in: context.modelContext
                                               )
        {
            existing
        } else {
            ConversationTurnPersistence.bindResponseMessage(
                job: job,
                turnID: job.turnID,
                resumable: false,
                context: context
            ).0
        }

        let message = "已主动中断。点按重试可从已保存进度继续。"
        let event = AgentTraceEvent.failed(
            message: message,
            cancelled: true,
            at: .now
        )
        if let traceID = responseMessage.agentTraceID,
           let trace = trace(id: traceID, in: context.modelContext)
        {
            PersistentAgentEventProjection.persistAndProject(
                event,
                job: job,
                responseMessage: responseMessage,
                trace: trace,
                in: context.modelContext
            )
        } else {
            responseMessage.applyAgentEvent(event)
            _ = try? ConversationTurnPersistence.append(
                kind: .cancelled,
                payload: .init(message: message, cancelled: true),
                to: job,
                in: context.modelContext
            )
        }
        if responseMessage.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            responseMessage.text = message
        }
        responseMessage.agentStatus = .cancelled
        do {
            try ConversationTurnPersistence.waitForUser(
                job,
                message: message,
                in: context.modelContext
            )
            try ConversationTurnPersistence.stageFollowingJobs(
                after: job,
                message: "前一条消息已中断并等待手动重试；本条已按发送顺序暂存。",
                in: context.modelContext
            )
            try context.modelContext.save()
        } catch {
            context.modelContext.rollback()
            return false
        }

        if job.backend == .remote,
           let remoteJobID = job.remoteJobID,
           let endpoint = RemoteAgentPreference.baseURL()
        {
            Task {
                try? await RemoteAgentClient(baseURL: endpoint)
                    .cancel(remoteJobID: remoteJobID)
            }
        }
        processingTask?.cancel()
        return true
    }

    private func trace(id: UUID, in context: ModelContext) -> AgentTrace? {
        var descriptor = FetchDescriptor<AgentTrace>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
