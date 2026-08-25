import Foundation

struct AgentJobDTO: Codable, Equatable, Sendable {
    var clientJobKey: String
    var id: UUID
    var turnID: UUID
    var sessionID: UUID
    var userMessageID: UUID
    var responseMessageID: UUID?
    var dataSpaceRaw: String
    var backendRaw: String
    var stateRaw: String
    var userText: String
    var mediaAttachments: [MediaAttachmentReference]
    var contextSnapshotData: Data
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var activeAttemptNumber: Int
    var submissionAttemptCount: Int
    var nextRetryAt: Date?
    var lastError: String?
    var remoteJobID: String?
    var remoteEventCursor: Int?
    var remoteRequestAttempt: Int?
    var leaseOwner: String?
    var leaseExpiresAt: Date?
    var leaseEpoch: Int
    var lastEventSequence: Int
    var chatProjectionCursor: Int
    var traceProjectionCursor: Int
    var liveActivityProjectionCursor: Int
    var notificationProjectionCursor: Int
    var responseTextSnapshot: String
    var loopActiveDuration: TimeInterval?
    var loopActiveStartedAt: Date?

    init(_ model: AgentJob) {
        clientJobKey = model.clientJobKey
        id = model.id
        turnID = model.turnID
        sessionID = model.sessionID
        userMessageID = model.userMessageID
        responseMessageID = model.responseMessageID
        dataSpaceRaw = model.dataSpaceRaw
        backendRaw = model.backendRaw
        stateRaw = model.stateRaw
        userText = model.userText
        mediaAttachments = model.mediaAttachments
        contextSnapshotData = model.contextSnapshotData
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        completedAt = model.completedAt
        activeAttemptNumber = model.activeAttemptNumber
        submissionAttemptCount = model.submissionAttemptCount
        nextRetryAt = model.nextRetryAt
        lastError = model.lastError
        remoteJobID = model.remoteJobID
        remoteEventCursor = model.remoteEventCursor
        remoteRequestAttempt = model.remoteRequestAttempt
        leaseOwner = model.leaseOwner
        leaseExpiresAt = model.leaseExpiresAt
        leaseEpoch = model.leaseEpoch
        lastEventSequence = model.lastEventSequence
        chatProjectionCursor = model.chatProjectionCursor
        traceProjectionCursor = model.traceProjectionCursor
        liveActivityProjectionCursor = model.liveActivityProjectionCursor
        notificationProjectionCursor = model.notificationProjectionCursor
        responseTextSnapshot = model.responseTextSnapshot
        loopActiveDuration = model.activeLoopDuration(at: .now)
        // 备份不是继续运行信号；恢复时从暂停状态重新 claim。
        loopActiveStartedAt = nil
    }

    func makeModel(mediaPathMapping: [String: String]) -> AgentJob {
        let remappedAttachments = mediaAttachments.map {
            MediaAttachmentReference(
                kind: $0.kind,
                path: mediaPathMapping[$0.path] ?? $0.path
            )
        }
        let snapshot = (
            try? JSONDecoder().decode(
                AgentJobContextSnapshot.self,
                from: contextSnapshotData
            )
        ) ?? AgentJobContextSnapshot(
            structuredContext: "",
            includeLocation: false,
            createdAt: createdAt
        )
        let job = AgentJob(
            id: id,
            turnID: turnID,
            sessionID: sessionID,
            userMessageID: userMessageID,
            dataSpace: DataSpace(rawValue: dataSpaceRaw) ?? .personal,
            backend: AgentExecutionBackendKind(rawValue: backendRaw) ?? .local,
            state: AgentJobState(rawValue: stateRaw) ?? .failed,
            userText: userText,
            mediaAttachments: remappedAttachments,
            contextSnapshot: snapshot,
            createdAt: createdAt
        )
        job.clientJobKey = clientJobKey
        job.responseMessageID = responseMessageID
        job.dataSpaceRaw = dataSpaceRaw
        job.backendRaw = backendRaw
        job.stateRaw = stateRaw
        job.contextSnapshotData = contextSnapshotData
        job.updatedAt = updatedAt
        job.completedAt = completedAt
        job.activeAttemptNumber = activeAttemptNumber
        job.submissionAttemptCount = submissionAttemptCount
        job.nextRetryAt = nextRetryAt
        job.lastError = lastError
        job.remoteJobID = remoteJobID
        job.remoteEventCursor = remoteEventCursor ?? 0
        job.remoteRequestAttempt = remoteRequestAttempt ?? 1
        job.leaseOwner = leaseOwner
        job.leaseExpiresAt = leaseExpiresAt
        job.leaseEpoch = leaseEpoch
        job.lastEventSequence = lastEventSequence
        job.chatProjectionCursor = chatProjectionCursor
        job.traceProjectionCursor = traceProjectionCursor
        job.liveActivityProjectionCursor = liveActivityProjectionCursor
        job.notificationProjectionCursor = notificationProjectionCursor
        job.responseTextSnapshot = responseTextSnapshot
        job.loopActiveDuration = loopActiveDuration ?? 0
        job.loopActiveStartedAt = loopActiveStartedAt
        return job
    }
}

struct PersistentAgentEventDTO: Codable, Equatable, Sendable {
    var eventKey: String
    var id: UUID
    var jobID: UUID
    var turnID: UUID
    var sequence: Int
    var attemptNumber: Int
    var kindRaw: String
    var payloadData: Data
    var createdAt: Date

    init(_ model: PersistentAgentEvent) {
        eventKey = model.eventKey
        id = model.id
        jobID = model.jobID
        turnID = model.turnID
        sequence = model.sequence
        attemptNumber = model.attemptNumber
        kindRaw = model.kindRaw
        payloadData = model.payloadData
        createdAt = model.createdAt
    }

    func makeModel() -> PersistentAgentEvent {
        let payload = (
            try? JSONDecoder().decode(
                PersistentAgentEventPayload.self,
                from: payloadData
            )
        ) ?? .init()
        let event = PersistentAgentEvent(
            id: id,
            jobID: jobID,
            turnID: turnID,
            sequence: sequence,
            attemptNumber: attemptNumber,
            kind: PersistentAgentEventKind(rawValue: kindRaw) ?? .failed,
            payload: payload,
            createdAt: createdAt
        )
        event.eventKey = eventKey
        event.kindRaw = kindRaw
        event.payloadData = payloadData
        return event
    }
}
