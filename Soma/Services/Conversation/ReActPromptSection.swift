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
            SomaPrompt.text("coach_default_persona").trimmingCharacters(in: .whitespacesAndNewlines)
        case .policy:
            ReActAgentPrompt.system
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
