import Foundation

struct AgentQuestionAction: Codable, Equatable, Sendable {
    var toolName: AgentToolName
    var argumentsJSON: String
    var schemaVersion: Int? = nil

    enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case argumentsJSON = "arguments_json"
        case schemaVersion = "schema_version"
    }

    static var allowedTools: [AgentToolName] {
        AgentToolName.allCases.filter { $0.isTypedTool || [.updateGym, .switchGym].contains($0) }
    }

    func validatedCall(allowedNames: Set<String>) throws -> AgentToolCall {
        guard Self.allowedTools.contains(toolName), allowedNames.contains(toolName.rawValue),
              schemaVersion == nil || schemaVersion == toolName.schemaVersion,
              argumentsJSON.utf8.count <= 32768
        else { throw AgentQuestionError.invalidAction }
        let data = Data(argumentsJSON.utf8)
        try AgentToolSchemaValidator.validate(data, for: toolName, schemaVersion: schemaVersion ?? toolName.schemaVersion)
        return try AgentToolCall(name: toolName, arguments: JSONDecoder().decode(AgentToolArguments.self, from: data))
    }
}

struct AgentQuestionOption: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var text: String
    var action: AgentQuestionAction? = nil
}

struct AgentUserQuestion: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var question: String
    var options: [AgentQuestionOption]
    var allowsCustomInput: Bool

    enum CodingKeys: String, CodingKey {
        case id, question, options
        case allowsCustomInput = "allows_custom_input"
    }
}

enum AgentQuestionError: LocalizedError {
    case invalidQuestions
    case invalidAction
    case expired

    var errorDescription: String? {
        switch self {
        case .invalidQuestions: "请提供 1 到 3 个问题；每题最多 6 个非空选项，或允许用户自行输入。问题和选项 ID 必须唯一。"
        case .invalidAction: "按钮绑定的操作不可用，请使用当前已开放工具及其完整有效参数，或省略 action 作为普通文本选项。"
        case .expired: "这个问题已经失效，请直接发送你的需求。"
        }
    }
}

struct AgentUserQuestionRequest: Codable, Equatable, Sendable {
    var questions: [AgentUserQuestion]

    var historyText: String {
        questions.map { item in
            ([item.question] + item.options.map { "- \($0.text)" }
                + (item.allowsCustomInput ? ["也可以直接输入你的情况。"] : [])).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    static func from(_ result: AgentToolResult) -> Self? {
        guard result.ok, result.code == "user_questions", let data = result.data,
              let encoded = try? JSONEncoder().encode(data)
        else { return nil }
        return try? JSONDecoder().decode(Self.self, from: encoded)
    }

    static func from(items: [AgentTurnItem]) -> Self? {
        for item in items.reversed() where item.kind == .tool && item.status == .succeeded {
            guard let output = item.output,
                  let result = try? JSONDecoder().decode(AgentToolResult.self, from: Data(output.utf8)),
                  let request = Self.from(result)
            else { continue }
            return request
        }
        return nil
    }
}

enum AgentUserQuestionsTool {
    static func result(
        questions: [AgentUserQuestion]?,
        allowedNames: Set<String> = Set(AgentToolName.allCases.map(\.rawValue))
    ) -> AgentToolResult {
        do {
            guard var questions, (1 ... 3).contains(questions.count),
                  Set(questions.map(\.id)).count == questions.count
            else { throw AgentQuestionError.invalidQuestions }
            for index in questions.indices {
                let question = questions[index]
                guard valid(question.id, maximum: 64), valid(question.question, maximum: 300),
                      question.options.count <= 6,
                      !question.options.isEmpty || question.allowsCustomInput,
                      Set(question.options.map(\.id)).count == question.options.count
                else { throw AgentQuestionError.invalidQuestions }
                for optionIndex in question.options.indices {
                    let option = question.options[optionIndex]
                    guard valid(option.id, maximum: 64), valid(option.text, maximum: 300)
                    else { throw AgentQuestionError.invalidQuestions }
                    if var action = option.action {
                        _ = try action.validatedCall(allowedNames: allowedNames)
                        action.schemaVersion = action.toolName.schemaVersion
                        questions[index].options[optionIndex].action = action
                    }
                }
            }
            let request = AgentUserQuestionRequest(questions: questions)
            let data = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(request))
            return .success(request.historyText, code: "user_questions", data: data)
        } catch {
            return .failure(error.localizedDescription, code: "invalid_tool_arguments", field: "questions")
        }
    }

    private static func valid(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= maximum
    }
}

extension AIService {
    func completeQuestionIfNeeded(
        observations: [AgentObservation],
        trace: ((AgentTraceEvent) -> Void)?
    ) throws -> AgentOutcome? {
        guard let observation = observations.last(where: {
            $0.action.name == .askUserQuestions && AgentUserQuestionRequest.from($0.result) != nil
        }) else { return nil }
        return try completeAgentRun(
            passage: observation.result.message, assistantPassages: [], observations: observations, trace: trace
        )
    }
}
