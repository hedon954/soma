import Foundation

enum AgentTurnItemKind: String, Codable, Hashable, Sendable {
    case activity
    case text
    case reasoning
    case skill
    case tool
    case error
}

enum AgentTurnPhase: String, Codable, CaseIterable, Sendable {
    case queued
    case modelRunning
    case preparing
    case running
    case waitingForDevice
    case completed
    case failed
    case cancelled
}

struct AgentTurnItem: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var sequence: Int
    var kindRaw: String
    var statusRaw: String
    var operationID: String?
    var phaseRaw: String?
    var title: String
    var text: String
    var startedAt: Date
    var endedAt: Date?
    var input: String?
    var output: String?
    var metadata: String?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        sequence: Int = 0,
        kind: AgentTurnItemKind,
        status: AgentTraceStatus,
        operationID: String? = nil,
        phase: AgentTurnPhase? = nil,
        title: String = "",
        text: String = "",
        startedAt: Date = .now,
        endedAt: Date? = nil,
        input: String? = nil,
        output: String? = nil,
        metadata: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.sequence = sequence
        kindRaw = kind.rawValue
        statusRaw = status.rawValue
        self.operationID = operationID
        phaseRaw = phase?.rawValue
        self.title = title
        self.text = text
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.input = input
        self.output = output
        self.metadata = metadata
        self.errorMessage = errorMessage
    }

    init(span: AgentTraceSpan, sequence: Int) {
        self.init(
            id: span.id,
            sequence: sequence,
            kind: span.kind == .skill ? .skill : .tool,
            status: span.status,
            operationID: span.operationID,
            phase: span.phase,
            title: span.title,
            startedAt: span.startedAt,
            endedAt: span.status == .running ? nil : span.endedAt,
            input: span.input,
            output: span.output,
            metadata: span.metadata,
            errorMessage: span.errorMessage
        )
    }

    var kind: AgentTurnItemKind {
        AgentTurnItemKind(rawValue: kindRaw) ?? .error
    }

    var status: AgentTraceStatus {
        AgentTraceStatus(rawValue: statusRaw) ?? .failed
    }

    var phase: AgentTurnPhase {
        if let phaseRaw, let phase = AgentTurnPhase(rawValue: phaseRaw) {
            return phase
        }
        return switch status {
        case .running: .running
        case .succeeded: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }

    mutating func appendTextDelta(_ delta: String) {
        text += delta
        statusRaw = AgentTraceStatus.running.rawValue
    }

    mutating func finishText(at date: Date) {
        statusRaw = AgentTraceStatus.succeeded.rawValue
        endedAt = date
    }

    mutating func fail(message: String, at date: Date) {
        statusRaw = AgentTraceStatus.failed.rawValue
        endedAt = date
        errorMessage = message
    }
}
