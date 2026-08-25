import Foundation

/// ADR 0082：Skill 只描述专业方法。工具权限由输入框快捷按钮持有，Skill 不再自带工具分组。
struct AgentSkillDescriptor: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var summary: String
    var whenToUse: String
    var markdown: String
    var isBuiltIn: Bool
}

struct AgentCustomSkill: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var description: String
    var whenToUse: String
    var content: String

    var descriptor: AgentSkillDescriptor {
        AgentSkillDescriptor(
            id: id,
            title: name,
            summary: description,
            whenToUse: whenToUse,
            markdown: """
            ---
            name: \(id)
            description: \(description)
            when_to_use: \(whenToUse)
            ---

            \(content)
            """,
            isBuiltIn: false
        )
    }
}

enum AgentSkillRegistry {
    static let customSkillsKey = "ai.react.custom-skills.v1"

    static func allDescriptors(
        defaults: UserDefaults = .standard
    ) -> [AgentSkillDescriptor] {
        AgentSkill.allCases.map { $0.descriptor(in: defaults) }
            + customSkills(defaults: defaults).map(\.descriptor)
    }

    static func descriptor(
        id: String,
        defaults: UserDefaults = .standard
    ) -> AgentSkillDescriptor? {
        allDescriptors(defaults: defaults).first { $0.id == id }
    }

    static func customSkills(
        defaults: UserDefaults = .standard
    ) -> [AgentCustomSkill] {
        guard let data = defaults.data(forKey: customSkillsKey) else { return [] }
        return (try? JSONDecoder().decode([AgentCustomSkill].self, from: data)) ?? []
    }

    static func save(
        _ skill: AgentCustomSkill,
        defaults: UserDefaults = .standard
    ) {
        var values = customSkills(defaults: defaults)
        if let index = values.firstIndex(where: { $0.id == skill.id }) {
            values[index] = skill
        } else {
            values.append(skill)
        }
        persist(values, defaults: defaults)
    }

    static func delete(
        id: String,
        defaults: UserDefaults = .standard
    ) {
        persist(
            customSkills(defaults: defaults).filter { $0.id != id },
            defaults: defaults
        )
        // 快捷按钮可能绑着这个 Skill；删除后解绑，避免发送时注入不存在的 Skill 正文。
        let shortcuts = AgentInputShortcutStore.shortcuts(defaults: defaults)
        if shortcuts.contains(where: { $0.skillID == id }) {
            AgentInputShortcutStore.replaceAll(
                shortcuts.map { shortcut in
                    var value = shortcut
                    if value.skillID == id {
                        value.skillID = nil
                    }
                    return value
                },
                defaults: defaults
            )
        }
    }

    private static func persist(
        _ values: [AgentCustomSkill],
        defaults: UserDefaults
    ) {
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: customSkillsKey)
        }
    }
}

extension AgentSkill {
    func descriptor(in defaults: UserDefaults = .standard) -> AgentSkillDescriptor {
        AgentSkillDescriptor(
            id: rawValue,
            title: title,
            summary: summary,
            whenToUse: whenToUse,
            markdown: markdown(in: defaults),
            isBuiltIn: true
        )
    }
}
