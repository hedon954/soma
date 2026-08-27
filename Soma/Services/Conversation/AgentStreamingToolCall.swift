import Foundation
import SwiftOpenAI

struct AgentStreamingToolCall {
    var id = ""
    var name = ""
    var arguments = ""

    mutating func append(_ delta: ToolCall) {
        if let id = delta.id, !id.isEmpty {
            self.id = id
        }
        if let name = delta.function.name, !name.isEmpty {
            self.name += name
        }
        arguments += delta.function.arguments
    }

    func resolved(fallbackID: String) throws -> (native: ToolCall, local: AgentToolCall) {
        guard let name = AgentToolName(rawValue: name) else {
            throw ReActAgentError.invalidToolCall("未知工具 \(name.isEmpty ? "（空名称）" : name)")
        }
        do {
            let argumentData = arguments.isEmpty ? Data("{}".utf8) : Data(arguments.utf8)
            let normalized = try AgentToolArgumentNormalizer.normalize(
                argumentData,
                for: name
            )
            try AgentToolSchemaValidator.validateTopLevelKeys(
                normalized,
                for: name
            )
            let decoded = try JSONDecoder().decode(
                AgentToolArguments.self,
                from: normalized
            )
            return (native(fallbackID: fallbackID, name: name), AgentToolCall(
                name: name,
                arguments: decoded
            ))
        } catch let error as ReActAgentError {
            throw error
        } catch {
            throw ReActAgentError.invalidToolCall("\(name.rawValue) 参数不是有效 JSON：\(error.localizedDescription)")
        }
    }

    func prepared(fallbackID: String) throws -> AgentPreparedStreamingToolCall {
        guard let toolName = AgentToolName(rawValue: name) else {
            throw ReActAgentError.invalidToolCall("未知工具 \(name.isEmpty ? "（空名称）" : name)")
        }
        do {
            let resolved = try resolved(fallbackID: fallbackID)
            return AgentPreparedStreamingToolCall(
                native: resolved.native,
                local: resolved.local
            )
        } catch let ReActAgentError.invalidToolCall(message) {
            return AgentPreparedStreamingToolCall(
                native: native(fallbackID: fallbackID, name: toolName),
                local: AgentToolCall(name: toolName, arguments: AgentToolArguments()),
                preflightResult: .failure(
                    "参数校验失败：\(message) 请按已注册 Schema 修正后重新调用同一工具。",
                    code: "invalid_tool_arguments",
                    field: Self.fieldPath(from: message, fallback: toolName.rawValue),
                    expected: "数值字段使用 JSON number；自然语言分数先换算成小数；其余字段满足严格 Schema",
                    retryable: true
                )
            )
        }
    }

    private func native(fallbackID: String, name: AgentToolName) -> ToolCall {
        ToolCall(
            id: id.isEmpty ? fallbackID : id,
            function: FunctionCall(
                arguments: arguments.isEmpty ? "{}" : arguments,
                name: name.rawValue
            )
        )
    }

    private static func fieldPath(from message: String, fallback: String) -> String {
        guard let separator = message.firstIndex(of: "：") else { return fallback }
        let path = message[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? fallback : path
    }
}

struct AgentPreparedStreamingToolCall {
    var native: ToolCall
    var local: AgentToolCall
    var preflightResult: AgentToolResult?
}
