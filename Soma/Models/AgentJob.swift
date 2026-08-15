import Foundation
import SwiftData

enum AgentExecutionBackendKind: String, Codable, CaseIterable, Sendable {
    case local
    case remote
}

enum AgentJobExecutionKind: String, Codable, Sendable {
    case react
    case deterministicWorkout
}

enum AgentJobState: String, Codable, CaseIterable, Sendable {
    case queued
    case waitingForNetwork
    /// 已持久化但当前没有可用的 LLM 执行位置（缺凭据、鉴权失败、限流或供应商 5xx）。
    /// 见 ADR 0045。
    case staged
    /// 欠费或需要用户决定的失败。只能由显式重试释放。
    case waitingForUser
    case running
    case remoteRunning
    case waitingForForeground
    case waitingForDevice
    case succeeded
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled:
            true
        default:
            false
        }
    }

    var isRunnable: Bool {
        switch self {
        case .queued,
             .waitingForNetwork,
             .waitingForForeground,
             .remoteRunning,
             .waitingForDevice:
            true
        default:
            false
        }
    }

    func canTransition(to next: AgentJobState) -> Bool {
        guard self != next, !isTerminal else { return false }
        return switch (self, next) {
        case (.queued, .running),
             (.queued, .waitingForNetwork),
             (.queued, .staged),
             (.queued, .failed),
             (.queued, .cancelled),
             (.waitingForNetwork, .queued),
             (.waitingForNetwork, .running),
             (.waitingForNetwork, .staged),
             (.waitingForNetwork, .failed),
             (.waitingForNetwork, .cancelled),
             (.staged, .queued),
             (.staged, .running),
             (.staged, .waitingForNetwork),
             (.staged, .failed),
             (.staged, .cancelled),
             (.waitingForUser, .queued),
             (.waitingForUser, .failed),
             (.waitingForUser, .cancelled),
             (.running, .queued),
             (.running, .waitingForNetwork),
             (.running, .staged),
             (.running, .waitingForUser),
             (.running, .remoteRunning),
             (.running, .waitingForForeground),
             (.running, .waitingForDevice),
             (.running, .succeeded),
             (.running, .failed),
             (.running, .cancelled),
             (.waitingForForeground, .queued),
             (.waitingForForeground, .running),
             (.waitingForForeground, .staged),
             (.waitingForForeground, .waitingForUser),
             (.waitingForForeground, .failed),
             (.waitingForForeground, .cancelled),
             (.waitingForDevice, .queued),
             (.waitingForDevice, .running),
             (.waitingForDevice, .failed),
             (.waitingForDevice, .cancelled):
            true
        case (.remoteRunning, .running),
             (.remoteRunning, .staged),
             (.remoteRunning, .waitingForDevice),
             (.remoteRunning, .succeeded),
             (.remoteRunning, .failed),
             (.remoteRunning, .cancelled),
             (.waitingForDevice, .remoteRunning):
            true
        default:
            false
        }
    }
}

enum AgentJobStateError: LocalizedError, Equatable {
    case invalidTransition(from: AgentJobState, to: AgentJobState)

    var errorDescription: String? {
        switch self {
        case let .invalidTransition(from, to):
            "Agent Job 不能从 \(from.rawValue) 转换为 \(to.rawValue)"
        }
    }
}

struct AgentJobContextSnapshot: Codable, Equatable, Sendable {
    var structuredContext: String
    var includeLocation: Bool
    var createdAt: Date
    var envelope: AgentTurnContextEnvelope?

    init(
        structuredContext: String,
        includeLocation: Bool,
        createdAt: Date = .now,
        envelope: AgentTurnContextEnvelope? = nil
    ) {
        self.structuredContext = structuredContext
        self.includeLocation = includeLocation
        self.createdAt = createdAt
        self.envelope = envelope
    }
}

