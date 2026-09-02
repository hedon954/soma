import Foundation

struct ConversationSessionDTO: Codable, Equatable, Sendable {
    var id: UUID
    var startedAt: Date
    var updatedAt: Date
    var title: String
    var titleSourceRaw: String?

    init(_ model: ConversationSession) {
        id = model.id
        startedAt = model.startedAt
        updatedAt = model.updatedAt
        title = model.title
        titleSourceRaw = model.titleSourceRaw
    }

    func makeModel() -> ConversationSession {
        let model = ConversationSession(
            id: id,
            startedAt: startedAt,
            updatedAt: updatedAt,
            title: title
        )
        // Compatibility-only restoration. Product behavior never consults it.
        model.titleSourceRaw = titleSourceRaw
        return model
    }
}

struct CoachMessageDTO: Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var sessionID: UUID?
    var isFromCoach: Bool
    var text: String
    var mediaKindRaw: String
    var mediaAttachments: [MediaAttachmentReference]
    var recordTypeRaw: String?
    var agentTraceID: UUID?
    var agentStatusRaw: String?
    var agentEventsData: Data
    var agentTurnItemsData: Data
    var turnID: UUID?
    var attemptNumber: Int
    var locationData: Data
    var effectiveGymID: UUID?

    init(_ model: CoachMessage) {
        id = model.id
        date = model.date
        sessionID = model.sessionID
        isFromCoach = model.isFromCoach
        text = model.text
        mediaKindRaw = model.mediaKindRaw
        mediaAttachments = model.mediaAttachments
        recordTypeRaw = model.recordTypeRaw
        agentTraceID = model.agentTraceID
        agentStatusRaw = model.agentStatusRaw
        agentEventsData = model.agentEventsData
        agentTurnItemsData = model.agentTurnItemsData
        turnID = model.turnID
        attemptNumber = model.attemptNumber
        locationData = model.locationData
        effectiveGymID = model.effectiveGymID
    }

    func makeModel(mediaPathMapping: [String: String]) -> CoachMessage {
        let attachments = mediaAttachments.map {
            MediaAttachmentReference(
                kind: $0.kind,
                path: mediaPathMapping[$0.path] ?? $0.path
            )
        }
        let model = CoachMessage(
            date: date,
            sessionID: sessionID,
            isFromCoach: isFromCoach,
            text: text,
            mediaAttachments: attachments,
            turnID: turnID,
            attemptNumber: attemptNumber,
            effectiveGymID: effectiveGymID
        )
        model.id = id
        model.mediaKindRaw = mediaKindRaw
        model.recordTypeRaw = recordTypeRaw
        model.agentTraceID = agentTraceID
        model.agentStatusRaw = agentStatusRaw
        model.agentEventsData = agentEventsData
        model.agentTurnItemsData = agentTurnItemsData
        model.locationData = locationData
        return model
    }
}

struct AgentTraceDTO: Codable, Equatable, Sendable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var provider: String
    var model: String
    var endpoint: String
    var dataSpaceRaw: String
    var userInput: String
    var contextSnapshot: String
    var mediaKindRaw: String
    var imageCount: Int
    var imageAttachmentCount: Int
    var videoAttachmentCount: Int
    var finalAnswer: String?
    var errorMessage: String?
    var spansData: Data
    var turnID: UUID?
    var attemptNumber: Int

    init(_ model: AgentTrace) {
        id = model.id
        startedAt = model.startedAt
        endedAt = model.endedAt
        statusRaw = model.statusRaw
        provider = model.provider
        self.model = model.model
        endpoint = model.endpoint
        dataSpaceRaw = model.dataSpaceRaw
        userInput = model.userInput
        contextSnapshot = model.contextSnapshot
        mediaKindRaw = model.mediaKindRaw
        imageCount = model.imageCount
        imageAttachmentCount = model.imageAttachmentCount
        videoAttachmentCount = model.videoAttachmentCount
        finalAnswer = model.finalAnswer
        errorMessage = model.errorMessage
        spansData = model.spansData
        turnID = model.turnID
        attemptNumber = model.attemptNumber
    }

    func makeModel() -> AgentTrace {
        let trace = AgentTrace(
            id: id,
            startedAt: startedAt,
            provider: provider,
            model: model,
            endpoint: endpoint,
            dataSpaceRaw: dataSpaceRaw,
            userInput: userInput,
            contextSnapshot: contextSnapshot,
            mediaKind: MediaKind(rawValue: mediaKindRaw) ?? .none,
            imageCount: imageCount,
            imageAttachmentCount: imageAttachmentCount,
            videoAttachmentCount: videoAttachmentCount,
            turnID: turnID,
            attemptNumber: attemptNumber
        )
        trace.endedAt = endedAt
        trace.statusRaw = statusRaw
        trace.mediaKindRaw = mediaKindRaw
        trace.finalAnswer = finalAnswer
        trace.errorMessage = errorMessage
        trace.spansData = spansData
        return trace
    }
}

struct AgentMutationReceiptDTO: Codable, Equatable, Sendable {
    var key: String
    var turnID: UUID
    var signature: String
    var resultData: Data
    var createdAt: Date

    var hasDecodableResult: Bool {
        (try? JSONDecoder().decode(AgentToolResult.self, from: resultData)) != nil
    }

    init(_ model: AgentMutationReceipt) {
        key = model.key
        turnID = model.turnID
        signature = model.signature
        resultData = model.resultData
        createdAt = model.createdAt
    }

    func makeModel() throws -> AgentMutationReceipt {
        let result = try JSONDecoder().decode(AgentToolResult.self, from: resultData)
        let receipt = AgentMutationReceipt(
            turnID: turnID,
            signature: signature,
            result: result,
            createdAt: createdAt
        )
        receipt.key = key
        receipt.resultData = resultData
        return receipt
    }
}
