import Foundation
import SwiftData

extension DataIntegrityRepair {
    static func finalizeInterruptedAgentTraces(in context: ModelContext) {
        let traces = (try? context.fetch(FetchDescriptor<AgentTrace>())) ?? []
        let jobs = (try? context.fetch(FetchDescriptor<AgentJob>())) ?? []
        let durableRemoteTurnIDs = Set(jobs.compactMap { job in
            job.backend == .remote && !job.state.isTerminal
                ? job.turnID
                : nil
        })
        let resumableTurnIDs = Set(jobs.compactMap { job in
            job.hasResumableCheckpoint && !job.state.isTerminal
                ? job.turnID
                : nil
        })
        let interrupted = traces.filter {
            $0.status == .running
                && !($0.turnID.map(durableRemoteTurnIDs.contains) ?? false)
                && !($0.turnID.map(resumableTurnIDs.contains) ?? false)
        }
        let messages = (try? context.fetch(FetchDescriptor<CoachMessage>())) ?? []
        let interruptedMessages = messages.filter {
            $0.agentStatus == .running
                && !($0.turnID.map(durableRemoteTurnIDs.contains) ?? false)
        }
        guard !interrupted.isEmpty || !interruptedMessages.isEmpty else { return }

        let endedAt = Date()
        let failedMessage = "上一次 ReAct Agent 执行未正常结束，可能是 App 被关闭或任务被系统中断。"
        let recoverableMessage = "上次处理已保存进度，将自动从中断处继续。"
        for trace in interrupted {
            trace.apply(.span(AgentTraceSpan(
                kind: .output,
                title: "执行中断",
                status: .failed,
                startedAt: endedAt,
                endedAt: endedAt,
                errorMessage: failedMessage
            )))
            trace.apply(.failed(message: failedMessage, cancelled: false, at: endedAt))
        }
        var failedTurnIDs = Set<UUID>()
        for response in interruptedMessages {
            let resumable = response.turnID.map(resumableTurnIDs.contains) ?? false
            if resumable {
                response.agentStatus = .cancelled
                let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    response.text = recoverableMessage
                }
                // 对应 job 会在 resumePendingJobs 中以同气泡续跑。
                continue
            }
            if let turnID = response.turnID {
                failedTurnIDs.insert(turnID)
            }
            response.agentStatus = .failed
            response.applyAgentEvent(.failed(
                message: failedMessage,
                cancelled: false,
                at: endedAt
            ))
            response.text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? failedMessage : response.text
            response.replaceAgentEvents(response.agentEvents.map { event in
                guard event.status == .running else { return event }
                var failed = event
                failed.statusRaw = AgentTraceStatus.failed.rawValue
                failed.endedAt = endedAt
                failed.errorMessage = failedMessage
                return failed
            })
        }
        for job in jobs where !job.state.isTerminal {
            if resumableTurnIDs.contains(job.turnID) {
                if job.state == .running {
                    job.pauseLoopRuntime(at: min(job.leaseExpiresAt ?? endedAt, endedAt))
                    try? job.transition(to: .waitingForForeground, at: endedAt)
                    job.leaseOwner = nil
                    job.leaseExpiresAt = nil
                }
                continue
            }
            // 无检查点的中断：UI 已标失败时，Job 也必须终态失败，避免回前台自动重跑。
            guard failedTurnIDs.contains(job.turnID) else {
                continue
            }
            if job.state.canTransition(to: .failed) {
                try? job.transition(to: .failed, at: endedAt, error: failedMessage)
                job.leaseOwner = nil
                job.leaseExpiresAt = nil
                job.loopCheckpoint = nil
                job.lastCompletedStep = 0
                _ = try? AgentJobStore.append(
                    kind: .failed,
                    payload: .init(message: failedMessage),
                    to: job,
                    in: context,
                    at: endedAt
                )
            }
        }
        try? context.save()
    }
}