private enum AgentJobCoding {
    static func encode(_ value: some Encodable) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

@Model
final class AgentJob {
    @Attribute(.unique) var clientJobKey: String
    var id: UUID
    var turnID: UUID
    var sessionID: UUID
    var userMessageID: UUID
    var responseMessageID: UUID?
    var dataSpaceRaw: String
    var backendRaw: String
    var stateRaw: String
    var userText: String
    var mediaAttachmentsData: Data
    var contextSnapshotData: Data
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var activeAttemptNumber: Int
    var submissionAttemptCount: Int
    var nextRetryAt: Date?
    var lastError: String?
    var remoteJobID: String?
    var remoteEventCursor: Int = 0
    var remoteRequestAttempt: Int = 1
    var leaseOwner: String?
    var leaseExpiresAt: Date?
    var leaseEpoch: Int
    var lastEventSequence: Int
    var chatProjectionCursor: Int
    var traceProjectionCursor: Int
    var liveActivityProjectionCursor: Int
    var notificationProjectionCursor: Int
    var responseTextSnapshot: String
    /// ADR 0048：本地 ReAct 循环检查点（step 边界）。
    var lastCompletedStep: Int = 0
    var loopCheckpointData: Data = Data()
    /// 第一次领取时冻结，后续 step、恢复与手动重试都复用。
    var loopStartedAt: Date?
    /// 当前用户授权执行窗口内，ReAct Loop 已实际运行的秒数；等待用户、网络或前台不计入。
    var loopActiveDuration: TimeInterval = 0
    /// 当前运行区间的起点。离开 running 时累计进 loopActiveDuration 并清空。
    var loopActiveStartedAt: Date?
    /// 第一个模型 invoke 的首增量门禁只消费一次。
    var firstStepDeadlineConsumed: Bool = false
    var executionKindRaw: String = AgentJobExecutionKind.react.rawValue
    var deterministicPayloadData: Data = Data()
    /// 原始用户 Turn 的发送时间；排队与重试不得刷新。
    var turnSentAt: Date?
    /// 当前 Turn 最终解析出的业务日，只对该 Turn 生效。
    var effectiveBusinessDate: Date?
    var businessTimeZoneIdentifier: String?
    /// 省略 occurred_at 时复用的稳定记录发生时间。
    var defaultOccurredAt: Date?
    /// 用户在输入框中单选的 Skill；用于首轮直载和恢复，提交后不随设置变化。
    var selectedSkillID: String?

    init(
        id: UUID = UUID(),
        turnID: UUID,
        sessionID: UUID,
        userMessageID: UUID,
        dataSpace: DataSpace,
        backend: AgentExecutionBackendKind = .local,
        state: AgentJobState = .queued,
        userText: String,
        mediaAttachments: [MediaAttachmentReference],
        contextSnapshot: AgentJobContextSnapshot,
        turnSentAt: Date? = nil,
        effectiveBusinessDate: Date? = nil,
        businessTimeZone: TimeZone = .current,
        selectedSkillID: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        clientJobKey = id.uuidString.lowercased()
        self.turnID = turnID
        self.sessionID = sessionID
        self.userMessageID = userMessageID
        dataSpaceRaw = dataSpace.rawValue
        backendRaw = backend.rawValue
        stateRaw = state.rawValue
        self.userText = userText
        mediaAttachmentsData = AgentJobCoding.encode(mediaAttachments)
        contextSnapshotData = AgentJobCoding.encode(contextSnapshot)
        self.createdAt = createdAt
        let stableTurnSentAt = turnSentAt
            ?? contextSnapshot.envelope?.trustedTime.turnSentAt
            ?? createdAt
        self.turnSentAt = stableTurnSentAt
        let stableBusinessDate = effectiveBusinessDate ?? stableTurnSentAt
        self.effectiveBusinessDate = BusinessDateResolver.startOfDay(
            stableBusinessDate,
            in: businessTimeZone
        )
        businessTimeZoneIdentifier = businessTimeZone.identifier
        defaultOccurredAt = BusinessDateResolver.defaultOccurredAt(
            turnSentAt: stableTurnSentAt,
            businessDate: stableBusinessDate,
            timeZone: businessTimeZone
        )
        self.selectedSkillID = selectedSkillID
        updatedAt = createdAt
        activeAttemptNumber = 0
        submissionAttemptCount = 0
        leaseEpoch = 0
        lastEventSequence = 0
        chatProjectionCursor = 0
        traceProjectionCursor = 0
        liveActivityProjectionCursor = 0
        notificationProjectionCursor = 0
        responseTextSnapshot = ""
        remoteRequestAttempt = 1
    }

