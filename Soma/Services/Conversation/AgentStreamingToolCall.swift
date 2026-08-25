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
        let argumentData = arguments.isEmpty ? Data("{}".utf8) : Data(arguments.utf8)
        try AgentToolSchemaValidator.validateTopLevelKeys(
            argumentData,
            for: name
        )
        let decoded: AgentToolArguments
        do {
            decoded = try JSONDecoder().decode(AgentToolArguments.self, from: argumentData)
        } catch {
            throw ReActAgentError.invalidToolCall("\(name.rawValue) 参数不是有效 JSON：\(error.localizedDescription)")
        }
        let callID = id.isEmpty ? fallbackID : id
        return (
            ToolCall(
                id: callID,
                function: FunctionCall(arguments: arguments.isEmpty ? "{}" : arguments, name: name.rawValue)
            ),
            AgentToolCall(name: name, arguments: decoded)
        )
    }
}
