import Foundation
import SwiftData

enum AgentExecutionBackendKind: String, Codable, CaseIterable, Sendable {
    case local
    case remote
}

enum AgentJobState: String, Codable, CaseIterable, Sendable {
    case queued
    case waitingForNetwork
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
             (.queued, .failed),
             (.queued, .cancelled),
             (.waitingForNetwork, .queued),
             (.waitingForNetwork, .running),
             (.waitingForNetwork, .failed),
             (.waitingForNetwork, .cancelled),
             (.running, .queued),
             (.running, .waitingForNetwork),
             (.running, .remoteRunning),
             (.running, .waitingForForeground),
             (.running, .waitingForDevice),
             (.running, .succeeded),
             (.running, .failed),
             (.running, .cancelled),
             (.waitingForForeground, .queued),
             (.waitingForForeground, .running),
             (.waitingForForeground, .cancelled),
             (.waitingForDevice, .queued),
             (.waitingForDevice, .running),
             (.waitingForDevice, .failed),
             (.waitingForDevice, .cancelled):
            true
        case (.remoteRunning, .running),
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

    init(
        structuredContext: String,
        includeLocation: Bool,
        createdAt: Date = .now
    ) {
        self.structuredContext = structuredContext
        self.includeLocation = includeLocation
        self.createdAt = createdAt
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
    var leaseOwner: String?
    var leaseExpiresAt: Date?
    var leaseEpoch: Int
    var lastEventSequence: Int
    var chatProjectionCursor: Int
    var traceProjectionCursor: Int
    var liveActivityProjectionCursor: Int
    var notificationProjectionCursor: Int
    var responseTextSnapshot: String

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

    func transition(
        to next: AgentJobState,
        at date: Date = .now,
        error: String? = nil
    ) throws {
        let current = state
        guard current.canTransition(to: next) else {
            throw AgentJobStateError.invalidTransition(from: current, to: next)
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
        let all = (
            try? context.fetch(
                FetchDescriptor<PersistentAgentEvent>(
                    sortBy: [SortDescriptor(\.sequence)]
                )
            )
        ) ?? []
        return all.filter { $0.jobID == jobID && $0.sequence > sequence }
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
            $0.dataSpace == dataSpace
                && $0.state.isRunnable
                && ($0.nextRetryAt == nil || $0.nextRetryAt! <= now)
        }) else {
            return nil
        }
        try job.transition(to: .running, at: now)
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
        var resumed: [UUID] = []
        for job in jobs where job.dataSpace == dataSpace
            && job.state == .waitingForForeground
        {
            try job.transition(to: .queued, at: now)
            resumed.append(job.id)
        }
        if !resumed.isEmpty {
            try context.save()
        }
        return resumed
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
        case .jobQueued,
             .jobClaimed,
             .attemptStarted,
             .waitingForNetwork,
             .waitingForForeground,
             .waitingForDevice:
            break
        }
    }
}
