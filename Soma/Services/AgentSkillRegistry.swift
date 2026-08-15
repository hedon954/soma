import Foundation

struct AgentSkillDescriptor: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var summary: String
    var whenToUse: String
    var markdown: String
    var toolGroups: Set<AgentToolGroup>
    var isBuiltIn: Bool
}

struct AgentCustomSkill: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var description: String
    var whenToUse: String
    var content: String
    var toolGroupIDs: [String]

    var descriptor: AgentSkillDescriptor {
        let groups = Set(toolGroupIDs.compactMap(AgentToolGroup.init(rawValue:)))
            .intersection(AgentSkillRegistry.allowedCustomToolGroups)
        return AgentSkillDescriptor(
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
            toolGroups: groups,
            isBuiltIn: false
        )
    }
}

enum AgentSkillRegistry {
    static let customSkillsKey = "ai.react.custom-skills.v1"
    static let quickSkillIDsKey = "ai.react.quick-skill-ids.v1"
    static let allowedCustomToolGroups: Set<AgentToolGroup> = [
        .exercises, .workouts, .meals, .body, .plans, .gym, .review
    ]

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
        setQuickSkillIDs(
            quickSkillIDs(defaults: defaults).filter { $0 != id },
            defaults: defaults
        )
    }

    static func quickSkillIDs(defaults: UserDefaults = .standard) -> [String] {
        let stored = defaults.stringArray(forKey: quickSkillIDsKey) ?? []
        if !stored.isEmpty {
            return Array(stored.prefix(6))
        }
        return AgentSkill.defaultQuickSkills.map(\.rawValue)
    }

    static func quickDescriptors(
        defaults: UserDefaults = .standard
    ) -> [AgentSkillDescriptor] {
        let byID = Dictionary(uniqueKeysWithValues: allDescriptors(defaults: defaults).map {
            ($0.id, $0)
        })
        return quickSkillIDs(defaults: defaults).compactMap { byID[$0] }
    }

    static func setQuickSkillIDs(
        _ ids: [String],
        defaults: UserDefaults = .standard
    ) {
        let allowed = Set(allDescriptors(defaults: defaults).map(\.id))
        var seen = Set<String>()
        let normalized = ids.filter {
            allowed.contains($0) && seen.insert($0).inserted
        }
        defaults.set(Array(normalized.prefix(6)), forKey: quickSkillIDsKey)
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
            toolGroups: toolGroups,
            isBuiltIn: true
        )
    }
}
