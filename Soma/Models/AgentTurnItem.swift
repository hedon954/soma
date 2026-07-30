import Foundation

enum AgentTurnItemKind: String, Codable, Hashable, Sendable {
    case text
    case skill
    case tool
    case error
}

struct AgentTurnItem: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var sequence: Int
    var kindRaw: String
    var statusRaw: String
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