    var dataSpace: DataSpace {
        DataSpace(rawValue: dataSpaceRaw) ?? .personal
    }

    var backend: AgentExecutionBackendKind {
        get { AgentExecutionBackendKind(rawValue: backendRaw) ?? .local }
        set { backendRaw = newValue.rawValue }
    }

    var state: AgentJobState {
        get { AgentJobState(rawValue: stateRaw) ?? .failed }
        set { stateRaw = newValue.rawValue }
    }

    var executionKind: AgentJobExecutionKind {
        get { AgentJobExecutionKind(rawValue: executionKindRaw) ?? .react }
        set { executionKindRaw = newValue.rawValue }
    }

    var deterministicWorkoutDraft: ExerciseQuickRecordDraft? {
        get {
            AgentJobCoding.decode(
                ExerciseQuickRecordDraft.self,
                from: deterministicPayloadData
            )
        }
        set {
            deterministicPayloadData = newValue.map(AgentJobCoding.encode) ?? Data()
        }
    }

    var mediaAttachments: [MediaAttachmentReference] {
        get {
            AgentJobCoding.decode(
                [MediaAttachmentReference].self,
                from: mediaAttachmentsData
            ) ?? []
        }
        set {
            mediaAttachmentsData = AgentJobCoding.encode(newValue)
        }
    }

    var contextSnapshot: AgentJobContextSnapshot? {
        get {
            AgentJobCoding.decode(
                AgentJobContextSnapshot.self,
                from: contextSnapshotData
            )
        }
        set {
            contextSnapshotData = newValue.map(AgentJobCoding.encode) ?? Data()
        }
    }

    var loopCheckpoint: AgentLoopCheckpoint? {
        get {
            AgentJobCoding.decode(
                AgentLoopCheckpoint.self,
                from: loopCheckpointData
            )
        }
        set {
            loopCheckpointData = newValue.map(AgentJobCoding.encode) ?? Data()
            if let newValue {
                lastCompletedStep = newValue.lastCompletedStep
            }
        }
    }

    var hasResumableCheckpoint: Bool {
        lastCompletedStep > 0 && loopCheckpoint != nil
    }

    /// 同一 ReAct Loop 的所有业务写入复用第一次执行时间；显示时再按用户时区格式化。
    var frozenExecutionDate: Date {
        loopStartedAt ?? createdAt
    }

    /// 记录 Tool 的默认发生时间与 Loop 领取时间解耦。
    var stableDefaultOccurredAt: Date {
        defaultOccurredAt ?? turnSentAt ?? createdAt
    }

    func freezeLoopStartIfNeeded(at date: Date) {
        guard loopStartedAt == nil else { return }
        loopStartedAt = date
        guard var snapshot = contextSnapshot,
              let envelope = snapshot.envelope
        else {
            return
        }
        snapshot.envelope = envelope.freezingLoopStart(at: date)
        snapshot.structuredContext = snapshot.envelope?.promptText(at: date)
            ?? snapshot.structuredContext
        contextSnapshot = snapshot
    }

    func activeLoopDuration(at date: Date = .now) -> TimeInterval {
        let currentInterval = loopActiveStartedAt.map {
            max(0, date.timeIntervalSince($0))
        } ?? 0
        return max(0, loopActiveDuration + currentInterval)
    }

    func pauseLoopRuntime(at date: Date = .now) {
        guard let startedAt = loopActiveStartedAt else { return }
        loopActiveDuration += max(0, date.timeIntervalSince(startedAt))
        loopActiveStartedAt = nil
    }

    /// 用户显式重试为未完成 step 开启新的执行预算，但不改变业务时间和检查点。
    func resetLoopRuntimeBudget() {
        loopActiveDuration = 0
        loopActiveStartedAt = nil
    }

