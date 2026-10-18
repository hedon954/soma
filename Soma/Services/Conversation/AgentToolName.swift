import Foundation

enum AgentToolName: String, Codable, CaseIterable, Equatable, Sendable {
    case searchExercises = "search_exercises"
    case createExercise = "create_exercise"
    case updateExercise = "update_exercise"
    case archiveExercise = "archive_exercise"
    case mergeExercises = "merge_exercises"
    case listWorkouts = "list_workouts"
    case getWorkout = "get_workout"
    case createWorkout = "create_workout"
    case deleteWorkout = "delete_workout"
    case listMeals = "list_meals"
    case getMeal = "get_meal"
    case createMeal = "create_meal"
    case deleteMeal = "delete_meal"
    case listBodyEntries = "list_body_entries"
    case getBodyEntry = "get_body_entry"
    case createBodyEntry = "create_body_entry"
    case deleteBodyEntry = "delete_body_entry"
    case listPrograms = "list_programs"
    case getProgram = "get_program"
    case createProgram = "create_program"
    case updateProgram = "update_program"
    case archiveProgram = "archive_program"
    case deleteProgram = "delete_program"
    case startProgram = "start_program"
    case proposeTrainingSchedule = "propose_training_schedule"
    case loadSkill = "load_skill"
    case askUserQuestions = "ask_user_questions"
    case updateWorkout = "update_workout"
    case updateMeal = "update_meal"
    case updateBody = "update_body"
    case updateGym = "update_gym"
    case switchGym = "switch_gym"
    case recordPerformanceAnalysis = "record_performance_analysis"
    case submitFeedback = "submit_feedback"

    var isTypedTool: Bool {
        switch self {
        case .searchExercises, .createExercise, .updateExercise,
             .archiveExercise, .mergeExercises, .listWorkouts,
             .getWorkout, .createWorkout, .deleteWorkout, .listMeals,
             .updateWorkout, .getMeal, .createMeal, .updateMeal, .deleteMeal, .listBodyEntries,
             .getBodyEntry, .createBodyEntry, .deleteBodyEntry,
             .updateBody,
             .listPrograms, .getProgram, .createProgram,
             .updateProgram, .archiveProgram, .deleteProgram,
             .startProgram:
            true
        default:
            false
        }
    }

    var isMutation: Bool {
        switch self {
        case .searchExercises,
             .listWorkouts,
             .getWorkout,
             .listMeals,
             .getMeal,
             .listBodyEntries,
             .getBodyEntry,
             .listPrograms,
             .getProgram,
             .loadSkill, .askUserQuestions, .proposeTrainingSchedule:
            false
        default:
            true
        }
    }

    var schemaVersion: Int {
        switch self {
        case .askUserQuestions, .proposeTrainingSchedule: 1
        case .searchExercises,
             .createExercise,
             .updateExercise,
             .createWorkout,
             .updateWorkout:
            4
        case .getProgram,
             .createProgram,
             .updateProgram:
            3
        case .archiveExercise,
             .mergeExercises,
             .listWorkouts,
             .getWorkout,
             .deleteWorkout,
             .listMeals,
             .getMeal,
             .createMeal,
             .deleteMeal,
             .listBodyEntries,
             .getBodyEntry,
             .createBodyEntry,
             .deleteBodyEntry,
             .listPrograms,
             .archiveProgram,
             .deleteProgram,
             .startProgram,
             .loadSkill,
             .updateMeal,
             .updateBody,
             .updateGym,
             .switchGym,
             .recordPerformanceAnalysis,
             .submitFeedback:
            2
        }
    }

    /// 新调用只广告当前版本；升级前持久化的远程 Job 仍可按原版本交回设备执行。
    var supportedSchemaVersions: Set<Int> {
        switch self {
        case .createExercise, .createWorkout:
            [1, 2, 3, 4]
        case .searchExercises, .updateExercise, .updateWorkout:
            [1, 2, 4]
        case .getProgram, .createProgram, .updateProgram:
            [1, 2, 3]
        default:
            [1, schemaVersion]
        }
    }

    var displayTitle: String {
        switch self {
        case .searchExercises: "搜索动作"
        case .createExercise: "创建动作"
        case .updateExercise: "更新动作"
        case .archiveExercise: "归档动作"
        case .mergeExercises: "合并动作"
        case .listWorkouts: "读取训练列表"
        case .getWorkout: "读取训练详情"
        case .createWorkout: "创建训练记录"
        case .deleteWorkout: "删除训练记录"
        case .listMeals: "读取饮食列表"
        case .getMeal: "读取饮食详情"
        case .createMeal: "创建饮食记录"
        case .deleteMeal: "删除饮食记录"
        case .listBodyEntries: "读取身体记录列表"
        case .getBodyEntry: "读取身体记录详情"
        case .createBodyEntry: "创建身体记录"
        case .deleteBodyEntry: "删除身体记录"
        case .listPrograms: "读取课程列表"
        case .getProgram: "读取课程详情"
        case .createProgram: "创建训练课程"
        case .updateProgram: "更新训练课程"
        case .archiveProgram: "归档训练课程"
        case .deleteProgram: "删除训练课程"
        case .startProgram: "开始课程带练"
        case .loadSkill: "加载 Skill"
        case .askUserQuestions: "等待你的回答"
        case .proposeTrainingSchedule: "起草训练计划"
        case .updateWorkout: "更新训练"
        case .updateMeal: "更新饮食"
        case .updateBody: "更新身体信息"
        case .updateGym: "更新健身房"
        case .switchGym: "切换健身房"
        case .recordPerformanceAnalysis: "保存视频复盘"
        case .submitFeedback: "提交产品反馈"
        }
    }
}
