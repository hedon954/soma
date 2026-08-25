import Foundation

struct AgentToolCall: Codable, Equatable {
    var name: AgentToolName
    var arguments: AgentToolArguments

    /// ADR 0049：规范化语义键，避免字面 JSON 差异（同义字段、缺省与 null）绕过幂等。
    var signature: String {
        AgentToolCallSignature.canonical(name: name, arguments: arguments)
    }
}

struct AgentObservation: Codable, Equatable {
    var step: Int
    var action: AgentToolCall
    var result: AgentToolResult
}

struct AgentOutcome: Equatable, @unchecked Sendable {
    var finalAnswer: String
    var observations: [AgentObservation]

    var primaryRecordType: ConversationIntent? {
        observations.compactMap(\.result.recordType).last
    }
}
