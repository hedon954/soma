import Foundation
import SwiftData

/// 对话写入路径的持久化门面：Job/Event 与回复气泡投影都从这里进出。
/// 底层仍复用 `AgentJobStore`，不改变幂等、FIFO 暂存或 Event 序号语义。
@MainActor
enum ConversationTurnPersistence {
    static func enqueue(
        _ job: AgentJob,
        userMessage: CoachMessage,
        in context: ModelContext,
        at date: Date = .now
    ) throws {
        try AgentJobStore.enqueue(job, userMessage: userMessage, in: context, at: date)
    }

    @discardableResult
    static func append(
        kind: PersistentAgentEventKind,
        payload: PersistentAgentEventPayload = .init(),
        to job: AgentJob,
        in context: ModelContext,
        at date: Date = .now
    ) throws -> PersistentAgentEvent {
        try AgentJobStore.append(
            kind: kind,
            payload: payload,
            to: job,
            in: context,
            at: date
        )
    }

    static func claim(
        _ job: AgentJob,
        owner: String,
        now: Date = .now,
        leaseDuration: TimeInterval = 25,
        in context: ModelContext
    ) throws {
        try AgentJobStore.claim(
            job,
            owner: owner,
            now: now,
            leaseDuration: leaseDuration,
            in: context
        )
    }

    static func recoverExpiredLeases(
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext
    ) throws -> [UUID] {
        try AgentJobStore.recoverExpiredLeases(dataSpace: dataSpace, now: now, in: context)
    }

    static func resumeForegroundJobs(
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext
    ) throws -> [UUID] {
        try AgentJobStore.resumeForegroundJobs(dataSpace: dataSpace, now: now, in: context)
    }

    @discardableResult
    static func promoteFailedResponsesToManualRetry(
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext
    ) throws -> [UUID] {
        try AgentJobStore.promoteFailedResponsesToManualRetry(
            dataSpace: dataSpace,
            now: now,
            in: context
        )
    }

    static func stage(
        _ job: AgentJob,
        message: String,
        retryDelay: TimeInterval?,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        try AgentJobStore.stage(
            job,
            message: message,
            retryDelay: retryDelay,
            now: now,
            in: context
        )
    }

    static func waitForUser(
        _ job: AgentJob,
        message: String,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        try AgentJobStore.waitForUser(job, message: message, now: now, in: context)
    }

    static func stageFollowingJobs(
        after blockingJob: AgentJob,
        message: String,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        try AgentJobStore.stageFollowingJobs(
            after: blockingJob,
            message: message,
            now: now,
            in: context
        )
    }

    static func releaseForManualRetry(
        _ job: AgentJob,
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        try AgentJobStore.releaseForManualRetry(
            job,
            dataSpace: dataSpace,
            now: now,
            in: context
        )
    }

    @discardableResult
    static func releasePendingQueueForManualRetry(
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext
    ) throws -> [UUID] {
        try AgentJobStore.releasePendingQueueForManualRetry(
            dataSpace: dataSpace,
            now: now,
            in: context
        )
    }

    static func releaseStagedJobs(
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext,
        isReady: (AgentJob) -> Bool = { _ in true }
    ) throws -> [UUID] {
        try AgentJobStore.releaseStagedJobs(
            dataSpace: dataSpace,
            now: now,
            in: context,
            isReady: isReady
        )
    }

    static func bindResponseMessage(
        job: AgentJob,
        turnID: UUID,
        resumable: Bool,
        context: ConversationProcessingContext
    ) -> (CoachMessage, Int) {
        if resumable,
           let existingID = job.responseMessageID,
           let existing = message(id: existingID, in: context.modelContext)
        {
            let attemptNumber = max(existing.attemptNumber, 1)
            job.activeAttemptNumber = attemptNumber
            prepareResponseMessageForResume(existing, job: job)
            _ = try? append(
                kind: .attemptStarted,
                payload: .init(message: "继续处理首个未完成 step。"),
                to: job,
                in: context.modelContext
            )
            return (existing, attemptNumber)
        }
        let attemptNumber = nextAttemptNumber(
            for: turnID,
            in: context.modelContext
        )
        job.activeAttemptNumber = attemptNumber
        let created = CoachMessage(
            sessionID: context.session.id,
            isFromCoach: true,
            text: "",
            agentStatus: .running,
            turnID: turnID,
            attemptNumber: attemptNumber
        )
        context.modelContext.insert(created)
        job.responseMessageID = created.id
        try? context.modelContext.save()
        _ = try? append(
            kind: .attemptStarted,
            payload: .init(message: "开始第 \(attemptNumber) 次处理。"),
            to: job,
            in: context.modelContext
        )
        return (created, attemptNumber)
    }

    /// ADR 0048：同气泡续跑时复用 CoachMessage，丢掉未完成 step 的 running 卡片。
    static func prepareResponseMessageForResume(
        _ message: CoachMessage,
        job: AgentJob
    ) {
        let completedItems = ConversationResumeProjection.completedItems(
            from: message.agentTurnItems
        )
        message.replaceAgentTurnItems(completedItems)
        let checkpointText = job.loopCheckpoint?.assistantPassages
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let checkpointText, !checkpointText.isEmpty {
            job.responseTextSnapshot = checkpointText
            message.text = checkpointText
        } else if !job.responseTextSnapshot.isEmpty, job.hasResumableCheckpoint {
            message.text = job.responseTextSnapshot
        } else {
            job.responseTextSnapshot = ""
            message.text = ""
        }
        message.agentStatus = .running
    }

    static func nextAttemptNumber(
        for turnID: UUID,
        in context: ModelContext
    ) -> Int {
        var descriptor = FetchDescriptor<CoachMessage>(
            predicate: #Predicate {
                $0.isFromCoach && $0.turnID == turnID
            },
            sortBy: [SortDescriptor(\.attemptNumber, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor).first?.attemptNumber) ?? 0) + 1
    }

    static func message(id: UUID, in context: ModelContext) -> CoachMessage? {
        var descriptor = FetchDescriptor<CoachMessage>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func recentMessages(
        sessionID: UUID,
        limit: Int = 80,
        in context: ModelContext
    ) -> [CoachMessage] {
        var descriptor = FetchDescriptor<CoachMessage>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
}
