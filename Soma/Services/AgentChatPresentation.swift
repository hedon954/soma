import Foundation

enum AgentToolResultDisclosure {
    static let collapsedLineLimit = 4
    private static let collapsedCharacterThreshold = 80

    static func shouldCollapse(_ text: String) -> Bool {
        text.count > collapsedCharacterThreshold
            || text.components(separatedBy: .newlines).count
            > collapsedLineLimit
    }
}

struct AgentToolResultPresentation: Equatable {
    var summary: String
    var details: [String]
    var disclosureLabel: String?
    var detailSystemImage = "checkmark.circle"

    static func make(for item: AgentTurnItem) -> AgentToolResultPresentation? {
        guard
            let output = item.output,
            let data = output.data(using: .utf8),
            let result = try? JSONDecoder().decode(AgentToolResult.self, from: data)
        else {
            return nil
        }
        let context = AgentToolPresentationContext(item: item)
        let observation = result.observation
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if context.name == .listExerciseNames
            || context.scope == "exercises"
            || AgentToolPresentationFormatter.exerciseNames(in: observation) != nil
        {
            return exerciseLibraryPresentation(observation)
        }

        if context.name == .queryUserData, let scope = context.scope {
            return queryPresentation(observation, scope: scope)
        }

        return genericPresentation(observation)
    }

    private static func exerciseLibraryPresentation(
        _ observation: String
    ) -> AgentToolResultPresentation {
        let names = AgentToolPresentationFormatter.exerciseNames(in: observation) ?? []
        switch names.count {
        case 0:
            return AgentToolResultPresentation(
                summary: "动作库目前为空",
                details: [],
                disclosureLabel: nil,
                detailSystemImage: "figure.strengthtraining.traditional"
            )
        case 1 ... 3:
            return AgentToolResultPresentation(
                summary: "动作库中有 \(names.count) 个动作：\(names.joined(separator: "、"))",
                details: [],
                disclosureLabel: nil,
                detailSystemImage: "figure.strengthtraining.traditional"
            )
        default:
            return AgentToolResultPresentation(
                summary: "动作库中有 \(names.count) 个动作",
                details: names,
                disclosureLabel: "查看全部 \(names.count) 个动作",
                detailSystemImage: "figure.strengthtraining.traditional"
            )
        }
    }

    private static func queryPresentation(
        _ observation: String,
        scope: String
    ) -> AgentToolResultPresentation {
        if scope == "overview" {
            let details = AgentToolPresentationFormatter.friendlySegments(
                observation,
                separator: "；"
            )
            guard details.count > 1 else {
                return genericPresentation(observation)
            }
            return AgentToolResultPresentation(
                summary: "已读取个人资料和近期记录",
                details: details,
                disclosureLabel: "查看 \(details.count) 项信息",
                detailSystemImage: "person.text.rectangle"
            )
        }

        let kind = queryResultKind(for: scope)
        let details = AgentToolPresentationFormatter.friendlyLines(observation)
        guard details.count > 1 else {
            return genericPresentation(observation, systemImage: kind.systemImage)
        }
        return AgentToolResultPresentation(
            summary: "找到 \(details.count) 条\(kind.name)",
            details: details,
            disclosureLabel: "查看 \(details.count) 条\(kind.name)",
            detailSystemImage: kind.systemImage
        )
    }

    private static func queryResultKind(
        for scope: String
    ) -> (name: String, systemImage: String) {
        switch scope {
        case "workouts", "exercise_history", "sessions":
            ("训练记录", "figure.strengthtraining.traditional")
        case "meals":
            ("饮食记录", "fork.knife")
        case "body":
            ("身体记录", "figure.stand")
        case "gyms":
            ("健身房", "dumbbell.fill")
        case "programs":
            ("训练计划", "list.bullet.clipboard")
        case "templates":
            ("训练模板", "doc.text")
        default:
            ("记录", "checkmark.circle")
        }
    }

    private static func genericPresentation(
        _ observation: String,
        systemImage: String = "checkmark.circle"
    ) -> AgentToolResultPresentation {
        let lines = AgentToolPresentationFormatter.friendlyLines(observation)
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else {
            return AgentToolResultPresentation(
                summary: "已完成",
                details: [],
                disclosureLabel: nil,
                detailSystemImage: systemImage
            )
        }
        guard AgentToolResultDisclosure.shouldCollapse(text) else {
            return AgentToolResultPresentation(
                summary: text,
                details: [],
                disclosureLabel: nil,
                detailSystemImage: systemImage
            )
        }
        return AgentToolResultPresentation(
            summary: "操作已完成，可查看完整结果",
            details: lines.isEmpty ? [text] : lines,
            disclosureLabel: "查看完整结果",
            detailSystemImage: systemImage
        )
    }
}

enum AgentVisibleTextSanitizer {
    static func sanitize(_ text: String) -> String {
        var sanitized = text
        for pattern in [
            #"(?is)<tool_call[^>]*>.*?</tool_call\s*>"#,
            #"(?is)<function[^>]*>.*?</function\s*>"#,
            #"(?is)</?(?:function|tool_call)[^>]*>"#
        ] {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        let incompleteMarkers = [
            "<function",
            "</function",
            "<tool_call",
            "</tool_call"
        ]
        let earliestMarker = incompleteMarkers
            .compactMap { sanitized.range(of: $0, options: .caseInsensitive) }
            .min { lhs, rhs in
                sanitized.distance(from: sanitized.startIndex, to: lhs.lowerBound)
                    < sanitized.distance(from: sanitized.startIndex, to: rhs.lowerBound)
            }
        if let earliestMarker {
            sanitized.removeSubrange(earliestMarker.lowerBound...)
        }

        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AgentToolPresentationContext {
    var name: AgentToolName?
    var scope: String?

    init(item: AgentTurnItem) {
        var rawName: String?
        if let input = item.input,
           let data = input.data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data),
           let object = value as? [String: Any]
        {
            rawName = object["name"] as? String
            let arguments = object["arguments"] as? [String: Any] ?? object
            scope = arguments["scope"] as? String
        }
        name = rawName.flatMap(AgentToolName.init(rawValue:))
            ?? AgentToolName.allCases.first(where: {
                $0.displayTitle == item.title || $0.rawValue == item.title
            })
    }
}

private enum AgentToolPresentationFormatter {
    static func exerciseNames(in observation: String) -> [String]? {
        guard let data = observation.data(using: .utf8),
              let references = try? JSONDecoder().decode(
                  [ExerciseNameReference].self,
                  from: data
              )
        else {
            return nil
        }
        return references.map(\.name).filter { !$0.isEmpty }
    }

    static func friendlySegments(
        _ observation: String,
        separator: Character
    ) -> [String] {
        observation
            .split(separator: separator)
            .map { friendlyText(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func friendlyLines(_ observation: String) -> [String] {
        observation
            .components(separatedBy: .newlines)
            .map(friendlyText)
            .filter { !$0.isEmpty }
    }

    private static func friendlyText(_ text: String) -> String {
        var value = text.replacingOccurrences(
            of: #"\[id:[^\]]+\]\s*"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)(?:program_id|template_id|session_id|record_id|exercise_id):[0-9a-f-]{36}\s*"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)(^|[^0-9.])0(?:\.0+)?kg(?=$|[^a-z0-9])"#,
            with: "$1自重",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s+([：；，。])"#,
            with: "$1",
            options: .regularExpression
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
