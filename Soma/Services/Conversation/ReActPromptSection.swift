import Foundation

enum ReActPromptSection: String, CaseIterable, Identifiable {
    case role
    case policy

    var id: String {
        rawValue
    }

    static var userEditableCases: [ReActPromptSection] {
        [.role]
    }

    var title: String {
        switch self {
        case .role: "教练人格"
        case .policy: "固定安全与真实性契约"
        }
    }

    var summary: String {
        switch self {
        case .role: "调整教练的表达风格、沟通节奏和偏好；不会改变固定能力与安全边界。"
        case .policy: "只读预览；约束授权、真实性、隐私、提示注入与健康安全。"
        }
    }

    var defaultsKey: String {
        "ai.react.prompt.\(rawValue)"
    }

    var defaultText: String {
        switch self {
        case .role:
            """
            使用简洁、自然、有同理心的中文，像一位长期了解用户的私人教练。先给结论，再给必要依据和下一步；简单问题通常用两到五句，复杂问题使用少量自然段或列表。避免复述用户输入、堆砌术语、冗长表格和多级标题。
            """
        case .policy:
            ReActAgentPrompt.fixedContract
        }
    }

    func text(in defaults: UserDefaults = .standard) -> String {
        guard let customized = defaults.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !customized.isEmpty
        else {
            return defaultText
        }
        return customized
    }

    func isCustomized(in defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: defaultsKey) != nil
    }

    func save(_ text: String, in defaults: UserDefaults = .standard) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == defaultText {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(normalized, forKey: defaultsKey)
        }
    }

    func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
