import Foundation

enum AgentSkill: String, CaseIterable, Identifiable {
    case gymAnalysis = "gym_analysis"
    case trainingPlan = "training_plan"
    case movementAnalysis = "movement_analysis"
    case nutritionAnalysis = "nutrition_analysis"
    case postureAnalysis = "posture_analysis"
    case trendAnalysis = "trend_analysis"
    case trainingVolumeAnalysis = "training_volume_analysis"
    case calorieEstimation = "calorie_estimation"
    case workoutLogging = "workout_logging"

    var id: String {
        rawValue
    }

    var title: String {
        content.title
    }

    var summary: String {
        content.description
    }

    var whenToUse: String {
        content.whenToUse
    }

    var defaultsKey: String {
        "ai.react.skill.\(rawValue)"
    }

    static var catalogForToolDescription: String {
        allCases.map { "\($0.rawValue)=\($0.title)" }.joined(separator: "；")
    }

    var defaultText: String {
        content.body
    }

    private var content: BuiltInSkillContent {
        guard let content = Self.builtInContent[self] else {
            preconditionFailure("Missing bundled Skill: \(id)")
        }
        return content
    }

    private static let builtInContent = Dictionary(uniqueKeysWithValues: allCases.map { skill in
        (skill, BuiltInSkillContent(id: skill.rawValue))
    })

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

    func markdown(in defaults: UserDefaults = .standard) -> String {
        """
        ---
        name: \(rawValue)
        description: \(summary)
        when_to_use: \(whenToUse)
        ---

        \(text(in: defaults))
        """
    }
}

private struct BuiltInSkillContent {
    let title: String
    let description: String
    let whenToUse: String
    let body: String

    init(id: String) {
        guard let file = Bundle.main.url(forResource: id, withExtension: "md", subdirectory: "Prompts/Skills"),
              let markdown = try? String(contentsOf: file, encoding: .utf8),
              let separator = markdown.range(of: "\n---\n\n"),
              markdown.hasSuffix("\n")
        else {
            preconditionFailure("Missing or malformed bundled Skill: \(id)")
        }

        let metadata = markdown[..<separator.lowerBound].split(separator: "\n")
        let body = markdown[separator.upperBound...].dropLast()
        guard metadata.count == 4,
              metadata[0] == "---",
              metadata[1] == "name: \(id)",
              metadata[2].hasPrefix("description: "),
              metadata[3].hasPrefix("when_to_use: "),
              let heading = body.split(separator: "\n", maxSplits: 1).first,
              heading.hasPrefix("# ")
        else {
            preconditionFailure("Malformed metadata for bundled Skill: \(id)")
        }
        title = String(heading.dropFirst("# ".count))
        description = String(metadata[2].dropFirst("description: ".count))
        whenToUse = String(metadata[3].dropFirst("when_to_use: ".count))
        self.body = String(body)
    }
}
