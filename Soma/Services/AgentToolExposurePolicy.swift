import Foundation

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
                .createProgramVersion,
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
}

enum AgentToolExposurePolicy {
    static let currentProtocolGroups = Set(AgentToolGroup.allCases)

    static func groups(selectedSkill: AgentSkillDescriptor?) -> Set<AgentToolGroup> {
        selectedSkill?.toolGroups ?? currentProtocolGroups
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
}
