import Foundation

/// PRD 033：分组只是设置页里挑选工具的分类，不再决定曝光边界。真正的曝光边界是
/// 快捷按钮上的 `toolNames`。
enum AgentToolGroup: String, CaseIterable, Sendable {
    case core
    case exercises
    case workouts
    case meals
    case body
    case plans
    case gym
    case review
    case feedback

    var tools: [AgentToolName] {
        switch self {
        case .core:
            [.loadSkill]
        case .exercises:
            [
                .searchExercises,
                .createExercise,
                .updateExercise,
                .archiveExercise,
                .mergeExercises
            ]
        case .workouts:
            [.listWorkouts, .getWorkout, .createWorkout, .updateWorkout, .deleteWorkout]
        case .meals:
            [.listMeals, .getMeal, .createMeal, .updateMeal, .deleteMeal]
        case .body:
            [
                .listBodyEntries,
                .getBodyEntry,
                .createBodyEntry,
                .updateBody,
                .deleteBodyEntry
            ]
        case .plans:
            [
                .listPrograms,
                .getProgram,
                .createProgram,
                .updateProgram,
                .archiveProgram,
                .deleteProgram,
                .startProgram
            ]
        case .gym:
            [.updateGym, .switchGym]
        case .review:
            [.recordPerformanceAnalysis]
        case .feedback:
            [.submitFeedback]
        }
    }

    var title: String {
        switch self {
        case .core: "基础"
        case .exercises: "动作库"
        case .workouts: "训练记录"
        case .meals: "饮食记录"
        case .body: "体重与体态"
        case .plans: "训练计划与带练"
        case .gym: "健身房"
        case .review: "动作复盘"
        case .feedback: "产品反馈"
        }
    }
}

/// ADR 0082：默认全量曝光；选中快捷按钮时只曝光该按钮勾选的工具。
enum AgentToolExposurePolicy {
    /// 工具目录顺序，作为所有曝光结果的稳定排序。
    static let orderedTools: [AgentToolName] = {
        var seen = Set<AgentToolName>()
        var ordered: [AgentToolName] = []
        for group in AgentToolGroup.allCases {
            for tool in group.tools where seen.insert(tool).inserted {
                ordered.append(tool)
            }
        }
        for tool in AgentToolName.allCases where seen.insert(tool).inserted {
            ordered.append(tool)
        }
        return ordered
    }()

    static func tools(selectedShortcut: AgentInputShortcut?) -> [AgentToolName] {
        guard let selectedShortcut else { return orderedTools }
        let selected = Set(selectedShortcut.toolNames)
        guard !selected.isEmpty else { return orderedTools }
        return orderedTools.filter { selected.contains($0.rawValue) }
    }

    static func tools(names: [String]) -> [AgentToolName] {
        guard !names.isEmpty else { return orderedTools }
        let selected = Set(names)
        return orderedTools.filter { selected.contains($0.rawValue) }
    }

    static func normalize(toolNames: [String]) -> [String] {
        tools(names: toolNames).map(\.rawValue)
    }

    static func toolNames(for groups: Set<AgentToolGroup>) -> [String] {
        orderedTools
            .filter { tool in
                groups.contains { $0.tools.contains(tool) }
            }
            .map(\.rawValue)
    }
}

extension AgentToolName {
    /// 全量工具名，作为快捷按钮的默认勾选集合。
    static var allToolNames: [String] {
        AgentToolExposurePolicy.orderedTools.map(\.rawValue)
    }
}
