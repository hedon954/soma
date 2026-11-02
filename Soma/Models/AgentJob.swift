import Foundation
import SwiftData

enum AgentExecutionBackendKind: String, Codable, CaseIterable, Sendable {
    case local
    case remote
}

enum AgentJobExecutionKind: String, Codable, Sendable {
    case react
    case deterministicWorkout
    case deterministicQuestion
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
             .waitingForForeground,
             .remoteRunning,
             .waitingForDevice:
            true
        default:
            false
        }
    }

    /// 只有尚未向用户报告失败的运行态可由系统续跑。
    var awaitsAutomaticRecovery: Bool {
        switch self {
        case .queued,
             .staged,
             .running,
             .remoteRunning,
             .waitingForForeground,
             .waitingForDevice:
            true
        case .waitingForNetwork, .waitingForUser, .succeeded, .failed, .cancelled:
            false
        }
    }

    func canTransition(to next: AgentJobState) -> Bool {
        guard self != next, !isTerminal else { return false }
        return switch (self, next) {
        case (.queued, .running),
             (.queued, .waitingForNetwork),
             (.queued, .staged),
             (.queued, .waitingForUser),
             (.queued, .failed),
             (.queued, .cancelled),
             (.waitingForNetwork, .queued),
             (.waitingForNetwork, .running),
             (.waitingForNetwork, .staged),
             (.waitingForNetwork, .waitingForUser),
             (.waitingForNetwork, .failed),
             (.waitingForNetwork, .cancelled),
             (.staged, .queued),
             (.staged, .running),
             (.staged, .waitingForNetwork),
             (.staged, .waitingForUser),
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
             (.remoteRunning, .waitingForUser),
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
    var canonicalTurn: AgentCanonicalTurn? = nil
    /// 远程 Job 在等待设备 Tool 时不保证仍在进程内；将已经确认的原生帧放在
    /// 现有上下文 JSON，终态才封装为可跨 Turn 复用的 canonicalTurn。
    var remoteCanonicalFrames: [AgentModelMessage]? = nil
    var configuration: AgentPromptConfiguration? = nil
    var executionContext: String? = nil
    var executionObservedAt: Date? = nil

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
    /// PRD 033：用户单选的快捷按钮；决定本 Turn 曝光哪些 Tool，排队与恢复都沿用。
    var selectedShortcutID: String?

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
        selectedShortcutID: String? = nil,
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
        self.selectedShortcutID = selectedShortcutID
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
    case reasoningCompleted
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
        let responseMessage = CoachMessage(
            date: date.addingTimeInterval(0.001),
            sessionID: job.sessionID,
            isFromCoach: true,
            text: "",
            agentStatus: .running,
            agentTurnItems: [AgentTurnItem(
                sequence: 1,
                kind: .activity,
                status: .running,
                phase: .queued,
                title: "已收到，正在准备处理…",
                text: "已收到，正在准备处理…",
                startedAt: date
            )],
            turnID: job.turnID,
            attemptNumber: 1
        )
        job.responseMessageID = responseMessage.id
        job.lastEventSequence = 1
        job.updatedAt = date
        context.insert(userMessage)
        context.insert(responseMessage)
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

    static func updateQueuedResponse(
        for job: AgentJob,
        message: String,
        status: AgentTraceStatus = .running,
        in context: ModelContext
    ) {
        guard let responseID = job.responseMessageID else { return }
        var descriptor = FetchDescriptor<CoachMessage>(
            predicate: #Predicate { $0.id == responseID }
        )
        descriptor.fetchLimit = 1
        guard let response = try? context.fetch(descriptor).first else { return }
        response.text = ""
        response.agentStatus = status
        response.setAgentActivity(phase: .queued, message: message)
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
        let dataSpaceRaw = dataSpace.rawValue
        let completed = AgentJobState.succeeded.rawValue
        let failed = AgentJobState.failed.rawValue
        let cancelled = AgentJobState.cancelled.rawValue
        var descriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate {
                $0.dataSpaceRaw == dataSpaceRaw
                    && $0.stateRaw != completed
                    && $0.stateRaw != failed
                    && $0.stateRaw != cancelled
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1
        let jobs = (try? context.fetch(descriptor)) ?? []
        guard let job = jobs.first, job.state.isRunnable,
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
        let dataSpaceRaw = dataSpace.rawValue
        let runningRaw = AgentJobState.running.rawValue
        var descriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate {
                $0.dataSpaceRaw == dataSpaceRaw && $0.stateRaw == runningRaw
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1
        let jobs = (try? context.fetch(descriptor)) ?? []
        var recovered: [UUID] = []
        for job in jobs where (job.leaseExpiresAt ?? .distantPast) <= now {
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
        let dataSpaceRaw = dataSpace.rawValue
        let waitingRaw = AgentJobState.waitingForForeground.rawValue
        var descriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate {
                $0.dataSpaceRaw == dataSpaceRaw && $0.stateRaw == waitingRaw
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1
        let jobs = (try? context.fetch(descriptor)) ?? []
        var resumed: [UUID] = []
        var changed = false
        for job in jobs {
            // 回复气泡已失败时不自动续跑，留给用户手动重试。
            var response: CoachMessage?
            if let responseID = job.responseMessageID {
                var descriptor = FetchDescriptor<CoachMessage>(
                    predicate: #Predicate { $0.id == responseID }
                )
                descriptor.fetchLimit = 1
                response = try? context.fetch(descriptor).first
            }
            if response?.agentStatus == .failed {
                if job.state.canTransition(to: .waitingForUser) {
                    try job.transition(
                        to: .waitingForUser,
                        at: now,
                        error: "上次处理已失败，等待手动重试。"
                    )
                    job.leaseOwner = nil
                    job.leaseExpiresAt = nil
                    job.nextRetryAt = nil
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

    /// 教练气泡一旦进入失败态并展示重试，Job 就不能再被自动领取或补偿。
    @discardableResult
    static func promoteFailedResponsesToManualRetry(
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext
    ) throws -> [UUID] {
        let dataSpaceRaw = dataSpace.rawValue
        let succeeded = AgentJobState.succeeded.rawValue
        let failed = AgentJobState.failed.rawValue
        let cancelled = AgentJobState.cancelled.rawValue
        var descriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate {
                $0.dataSpaceRaw == dataSpaceRaw
                    && $0.stateRaw != succeeded
                    && $0.stateRaw != failed
                    && $0.stateRaw != cancelled
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        // FIFO 只允许队首运行；后续失败 Job 等到成为队首时再提升即可。
        descriptor.fetchLimit = 1
        let jobs = (try? context.fetch(descriptor)) ?? []
        var promoted: [UUID] = []
        for job in jobs {
            guard let responseID = job.responseMessageID else { continue }
            var descriptor = FetchDescriptor<CoachMessage>(
                predicate: #Predicate { $0.id == responseID }
            )
            descriptor.fetchLimit = 1
            guard (try? context.fetch(descriptor).first?.agentStatus) == .failed, job.state.canTransition(to: .waitingForUser) else { continue }
            try waitForUser(
                job,
                message: "上次处理已失败，等待手动重试。",
                now: now,
                in: context
            )
            promoted.append(job.id)
        }
        return promoted
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
        updateQueuedResponse(for: job, message: message, in: context)
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
        if let responseID = job.responseMessageID {
            var descriptor = FetchDescriptor<CoachMessage>(
                predicate: #Predicate { $0.id == responseID }
            )
            descriptor.fetchLimit = 1
            if let response = try? context.fetch(descriptor).first,
               response.agentStatus != .failed,
               response.agentStatus != .cancelled
            {
                response.text = ""
                response.agentStatus = .failed
                response.applyAgentEvent(.failed(
                    message: message,
                    cancelled: false,
                    at: now
                ))
            }
        }
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
        let dataSpaceRaw = blockingJob.dataSpaceRaw
        let createdAt = blockingJob.createdAt
        let succeeded = AgentJobState.succeeded.rawValue
        let failed = AgentJobState.failed.rawValue
        let cancelled = AgentJobState.cancelled.rawValue
        let jobs = (
            try? context.fetch(
                FetchDescriptor<AgentJob>(
                    predicate: #Predicate {
                        $0.dataSpaceRaw == dataSpaceRaw
                            && $0.createdAt > createdAt
                            && $0.stateRaw != succeeded
                            && $0.stateRaw != failed
                            && $0.stateRaw != cancelled
                    },
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        for job in jobs where job.state != .staged
            && job.state != .waitingForUser
        {
            guard job.state.canTransition(to: .staged) else { continue }
            try job.transition(to: .staged, at: now, error: message)
            job.leaseOwner = nil
            job.leaseExpiresAt = nil
            job.nextRetryAt = nil
            updateQueuedResponse(for: job, message: message, in: context)
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
              job.state == .waitingForUser
              || job.state == .staged
              || job.state == .waitingForNetwork
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
        let dataSpaceRaw = dataSpace.rawValue
        let jobs = (
            try? context.fetch(
                FetchDescriptor<AgentJob>(
                    predicate: #Predicate {
                        $0.dataSpaceRaw == dataSpaceRaw
                            && ($0.stateRaw == "staged"
                                || $0.stateRaw == "waitingForUser"
                                || $0.stateRaw == "queued"
                                || $0.stateRaw == "waitingForNetwork")
                    },
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        guard !jobs.isEmpty else { return [] }
        for job in jobs {
            if job.state != .queued {
                try job.transition(to: .queued, at: now)
            }
            job.resetLoopRuntimeBudget()
            job.nextRetryAt = nil
        }
        try context.save()
        return jobs.map(\.id)
    }

    /// LLM 恢复后解除暂存，让既有 FIFO 领取逻辑立即消费。
    static func releaseStagedJobs(
        dataSpace: DataSpace,
        now: Date = .now,
        in context: ModelContext,
        isReady: (AgentJob) -> Bool = { _ in true }
    ) throws -> [UUID] {
        let dataSpaceRaw = dataSpace.rawValue
        let staged = AgentJobState.staged.rawValue
        let jobs = (try? context.fetch(FetchDescriptor<AgentJob>(
            predicate: #Predicate {
                $0.dataSpaceRaw == dataSpaceRaw && $0.stateRaw == staged
            }
        ))) ?? []
        var released: [UUID] = []
        for job in jobs where isReady(job) {
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
        let dataSpaceRaw = dataSpace.rawValue
        let descriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate {
                $0.dataSpaceRaw == dataSpaceRaw
                    && ($0.stateRaw == "staged"
                        || $0.stateRaw == "waitingForUser")
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}

@MainActor
enum PersistentAgentEventProjection {
    static func persistAndProject(
        _ event: AgentTraceEvent,
        job: AgentJob,
        responseMessage: CoachMessage,
        trace: AgentTrace,
        liveText: LiveAgentTextSnapshot? = nil,
        in context: ModelContext
    ) {
        #if DEBUG
            // BUG 0024：这里改的是 SwiftData `@Model`。一旦流式回调重新脱离主 actor，
            // 就在开发构建里立刻炸出来，而不是等线上随机闪退。
            MainActor.assertIsolated("Agent 事件投影必须在主 actor 执行")
        #endif
        trace.apply(event)

        switch event {
        case .assistantTextDelta, .assistantTextDiscarded:
            // 高频增量由 ConversationProcessingService 的瞬态缓冲驱动 UI。
            // 这里不再反复修改三份增长中的字符串、解码/编码完整
            // agentTurnItems JSON，或使 SwiftData 观察者整页失效。
            return
        case .reasoningDelta:
            // 高频增量由 ConversationProcessingService 的瞬态缓冲驱动 UI。
            // 这里不再反复修改三份增长中的字符串、解码/编码完整
            // agentTurnItems JSON，或使 SwiftData 观察者整页失效。
            return
        case let .assistantTextCompleted(itemID, date):
            commitLiveText(
                liveText,
                expectedItemID: itemID,
                job: job,
                responseMessage: responseMessage
            )
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
        case let .reasoningCompleted(itemID, text, date):
            persist(
                kind: .reasoningCompleted,
                payload: .init(itemID: itemID, text: text),
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
            commitLiveText(
                liveText,
                expectedItemID: nil,
                job: job,
                responseMessage: responseMessage
            )
            persist(
                kind: .completed,
                payload: .init(text: answer),
                job: job,
                context: context,
                at: date
            )
        case let .failed(message, cancelled, date):
            commitLiveText(
                liveText,
                expectedItemID: nil,
                job: job,
                responseMessage: responseMessage
            )
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

    private static func commitLiveText(
        _ liveText: LiveAgentTextSnapshot?,
        expectedItemID: UUID?,
        job: AgentJob,
        responseMessage: CoachMessage
    ) {
        guard let liveText,
              expectedItemID == nil || expectedItemID == liveText.itemID,
              !liveText.text.isEmpty
        else {
            return
        }
        job.responseTextSnapshot += liveText.text
        responseMessage.text += liveText.text
        responseMessage.applyAgentEvent(.assistantTextDelta(
            itemID: liveText.itemID,
            delta: liveText.text
        ))
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
        case .assistantTextDelta, .assistantTextDiscarded, .reasoningDelta:
            break
        case .assistantTextCompleted, .reasoningCompleted, .span:
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
        case .reasoningCompleted:
            if let text = payload.text, !text.isEmpty {
                message.applyAgentEvent(.reasoningCompleted(
                    itemID: payload.itemID ?? UUID(),
                    text: text,
                    at: event.createdAt
                ))
            }
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
                $0.status == .succeeded
                    && $0.kind != .error
                    && $0.kind != .activity
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
            message.setAgentActivity(
                phase: .queued,
                message: "已收到，正在准备处理…",
                at: event.createdAt
            )
        case .jobQueued, .jobClaimed:
            message.setAgentActivity(
                phase: .queued,
                message: payload.message ?? "已收到，正在准备处理…",
                at: event.createdAt
            )
            message.agentStatus = .running
        case .waitingForNetwork, .staged, .waitingForForeground:
            message.setAgentActivity(
                phase: .queued,
                message: payload.message ?? "正在等待可用条件…",
                at: event.createdAt
            )
            message.agentStatus = .running
        case .waitingForDevice:
            message.setAgentActivity(
                phase: .waitingForDevice,
                message: payload.message ?? "等待在本机执行…",
                at: event.createdAt
            )
            message.agentStatus = .running
        case .waitingForUser:
            message.applyAgentEvent(.failed(
                message: payload.message ?? "这一步需要你手动重试。",
                cancelled: false,
                at: event.createdAt
            ))
            message.agentStatus = .failed
        }
    }
}