    func transition(
        to next: AgentJobState,
        at date: Date = .now,
        error: String? = nil
    ) throws {
        let current = state
        guard current.canTransition(to: next) else {
            throw AgentJobStateError.invalidTransition(from: current, to: next)
        }
        if current == .running, next != .running {
            pauseLoopRuntime(at: date)
        } else if current != .running, next == .running, loopActiveStartedAt == nil {
            loopActiveStartedAt = date
        }
        state = next
        updatedAt = date
        lastError = error
        if next.isTerminal {
            completedAt = date
            leaseOwner = nil
            leaseExpiresAt = nil
        }
    }
}

enum PersistentAgentEventKind: String, Codable, CaseIterable, Sendable {
    case jobQueued
    case jobClaimed
    case attemptStarted
    case assistantTextDelta
    case assistantTextCompleted
    case span
    case waitingForNetwork
    case staged
    case waitingForUser
    case waitingForForeground
    case waitingForDevice
    case completed
    case failed
    case cancelled
}

struct PersistentAgentEventPayload: Codable, Equatable, Sendable {
    var itemID: UUID?
    var text: String?
    var span: AgentTraceSpan?
    var message: String?
    var cancelled: Bool?

    init(
        itemID: UUID? = nil,
        text: String? = nil,
        span: AgentTraceSpan? = nil,
        message: String? = nil,
        cancelled: Bool? = nil
    ) {
        self.itemID = itemID
        self.text = text
        self.span = span
        self.message = message
        self.cancelled = cancelled
    }
}

@Model
final class PersistentAgentEvent {
    @Attribute(.unique) var eventKey: String
    var id: UUID
    var jobID: UUID
    var turnID: UUID
    var sequence: Int
    var attemptNumber: Int
    var kindRaw: String
    var payloadData: Data
    var createdAt: Date

    init(
        id: UUID = UUID(),
        jobID: UUID,
        turnID: UUID,
        sequence: Int,
        attemptNumber: Int,
        kind: PersistentAgentEventKind,
        payload: PersistentAgentEventPayload = .init(),
        createdAt: Date = .now
    ) {
        self.id = id
        self.jobID = jobID
        self.turnID = turnID
        self.sequence = sequence
        self.attemptNumber = attemptNumber
        kindRaw = kind.rawValue
        payloadData = AgentJobCoding.encode(payload)
        self.createdAt = createdAt
        eventKey = "\(jobID.uuidString.lowercased())|\(sequence)"
    }

    var kind: PersistentAgentEventKind {
        PersistentAgentEventKind(rawValue: kindRaw) ?? .failed
    }

    var payload: PersistentAgentEventPayload {
        AgentJobCoding.decode(
            PersistentAgentEventPayload.self,
            from: payloadData
        ) ?? .init()
    }
}

@MainActor
enum AgentJobStore {
    static func enqueue(
        _ job: AgentJob,
        userMessage: CoachMessage,
        in context: ModelContext,
        at date: Date = .now
    ) throws {
        job.lastEventSequence = 1
        job.updatedAt = date
        context.insert(userMessage)
        context.insert(job)
        context.insert(PersistentAgentEvent(
            jobID: job.id,
            turnID: job.turnID,
            sequence: 1,
            attemptNumber: 0,
            kind: .jobQueued,
            createdAt: date
        ))
        try context.save()
    }

    static func append(
        kind: PersistentAgentEventKind,
        payload: PersistentAgentEventPayload = .init(),
        to job: AgentJob,
        in context: ModelContext,
        at date: Date = .now
    ) throws -> PersistentAgentEvent {
        job.lastEventSequence += 1
        job.updatedAt = date
        let event = PersistentAgentEvent(
            jobID: job.id,
            turnID: job.turnID,
            sequence: job.lastEventSequence,
            attemptNumber: job.activeAttemptNumber,
            kind: kind,
            payload: payload,
            createdAt: date
        )
        context.insert(event)
        try context.save()
        return event
    }

    static func events(
        for jobID: UUID,
        after sequence: Int = 0,
        in context: ModelContext
    ) -> [PersistentAgentEvent] {
        var descriptor = FetchDescriptor<PersistentAgentEvent>(
            predicate: #Predicate { event in
                event.jobID == jobID && event.sequence > sequence
            },
            sortBy: [SortDescriptor(\.sequence)]
        )
        descriptor.fetchLimit = 5000
        return (try? context.fetch(descriptor)) ?? []
    }

