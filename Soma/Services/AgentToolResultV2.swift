import Foundation

enum AgentJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AgentJSONValue])
    case array([AgentJSONValue])
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
        } else if let value = try? container.decode([String: AgentJSONValue].self) {
            self = .object(value)
        } else {
            self = try .array(container.decode([AgentJSONValue].self))
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
}

struct AgentRecordReference: Codable, Equatable, Sendable {
    var recordType: String
    var recordID: Int64
    var title: String?

    enum CodingKeys: String, CodingKey {
        case title
        case recordType = "record_type"
        case recordID = "record_id"
    }
}

struct AgentToolPage: Codable, Equatable, Sendable {
    var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case nextCursor = "next_cursor"
    }
}

struct AgentToolResult: Codable, Equatable, Sendable {
    var ok: Bool
    var code: String
    var message: String
    var data: AgentJSONValue?
    var recordRefs: [AgentRecordReference]?
    var page: AgentToolPage?
    var recordType: ConversationIntent?
    var field: String?
    var expected: String?
    var retryable: Bool?

    var observation: String {
        message
    }

    enum CodingKeys: String, CodingKey {
        case ok, code, message, data, page, observation, field, expected, retryable
        case recordRefs = "record_refs"
        case recordType = "record_type"
    }

    init(
        ok: Bool,
        code: String,
        message: String,
        data: AgentJSONValue? = nil,
        recordRefs: [AgentRecordReference]? = nil,
        page: AgentToolPage? = nil,
        recordType: ConversationIntent? = nil,
        field: String? = nil,
        expected: String? = nil,
        retryable: Bool? = nil
    ) {
        self.ok = ok
        self.code = code
        self.message = message
        self.data = data
        self.recordRefs = recordRefs
        self.page = page
        self.recordType = recordType
        self.field = field
        self.expected = expected
        self.retryable = retryable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        code = try container.decodeIfPresent(String.self, forKey: .code)
            ?? (ok ? "ok" : "error")
        message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .observation)
            ?? ""
        data = try container.decodeIfPresent(AgentJSONValue.self, forKey: .data)
        recordRefs = try container.decodeIfPresent(
            [AgentRecordReference].self,
            forKey: .recordRefs
        )
        page = try container.decodeIfPresent(AgentToolPage.self, forKey: .page)
        recordType = try container.decodeIfPresent(ConversationIntent.self, forKey: .recordType)
        field = try container.decodeIfPresent(String.self, forKey: .field)
        expected = try container.decodeIfPresent(String.self, forKey: .expected)
        retryable = try container.decodeIfPresent(Bool.self, forKey: .retryable)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ok, forKey: .ok)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(recordRefs, forKey: .recordRefs)
        try container.encodeIfPresent(page, forKey: .page)
        try container.encodeIfPresent(recordType, forKey: .recordType)
        try container.encodeIfPresent(field, forKey: .field)
        try container.encodeIfPresent(expected, forKey: .expected)
        try container.encodeIfPresent(retryable, forKey: .retryable)
    }

    static func success(
        _ message: String,
        code: String = "ok",
        data: AgentJSONValue? = nil,
        recordRefs: [AgentRecordReference]? = nil,
        page: AgentToolPage? = nil,
        recordType: ConversationIntent? = nil
    ) -> AgentToolResult {
        AgentToolResult(
            ok: true,
            code: code,
            message: message,
            data: data,
            recordRefs: recordRefs,
            page: page,
            recordType: recordType
        )
    }

    static func failure(
        _ message: String,
        code: String = "invalid_request",
        field: String? = nil,
        expected: String? = nil,
        retryable: Bool = true
    ) -> AgentToolResult {
        AgentToolResult(
            ok: false,
            code: code,
            message: message,
            field: field,
            expected: expected,
            retryable: retryable
        )
    }
}
