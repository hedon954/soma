import SwiftOpenAI

enum AgentUserQuestionsSchema {
    static var parameters: JSONSchema {
        object([
            "questions": JSONSchema(
                type: .array,
                description: "1 到 3 个问题。未设置 selection 时，点按一个选项立即发送。排训练计划时必须设置 selection，点按只切换选中，每题都允许自填，整张卡片一次发送。",
                items: object([
                    "id": string("当前请求内唯一的问题 ID，1 到 64 字"),
                    "question": string("简短具体的问题，最多 300 字"),
                    "options": JSONSchema(
                        type: .array,
                        description: "最多 6 个选项；允许自定义输入时可以为空。",
                        items: object([
                            "id": string("题内唯一的选项 ID，1 到 64 字"),
                            "text": string("以用户口吻写完整、可独立理解的一句话，最多 300 字；同时作为按钮文字和发送内容"),
                            "action": object([
                                "tool_name": JSONSchema(
                                    type: .string,
                                    description: "可选绑定一个本轮已开放的确定性工具；参数必须已明确，不能依赖回答后的模型判断",
                                    enum: AgentQuestionAction.allowedTools.map(\.rawValue)
                                ),
                                "arguments_json": string("该工具的完整 JSON 参数对象字符串，严格遵守对应工具 Schema，最多 32768 UTF-8 字节")
                            ], required: ["tool_name", "arguments_json"])
                        ], required: ["id", "text"])
                    ),
                    "allows_custom_input": JSONSchema(type: .boolean, description: "选项可能不完整时设为 true，提供自定义输入框。设置了 selection 时必须为 true"),
                    "selection": JSONSchema(
                        type: .string,
                        description: "single 单选，multiple 多选。设置后点按不发送，并且不能绑定 action",
                        enum: [AgentQuestionSelection.single.rawValue, AgentQuestionSelection.multiple.rawValue]
                    )
                ], required: ["id", "question", "options", "allows_custom_input"])
            )
        ], required: ["questions"])
    }

    private static func string(_ description: String) -> JSONSchema {
        JSONSchema(type: .string, description: description)
    }

    private static func object(_ properties: [String: JSONSchema], required: [String]) -> JSONSchema {
        JSONSchema(type: .object, properties: properties, required: required, additionalProperties: false)
    }
}
