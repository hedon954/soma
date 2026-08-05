import Foundation

enum AgentToolGroup: String, CaseIterable, Sendable {
    case core
    case plans
    case gym
    case review

    static var expandableCases: [AgentToolGroup] {
        [.plans, .gym, .review]
    }

    var tools: [AgentToolName] {
        switch self {
        case .core:
            [
                .loadSkill,
                .queryUserData,
                .listExerciseNames,
                .recordWorkout,
                .recordMeal,
                .recordBody,
                .updateWorkout,
                .updateMeal,
                .updateBody,
                .deleteRecord,
                .expandToolGroup
            ]
        case .plans:
            [
                .listTrainingPrograms,
                .getTrainingProgram,
                .createTrainingProgram,
                .createWorkoutTemplateVersion,
                .updateWorkoutTemplate,
                .archiveTrainingProgram,
                .deleteTrainingProgram,
                .startGuidedWorkout
            ]
        case .gym:
            [.updateGym, .switchGym]
        case .review:
            [.recordPerformanceAnalysis]
        }
    }
}

struct AgentToolExposureSignals: Equatable, Sendable {
    var text: String
    var hasVideo: Bool
    var hasActiveProgram: Bool
    var hasActiveGuidedSession: Bool
}

enum AgentToolExposurePolicy {
    static func initialGroups(signals: AgentToolExposureSignals) -> Set<AgentToolGroup> {
        var groups: Set<AgentToolGroup> = [.core]
        let lowered = signals.text.lowercased()
        if signals.hasActiveProgram
            || signals.hasActiveGuidedSession
            || containsAny(
                lowered,
                [
                    "计划", "模板", "带练", "训练计划", "开始练", "执行计划",
                    "program", "template"
                ]
            )
        {
            groups.insert(.plans)
        }
        if containsAny(lowered, ["健身房", "器械", "场馆", "换馆", "gym"]) {
            groups.insert(.gym)
        }
        if signals.hasVideo
            || containsAny(lowered, ["复盘", "视频分析", "动作分析", "review"])
        {
            groups.insert(.review)
        }
        return groups
    }

    static func tools(for groups: Set<AgentToolGroup>) -> [AgentToolName] {
        var seen = Set<AgentToolName>()
        var ordered: [AgentToolName] = []
        for group in AgentToolGroup.allCases where groups.contains(group) {
            for tool in group.tools where seen.insert(tool).inserted {
                ordered.append(tool)
            }
        }
        return ordered
    }

    static func expanding(
        _ groupRaw: String?,
        into groups: inout Set<AgentToolGroup>
    ) -> AgentToolResult {
        guard let groupRaw,
              let group = AgentToolGroup(rawValue: groupRaw),
              AgentToolGroup.expandableCases.contains(group)
        else {
            return .failure("tool_group 仅支持 plans、gym、review。")
        }
        if groups.contains(group) {
            return .success("工具组 \(group.rawValue) 已经展开。")
        }
        groups.insert(group)
        let names = group.tools.map(\.rawValue).joined(separator: ", ")
        return .success("已展开工具组 \(group.rawValue)：\(names)。后续步骤可使用这些工具。")
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
