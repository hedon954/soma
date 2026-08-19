import Foundation

enum AgentTurnVisibleItems {
    /// ADR 0014 / ADR 0077：空文字卡去掉；Skill/Tool/错误和有内容的文字全部保留。
    static func make(from items: [AgentTurnItem]) -> [AgentTurnItem] {
        items.filter {
            $0.kind != .text
                || !AgentVisibleTextSanitizer.sanitize($0.text).isEmpty
        }
    }
}

/// PRD 020：连续 Skill/Tool 收成一条可展开过程；文字和失败卡仍按原顺序打断该组。
enum AgentTurnTranscriptSegment: Equatable, Identifiable {
    case process(id: UUID, items: [AgentTurnItem])
    case item(AgentTurnItem)

    var id: UUID {
        switch self {
        case let .process(id, _):
            id
        case let .item(item):
            item.id
        }
    }

    var items: [AgentTurnItem] {
        switch self {
        case let .process(_, items):
            items
        case let .item(item):
            [item]
        }
    }
}

enum AgentTurnTranscriptSegments {
    static func make(from items: [AgentTurnItem]) -> [AgentTurnTranscriptSegment] {
        var segments: [AgentTurnTranscriptSegment] = []
        var process: [AgentTurnItem] = []

        func flushProcess() {
            guard !process.isEmpty else { return }
            segments.append(.process(id: process[0].id, items: process))
            process = []
        }

        for item in AgentTurnVisibleItems.make(from: items) {
            if Self.isGroupableProcess(item) {
                process.append(item)
            } else {
                flushProcess()
                segments.append(.item(item))
            }
        }
        flushProcess()
        return segments
    }

    static func processSummary(for items: [AgentTurnItem]) -> String {
        guard !items.isEmpty else { return "执行过程" }
        if items.contains(where: { $0.status == .running }) {
            return items.count == 1
                ? (items[0].title.isEmpty ? "正在执行" : items[0].title)
                : "正在执行 \(items.count) 步"
        }

        var groups: [(title: String, count: Int)] = []
        for item in items {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = title.isEmpty ? "执行" : title
            if let last = groups.last, last.title == label {
                groups[groups.count - 1].count += 1
            } else {
                groups.append((label, 1))
            }
        }
        return groups.map { group in
            group.count == 1 ? group.title : "\(group.title) ×\(group.count)"
        }.joined(separator: " · ")
    }

    static func isGroupableProcess(_ item: AgentTurnItem) -> Bool {
        switch item.kind {
        case .skill, .tool:
            item.status != .failed && item.status != .cancelled
        case .text, .error:
            false
        }
    }
}

enum AgentProcessCardPolicy {
    /// PRD 020：Skill/Tool 过程卡默认折叠为可展开状态行；折叠不等于删除。
    static let defaultsCollapsed = true
}

enum AgentToolResultDisclosure {
    static let collapsedLineLimit = 4
    /// 约 4 行 caption 正文；未超过行数且未超过该字数时不显示展开按钮。
    private static let collapsedCharacterThreshold = 200

    static func shouldCollapse(_ text: String) -> Bool {
        let lineCount = text.components(separatedBy: .newlines).count
        return lineCount > collapsedLineLimit
            || text.count > collapsedCharacterThreshold
    }
}

struct AgentToolResultPresentation: Equatable {
    var summary: String
    var details: [String]
    var disclosureLabel: String?
    var detailSystemImage = "checkmark.circle"
    var defaultsCollapsed = AgentProcessCardPolicy.defaultsCollapsed

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

        if AgentToolPresentationFormatter.exerciseNames(in: observation) != nil {
            return exerciseLibraryPresentation(observation)
        }

        if context.name == .searchExercises {
            return searchExercisesPresentation(result)
        }

        if let scope = context.scope ?? queryScope(for: context.name) {
            return queryPresentation(observation, scope: scope)
        }

        return genericPresentation(observation)
    }

    private static func queryScope(for name: AgentToolName?) -> String? {
        switch name {
        case .listWorkouts, .getWorkout: "workouts"
        case .listMeals, .getMeal: "meals"
        case .listBodyEntries, .getBodyEntry: "body"
        case .listPrograms, .getProgram: "programs"
        default: nil
        }
    }

    private static func searchExercisesPresentation(
        _ result: AgentToolResult
    ) -> AgentToolResultPresentation {
        let image = "figure.strengthtraining.traditional"
        let summary = AgentToolPresentationFormatter.friendlyLines(result.observation)
            .first
            ?? "已完成"
        let names = AgentToolPresentationFormatter.names(in: result.data)
        guard !names.isEmpty else {
            return compactPresentation(summary, systemImage: image)
        }
        return collapsedPresentation(
            summary: summary,
            details: names,
            systemImage: image
        )
    }

    private static func exerciseLibraryPresentation(
        _ observation: String
    ) -> AgentToolResultPresentation {
        let names = AgentToolPresentationFormatter.exerciseNames(in: observation) ?? []
        let image = "figure.strengthtraining.traditional"
        guard !names.isEmpty else {
            return compactPresentation("动作库目前为空", systemImage: image)
        }
        if names.count == 1 {
            return compactPresentation(
                "动作库中有 1 个动作：\(names[0])",
                systemImage: image
            )
        }
        return collapsedPresentation(
            summary: "动作库中有 \(names.count) 个动作",
            details: names,
            systemImage: image
        )
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
            return collapsedPresentation(
                summary: "已读取个人资料和近期记录",
                details: details,
                systemImage: "person.text.rectangle"
            )
        }

        let kind = queryResultKind(for: scope)
        let details = AgentToolPresentationFormatter.friendlyLines(observation)
        guard details.count > 1 else {
            return genericPresentation(observation, systemImage: kind.systemImage)
        }
        return collapsedPresentation(
            summary: "找到 \(details.count) 条\(kind.name)",
            details: details,
            systemImage: kind.systemImage
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
            return compactPresentation("已完成", systemImage: systemImage)
        }
        let needsDisclosure = lines.count > 1 || AgentToolResultDisclosure.shouldCollapse(text)
        guard needsDisclosure else {
            return compactPresentation(text, systemImage: systemImage)
        }
        return collapsedPresentation(
            summary: lines[0],
            details: lines,
            systemImage: systemImage
        )
    }

    private static func compactPresentation(
        _ summary: String,
        systemImage: String
    ) -> AgentToolResultPresentation {
        AgentToolResultPresentation(
            summary: summary,
            details: [],
            disclosureLabel: nil,
            detailSystemImage: systemImage,
            defaultsCollapsed: AgentProcessCardPolicy.defaultsCollapsed
        )
    }

    /// 默认只露一行状态；展开后显示完整结果。过程卡本身始终保留。
    private static func collapsedPresentation(
        summary: String,
        details: [String],
        systemImage: String
    ) -> AgentToolResultPresentation {
        AgentToolResultPresentation(
            summary: summary,
            details: details,
            disclosureLabel: "展开",
            detailSystemImage: systemImage,
            defaultsCollapsed: AgentProcessCardPolicy.defaultsCollapsed
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

    static func names(in data: AgentJSONValue?) -> [String] {
        guard case let .object(object) = data,
              case let .array(items) = object["items"]
        else {
            return []
        }
        return items.compactMap { item in
            guard case let .object(object) = item,
                  case let .string(name) = object["name"]
            else {
                return nil
            }
            return name
        }.filter { !$0.isEmpty }
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