    static func claimNext(
        dataSpace: DataSpace,
        owner: String,
        now: Date = .now,
        leaseDuration: TimeInterval = 25,
        in context: ModelContext
    ) throws -> AgentJob? {
        let jobs = (
            try? context.fetch(
                FetchDescriptor<AgentJob>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        guard let job = jobs.first(where: {
            $0.dataSpace == dataSpace && !$0.state.isTerminal
        }), job.state.isRunnable,
        job.nextRetryAt == nil || job.nextRetryAt! <= now
        else {
            return nil
        }
        try job.transition(to: .running, at: now)
        job.freezeLoopStartIfNeeded(at: now)
        job.leaseOwner = owner
        job.leaseExpiresAt = now.addingTimeInterval(leaseDuration)
        job.leaseEpoch += 1
        job.activeAttemptNumber += 1
        try context.save()
        _ = try append(
            kind: .jobClaimed,
            to: job,
            in: context,
            at: now
        )
        return job
    }

    static func claim(
        _ job: AgentJob,
        owner: String,
        now: Date = .now,
        leaseDuration: TimeInterval = 25,
        in context: ModelContext
    ) throws {
        guard job.state.isRunnable,
              job.nextRetryAt == nil || job.nextRetryAt! <= now
        else {
            throw AgentJobStateError.invalidTransition(
                from: job.state,
                to: .running
            )
        }
        try job.transition(to: .running, at: now)
        job.freezeLoopStartIfNeeded(at: now)
        job.leaseOwner = owner
        job.leaseExpiresAt = now.addingTimeInterval(leaseDuration)
        job.leaseEpoch += 1
        job.activeAttemptNumber += 1
        try context.save()
        _ = try append(
            kind: .jobClaimed,
            to: job,
            in: context,
            at: now
        )
    }

    static func recoverExpiredLeases(
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext
    ) throws -> [UUID] {
        let jobs = (try? context.fetch(FetchDescriptor<AgentJob>())) ?? []
        var recovered: [UUID] = []
        for job in jobs where job.dataSpace == dataSpace
            && job.state == .running
            && (job.leaseExpiresAt ?? .distantPast) <= now
        {
            // App 被系统结束后，离线等待不能被算作 ReAct 实际执行时间。
            job.pauseLoopRuntime(at: min(job.leaseExpiresAt ?? now, now))
            try job.transition(to: .waitingForForeground, at: now)
            job.leaseOwner = nil
            job.leaseExpiresAt = nil
            recovered.append(job.id)
            _ = try append(
                kind: .waitingForForeground,
                payload: .init(message: "上一次执行租约已过期，等待前台恢复。"),
                to: job,
                in: context,
                at: now
            )
        }
        return recovered
    }

    static func resumeForegroundJobs(
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext
    ) throws -> [UUID] {
        let jobs = (try? context.fetch(FetchDescriptor<AgentJob>())) ?? []
        let messages = (try? context.fetch(FetchDescriptor<CoachMessage>())) ?? []
        let messageByID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        var resumed: [UUID] = []
        var changed = false
        for job in jobs where job.dataSpace == dataSpace
            && job.state == .waitingForForeground
        {
            // 回复气泡已失败时不自动续跑，留给用户手动重试。
            if let responseID = job.responseMessageID,
               messageByID[responseID]?.agentStatus == .failed
            {
                if job.state.canTransition(to: .waitingForUser) {
                    try job.transition(
                        to: .waitingForUser,
                        at: now,
                        error: "上次处理已失败，等待手动重试。"
                    )
                    job.leaseOwner = nil
                    job.leaseExpiresAt = nil
                    changed = true
                }
                continue
            }
            try job.transition(to: .queued, at: now)
            resumed.append(job.id)
            changed = true
        }
        if changed {
            try context.save()
        }
        return resumed
    }

    /// ADR 0045：把 Job 暂存到 LLM 恢复为止。`retryDelay` 为 nil 表示只等配置变更信号，
    /// 不设退避计时。
    static func stage(
        _ job: AgentJob,
        message: String,
        retryDelay: TimeInterval?,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        if job.state != .staged {
            try job.transition(to: .staged, at: now, error: message)
        }
        job.leaseOwner = nil
        job.leaseExpiresAt = nil
        job.nextRetryAt = retryDelay.map { now.addingTimeInterval($0) }
        try context.save()
        _ = try append(
            kind: .staged,
            payload: .init(message: message),
            to: job,
            in: context,
            at: now
        )
    }

    static func waitForUser(
        _ job: AgentJob,
        message: String,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        if job.state != .waitingForUser {
            try job.transition(to: .waitingForUser, at: now, error: message)
        }
        job.leaseOwner = nil
        job.leaseExpiresAt = nil
        job.nextRetryAt = nil
        try context.save()
        _ = try append(
            kind: .waitingForUser,
            payload: .init(message: message),
            to: job,
            in: context,
            at: now
        )
    }

    static func stageFollowingJobs(
        after blockingJob: AgentJob,
        message: String,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        let jobs = (
            try? context.fetch(
                FetchDescriptor<AgentJob>(sortBy: [SortDescriptor(\.createdAt)])
            )
        ) ?? []
        for job in jobs where job.dataSpace == blockingJob.dataSpace
            && job.createdAt > blockingJob.createdAt
            && !job.state.isTerminal
            && job.state != .staged
            && job.state != .waitingForUser
        {
            guard job.state.canTransition(to: .staged) else { continue }
            try job.transition(to: .staged, at: now, error: message)
            job.leaseOwner = nil
            job.leaseExpiresAt = nil
            job.nextRetryAt = nil
            _ = try append(
                kind: .staged,
                payload: .init(message: message),
                to: job,
                in: context,
                at: now
            )
        }
        try context.save()
    }

    static func releaseForManualRetry(
        _ job: AgentJob,
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext
    ) throws {
        guard job.dataSpace == dataSpace,
              job.state == .waitingForUser || job.state == .staged
        else {
            throw AgentJobStateError.invalidTransition(from: job.state, to: .queued)
        }
        try job.transition(to: .queued, at: now)
        job.resetLoopRuntimeBudget()
        job.nextRetryAt = nil
        _ = try releaseStagedJobs(dataSpace: dataSpace, now: now, in: context)
        try context.save()
    }

    /// 用户从暂存管理显式选择“按顺序重试全部”时，一次性释放整个本地队列。
    /// 真正领取仍由 `claimNext` 严格按 `createdAt` 串行完成。
    @discardableResult
    static func releasePendingQueueForManualRetry(
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext
    ) throws -> [UUID] {
        let jobs = (
            try? context.fetch(
                FetchDescriptor<AgentJob>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        let pendingStates: Set<AgentJobState> = [
            .staged,
            .waitingForUser,
            .queued,
            .waitingForNetwork
        ]
        let targets = jobs.filter {
            $0.dataSpace == dataSpace && pendingStates.contains($0.state)
        }
        guard !targets.isEmpty else { return [] }
        for job in targets {
            if job.state != .queued {
                try job.transition(to: .queued, at: now)
            }
            job.resetLoopRuntimeBudget()
            job.nextRetryAt = nil
        }
        try context.save()
        return targets.map(\.id)
    }

    /// LLM 恢复后解除暂存，让既有 FIFO 领取逻辑立即消费。
    static func releaseStagedJobs(
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext,
        isReady: (AgentJob) -> Bool = { _ in true }
    ) throws -> [UUID] {
        let jobs = (try? context.fetch(FetchDescriptor<AgentJob>())) ?? []
        var released: [UUID] = []
        for job in jobs where job.dataSpace == dataSpace
            && job.state == .staged
            && isReady(job)
        {
            try job.transition(to: .queued, at: now)
            job.nextRetryAt = nil
            released.append(job.id)
        }
        if !released.isEmpty {
            try context.save()
        }
        return released
    }

    static func stagedJobCount(
        dataSpace: DataSpace,
        in context: ModelContext
    ) -> Int {
        let jobs = (try? context.fetch(FetchDescriptor<AgentJob>())) ?? []
        return jobs.filter {
            $0.dataSpace == dataSpace
                && ($0.state == .staged || $0.state == .waitingForUser)
        }.count
    }
}

@MainActor
enum PersistentAgentEventProjection {
    static func persistAndProject(
        _ event: AgentTraceEvent,
        job: AgentJob,
        responseMessage: CoachMessage,
        trace: AgentTrace,
        in context: ModelContext
    ) {
        trace.apply(event)

        switch event {
        case let .assistantTextDelta(_, delta):
            job.responseTextSnapshot += delta
            responseMessage.text += delta
            responseMessage.applyAgentEvent(event)
            return
        case let .assistantTextCompleted(itemID, date):
            persist(
                kind: .assistantTextCompleted,
                payload: .init(
                    itemID: itemID,
                    text: job.responseTextSnapshot
                ),
                job: job,
                context: context,
                at: date
            )
        case let .span(span):
            persist(
                kind: .span,
                payload: .init(span: span),
                job: job,
                context: context,
                at: span.endedAt
            )
        case let .completed(answer, date):
            persist(
                kind: .completed,
                payload: .init(text: answer),
                job: job,
                context: context,
                at: date
            )
        case let .failed(message, cancelled, date):
            persist(
                kind: cancelled ? .cancelled : .failed,
                payload: .init(
                    message: message,
                    cancelled: cancelled
                ),
                job: job,
                context: context,
                at: date
            )
        }

        projectChat(event, onto: responseMessage, job: job)
        try? context.save()
    }

    static func replayChat(
        events: [PersistentAgentEvent],
        onto message: CoachMessage
    ) {
        message.replaceAgentEvents([])
        message.replaceAgentTurnItems([])
        message.text = ""
        for event in events {
            projectChat(event, onto: message)
        }
    }

    private static func persist(
        kind: PersistentAgentEventKind,
        payload: PersistentAgentEventPayload,
        job: AgentJob,
        context: ModelContext,
        at date: Date
    ) {
        _ = try? AgentJobStore.append(
            kind: kind,
            payload: payload,
            to: job,
            in: context,
            at: date
        )
    }

    private static func projectChat(
        _ event: AgentTraceEvent,
        onto message: CoachMessage,
        job: AgentJob
    ) {
        message.applyAgentEvent(event)
        switch event {
        case .assistantTextDelta:
            break
        case .assistantTextCompleted, .span:
            break
        case let .completed(answer, _):
            message.text = answer
            message.agentStatus = .succeeded
        case let .failed(_, cancelled, _):
            message.agentStatus = cancelled ? .cancelled : .failed
        }
        if message.text.isEmpty, !job.responseTextSnapshot.isEmpty {
            message.text = job.responseTextSnapshot
        }
    }

    private static func projectChat(
        _ event: PersistentAgentEvent,
        onto message: CoachMessage
    ) {
        let payload = event.payload
        switch event.kind {
        case .assistantTextDelta:
            let itemID = payload.itemID ?? UUID()
            if let text = payload.text, !text.isEmpty {
                message.applyAgentEvent(.assistantTextDelta(
                    itemID: itemID,
                    delta: text
                ))
                message.text += text
            }
        case .assistantTextCompleted:
            let itemID = payload.itemID ?? UUID()
            if let text = payload.text, !text.isEmpty {
                message.applyAgentEvent(.assistantTextDelta(
                    itemID: itemID,
                    delta: text
                ))
                message.text = text
            }
            message.applyAgentEvent(.assistantTextCompleted(
                itemID: itemID,
                at: event.createdAt
            ))
        case .span:
            if let span = payload.span {
                message.applyAgentEvent(.span(span))
            }
        case .completed:
            let text = payload.text ?? message.text
            message.text = text
            message.applyAgentEvent(.completed(
                answer: text,
                at: event.createdAt
            ))
            message.agentStatus = .succeeded
        case .failed, .cancelled:
            let cancelled = event.kind == .cancelled
            message.applyAgentEvent(.failed(
                message: payload.message ?? "执行中断",
                cancelled: cancelled,
                at: event.createdAt
            ))
            message.agentStatus = cancelled ? .cancelled : .failed
        case .attemptStarted:
            let completedItems = message.agentTurnItems.filter {
                $0.status == .succeeded && $0.kind != .error
            }
            message.replaceAgentTurnItems(completedItems)
            message.replaceAgentEvents(
                message.agentEvents.filter { $0.status == .succeeded }
            )
            message.text = completedItems
                .filter { $0.kind == .text }
                .map(\.text)
                .joined(separator: "\n\n")
            message.agentStatus = .running
        case .jobQueued,
             .jobClaimed,
             .waitingForNetwork,
             .staged,
             .waitingForUser,
             .waitingForForeground,
             .waitingForDevice:
            break
        }
    }
}
