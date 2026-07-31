import Foundation

enum RemoteAgentError: LocalizedError, Equatable {
    case endpointMissing
    case identityUnavailable
    case invalidResponse
    case protocolMismatch
    case server(code: String, message: String)
    case toolRejected(String)

    var errorDescription: String? {
        switch self {
        case .endpointMissing:
            "请先在设置中填写 Soma 后台服务地址。"
        case .identityUnavailable:
            "无法创建本机设备身份，请检查设备安全设置。"
        case .invalidResponse:
            "Soma 后台返回了无法识别的响应。"
        case .protocolMismatch:
            "App 与 Soma 后台协议版本不一致，请更新后重试。"
        case let .server(_, message):
            message
        case let .toolRejected(message):
            message
        }
    }
}

enum RemoteJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: RemoteJSONValue])
    case array([RemoteJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(
            [String: RemoteJSONValue].self
        ) {
            self = .object(value)
        } else {
            self = try .array(container.decode([RemoteJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case let .number(value) = self else { return nil }
        return Int(exactly: value)
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var objectValue: [String: RemoteJSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }
}

struct RemoteAgentJobSnapshot: Codable, Equatable, Sendable {
    var id: String
    var clientJobID: String
    var turnID: String
    var sessionID: String
    var state: String
    var lastSequence: Int
    var createdAt: Date
    var updatedAt: Date
    var errorCode: String?
}

struct RemoteAgentEvent: Codable, Equatable, Sendable {
    var id: String
    var jobID: String
    var sequence: Int
    var kind: String
    var phase: String
    var payloadVersion: Int
    var payload: [String: RemoteJSONValue]
    var createdAt: Date
}

struct RemoteAgentEventPage: Codable, Equatable, Sendable {
    var jobID: String
    var events: [RemoteAgentEvent]
    var nextSequence: Int
    var terminal: Bool
}

struct RemoteDeviceToolRequest: Equatable, Sendable {
    var toolCallID: String
    var name: String
    var schemaVersion: Int
    var arguments: [String: RemoteJSONValue]
    var mutation: Bool

    init?(event: RemoteAgentEvent) {
        guard event.kind == "tool",
              event.phase == "suspended",
              let toolCallID = event.payload["toolCallID"]?.stringValue,
              let name = event.payload["toolName"]?.stringValue,
              let schemaVersion = event.payload["schemaVersion"]?.intValue,
              let arguments = event.payload["arguments"]?.objectValue,
              let mutation = event.payload["mutation"]?.boolValue
        else {
            return nil
        }
        self.toolCallID = toolCallID
        self.name = name
        self.schemaVersion = schemaVersion
        self.arguments = arguments
        self.mutation = mutation
    }
}

protocol AgentExecutionBackend: Sendable {
    var kind: AgentExecutionBackendKind { get }

    func submit(
        job: AgentJobSubmission
    ) async throws -> RemoteAgentJobSnapshot

    func events(
        remoteJobID: String,
        after sequence: Int
    ) async throws -> RemoteAgentEventPage

    func cancel(remoteJobID: String) async throws

    func acknowledge(
        remoteJobID: String,
        through sequence: Int
    ) async throws

    func submitToolResult(
        remoteJobID: String,
        toolCallID: String,
        result: AgentToolResult
    ) async throws
}

struct AgentJobSubmission: Sendable {
    var clientJobID: UUID
    var turnID: UUID
    var sessionID: UUID
    var text: String
    var contextSnapshot: String
    var attachments: [MediaAttachmentReference]
    var liveActivityEnabled: Bool
}

struct LocalAgentExecutionBackend: AgentExecutionBackend {
    let kind = AgentExecutionBackendKind.local

    func submit(job _: AgentJobSubmission) async throws -> RemoteAgentJobSnapshot {
        throw RemoteAgentError.toolRejected("本机 Backend 由设备 ReAct runner 直接执行。")
    }

    func events(
        remoteJobID _: String,
        after _: Int
    ) async throws -> RemoteAgentEventPage {
        throw RemoteAgentError.toolRejected("本机 Backend 不使用远端 Event。")
    }

    func cancel(remoteJobID _: String) async throws {}

    func acknowledge(
        remoteJobID _: String,
        through _: Int
    ) async throws {}

    func submitToolResult(
        remoteJobID _: String,
        toolCallID _: String,
        result _: AgentToolResult
    ) async throws {
        throw RemoteAgentError.toolRejected("本机 Backend 不接受远端 Tool Result。")
    }
}
