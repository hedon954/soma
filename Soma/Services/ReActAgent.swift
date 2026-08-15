import Foundation
import SwiftOpenAI

enum AgentToolName: String, Codable, CaseIterable, Equatable, Sendable {
    // v3 单一职责工具；旧工具保留解码兼容，但不再进入默认暴露集合。
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
    case createProgramVersion = "create_program_version"
    case archiveProgram = "archive_program"
    case deleteProgram = "delete_program"
    case startProgram = "start_program"
    case loadSkill = "load_skill"
    case queryUserData = "query_user_data"
    case mutateUserData = "mutate_user_data"
    case listExerciseNames = "list_exercise_names"
    case listTrainingPrograms = "list_training_programs"
    case getTrainingProgram = "get_training_program"
    case recordWorkout = "record_workout"
    case recordMeal = "record_meal"
    case recordBody = "record_body"
    case updateWorkout = "update_workout"
    case updateMeal = "update_meal"
    case updateBody = "update_body"
    case deleteRecord = "delete_record"
    case updateGym = "update_gym"
    case switchGym = "switch_gym"
    case createTrainingProgram = "create_training_program"
    case createWorkoutTemplateVersion = "create_workout_template_version"
    case updateWorkoutTemplate = "update_workout_template"
    case archiveTrainingProgram = "archive_training_program"
    case deleteTrainingProgram = "delete_training_program"
    case startGuidedWorkout = "start_guided_workout"
    case recordPerformanceAnalysis = "record_performance_analysis"
    case submitFeedback = "submit_feedback"
    case expandToolGroup = "expand_tool_group"

    var isTypedV3: Bool {
        switch self {
        case .searchExercises, .createExercise, .updateExercise,
             .archiveExercise, .mergeExercises, .listWorkouts,
             .getWorkout, .createWorkout, .deleteWorkout, .listMeals,
             .updateWorkout, .getMeal, .createMeal, .updateMeal, .deleteMeal, .listBodyEntries,
             .getBodyEntry, .createBodyEntry, .deleteBodyEntry,
             .updateBody,
             .listPrograms, .getProgram, .createProgram,
             .createProgramVersion, .archiveProgram, .deleteProgram,
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
             .loadSkill,
             .queryUserData,
             .listExerciseNames,
             .listTrainingPrograms,
             .getTrainingProgram,
             .expandToolGroup:
            false
        default:
            true
        }
    }

    var schemaVersion: Int {
        switch self {
        case .searchExercises,
             .createExercise,
             .updateExercise,
             .archiveExercise,
             .mergeExercises,
             .listWorkouts,
             .getWorkout,
             .createWorkout,
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
             .getProgram,
             .createProgram,
             .createProgramVersion,
             .archiveProgram,
             .deleteProgram,
             .startProgram,
             .loadSkill,
             .queryUserData,
             .mutateUserData,
             .expandToolGroup,
             .createTrainingProgram,
             .createWorkoutTemplateVersion,
             .archiveTrainingProgram,
             .deleteTrainingProgram,
             .startGuidedWorkout,
             .updateWorkout,
             .updateMeal,
             .updateBody,
             .updateGym,
             .switchGym,
             .recordPerformanceAnalysis,
             .submitFeedback:
            2
        default:
            1
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
        case .listPrograms: "读取计划列表"
        case .getProgram: "读取计划详情"
        case .createProgram: "创建训练计划"
        case .createProgramVersion: "创建计划版本"
        case .archiveProgram: "归档训练计划"
        case .deleteProgram: "删除训练计划"
        case .startProgram: "开始计划带练"
        case .loadSkill: "加载 Skill"
        case .queryUserData: "读取用户数据"
        case .mutateUserData: "修改用户数据"
        case .listExerciseNames: "读取动作库"
        case .listTrainingPrograms: "读取训练计划"
        case .getTrainingProgram: "读取计划详情"
        case .recordWorkout: "记录训练"
        case .recordMeal: "记录饮食"
        case .recordBody: "记录身体信息"
        case .updateWorkout: "更新训练"
        case .updateMeal: "更新饮食"
        case .updateBody: "更新身体信息"
        case .deleteRecord: "删除记录"
        case .updateGym: "更新健身房"
        case .switchGym: "切换健身房"
        case .createTrainingProgram: "创建训练计划"
        case .createWorkoutTemplateVersion: "创建计划版本"
        case .updateWorkoutTemplate: "更新训练模板"
        case .archiveTrainingProgram: "归档训练计划"
        case .deleteTrainingProgram: "永久删除训练计划"
        case .startGuidedWorkout: "开始计划带练"
        case .recordPerformanceAnalysis: "保存视频复盘"
        case .submitFeedback: "提交产品反馈"
        case .expandToolGroup: "展开工具组"
        }
    }
}

struct AgentEquipmentInput: Codable, Equatable {
    var name: String
    var category: String
    var capabilities: String
    var confidence: Double?
}

struct AgentWorkoutSetInput: Codable, Equatable {
    var reps: Int?
    var externalWeightKG: Double?

    enum CodingKeys: String, CodingKey {
        case reps
        case externalWeightKG = "external_weight_kg"
    }
}

struct AgentMealItemInput: Codable, Equatable {
    var id: String? = nil
    var name: String
    var portionDescription: String? = nil
    var calories: Int? = nil
    var protein: Double? = nil
    var carbs: Double? = nil
    var fat: Double? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, calories, protein, carbs, fat
        case portionDescription = "portion_description"
    }

    var model: MealItem {
        MealItem(
            id: id.flatMap(UUID.init(uuidString:)) ?? UUID(),
            name: name,
            portionDescription: portionDescription,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat
        )
    }
}

struct AgentMutationPayload: Codable, Equatable {
    var exerciseID: Int64? = nil
    var exerciseName: String? = nil
    var setEntries: [AgentWorkoutSetInput]? = nil
    var restSeconds: Int? = nil
    var durationMinutes: Int? = nil
    var formScore: Int? = nil
    var intensity: String? = nil
    var feedback: String? = nil
    var mealType: String? = nil
    var title: String? = nil
    var calories: Int? = nil
    var protein: Double? = nil
    var carbs: Double? = nil
    var fat: Double? = nil
    var items: [AgentMealItemInput]? = nil
    var note: String? = nil
    var weight: Double? = nil
    var bodyFat: Double? = nil
    var waist: Double? = nil
    var postureNote: String? = nil
    var safetyNote: String? = nil

    enum CodingKeys: String, CodingKey {
        case intensity, feedback, title, calories, protein, carbs, fat, items, note, weight, waist
        case exerciseID = "exercise_id"
        case exerciseName = "exercise_name"
        case setEntries = "set_entries"
        case restSeconds = "rest_seconds"
        case durationMinutes = "duration_minutes"
        case formScore = "form_score"
        case mealType = "meal_type"
        case bodyFat = "body_fat"
        case postureNote = "posture_note"
        case safetyNote = "safety_note"
    }
}

extension AgentMutationPayload {
    func toolArguments(recordID: Int64?, recordType: String?) -> AgentToolArguments {
        AgentToolArguments(
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            setEntries: setEntries,
            weight: weight,
            restSeconds: restSeconds,
            durationMinutes: durationMinutes,
            formScore: formScore,
            intensity: intensity,
            feedback: feedback,
            mealType: mealType,
            title: title,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            note: note,
            items: items,
            bodyFat: bodyFat,
            waist: waist,
            postureNote: postureNote,
            safetyNote: safetyNote,
            recordID: recordID,
            recordType: recordType
        )
    }
}

struct AgentTemplateExerciseInput: Codable, Equatable {
    var exerciseID: Int64
    var order: Int
    var targetSets: Int? = nil
    var targetReps: Int? = nil
    var targetWeightKG: Double? = nil
    var targetRestSeconds: Int? = nil
    var firstSetIsWarmup: Bool? = nil
    var equipmentKind: String? = nil
    var notes: String? = nil

    enum CodingKeys: String, CodingKey {
        case order, notes
        case exerciseID = "exercise_id"
        case targetSets = "target_sets"
        case targetReps = "target_reps"
        case targetWeightKG = "target_weight_kg"
        case targetRestSeconds = "target_rest_seconds"
        case firstSetIsWarmup = "first_set_is_warmup"
        case equipmentKind = "equipment_kind"
    }
}

struct AgentToolArguments: Codable, Equatable {
    var skillID: String?
    var scope: String?
    var query: String?
    var sort: String?
    var limit: Int?
    var cursor: String?
    var projection: String?
    var fields: [String]?
    var dateFrom: String?
    var dateTo: String?
    var groupBy: String?
    var metric: String?
    var toolGroup: String?
    var operation: String?
    var payload: AgentMutationPayload?
    var occurredAt: String?

    var gymName: String?
    var summary: String?
    var equipment: [AgentEquipmentInput]?
    var mediaSource: String?

    var exercise: String?
    var exerciseID: Int64?
    var targetExerciseID: Int64?
    var exerciseName: String?
    var setEntries: [AgentWorkoutSetInput]?
    var sets: Int?
    var reps: Int?
    var weight: Double?
    var restSeconds: Int?
    var durationMinutes: Int?
    var formScore: Int?
    var intensity: String?
    var feedback: String?

    var mealType: String?
    var title: String?
    var calories: Int?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var note: String?
    var items: [AgentMealItemInput]?

    var bodyFat: Double?
    var waist: Double?
    var postureNote: String?
    var safetyNote: String?
    var recordID: Int64?
    var recordType: String?
    var programID: Int64?
    var sessionID: Int64?
    var performanceID: Int64?
    var inputFingerprint: String?
    var evidence: String?
    var limitations: String?
    var programName: String?
    var goal: String?
    var templateName: String?
    var scheduleHint: String?
    var templateExercises: [AgentTemplateExerciseInput]?
    var autoRecordingPolicy: String?

    enum CodingKeys: String, CodingKey {
        case scope, query, sort, limit, cursor, projection, fields, summary, equipment
        case exercise, sets, reps, weight, intensity, feedback, title, calories, protein
        case carbs, fat, note, items, waist, metric, operation, payload
        case occurredAt = "occurred_at"
        case setEntries = "set_entries"
        case skillID = "skill_id"
        case dateFrom = "date_from"
        case dateTo = "date_to"
        case groupBy = "group_by"
        case toolGroup = "tool_group"
        case gymName = "gym_name"
        case mediaSource = "media_source"
        case exerciseID = "exercise_id"
        case targetExerciseID = "target_exercise_id"
        case exerciseName = "exercise_name"
        case restSeconds = "rest_seconds"
        case durationMinutes = "duration_minutes"
        case formScore = "form_score"
        case mealType = "meal_type"
        case bodyFat = "body_fat"
        case postureNote = "posture_note"
        case safetyNote = "safety_note"
        case recordID = "record_id"
        case recordType = "record_type"
        case programID = "program_id"
        case sessionID = "session_id"
        case performanceID = "performance_id"
        case inputFingerprint = "input_fingerprint"
        case evidence, limitations
        case programName = "program_name"
        case goal
        case templateName = "template_name"
        case scheduleHint = "schedule_hint"
        case templateExercises = "template_exercises"
        case autoRecordingPolicy = "auto_recording_policy"
    }

    init(
        skillID: String? = nil,
        scope: String? = nil,
        query: String? = nil,
        sort: String? = nil,
        limit: Int? = nil,
        cursor: String? = nil,
        projection: String? = nil,
        fields: [String]? = nil,
        dateFrom: String? = nil,
        dateTo: String? = nil,
        groupBy: String? = nil,
        metric: String? = nil,
        toolGroup: String? = nil,
        operation: String? = nil,
        payload: AgentMutationPayload? = nil,
        occurredAt: String? = nil,
        gymName: String? = nil,
        summary: String? = nil,
        equipment: [AgentEquipmentInput]? = nil,
        mediaSource: String? = nil,
        exercise: String? = nil,
        exerciseID: Int64? = nil,
        targetExerciseID: Int64? = nil,
        exerciseName: String? = nil,
        setEntries: [AgentWorkoutSetInput]? = nil,
        sets: Int? = nil,
        reps: Int? = nil,
        weight: Double? = nil,
        restSeconds: Int? = nil,
        durationMinutes: Int? = nil,
        formScore: Int? = nil,
        intensity: String? = nil,
        feedback: String? = nil,
        mealType: String? = nil,
        title: String? = nil,
        calories: Int? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        note: String? = nil,
        items: [AgentMealItemInput]? = nil,
        bodyFat: Double? = nil,
        waist: Double? = nil,
        postureNote: String? = nil,
        safetyNote: String? = nil,
        recordID: Int64? = nil,
        recordType: String? = nil,
        programID: Int64? = nil,
        sessionID: Int64? = nil,
        performanceID: Int64? = nil,
        inputFingerprint: String? = nil,
        evidence: String? = nil,
        limitations: String? = nil,
        programName: String? = nil,
        goal: String? = nil,
        templateName: String? = nil,
        scheduleHint: String? = nil,
        templateExercises: [AgentTemplateExerciseInput]? = nil,
        autoRecordingPolicy: String? = nil
    ) {
        self.skillID = skillID
        self.scope = scope
        self.query = query
        self.sort = sort
        self.limit = limit
        self.cursor = cursor
        self.projection = projection
        self.fields = fields
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.groupBy = groupBy
        self.metric = metric
        self.toolGroup = toolGroup
        self.operation = operation
        self.payload = payload
        self.occurredAt = occurredAt
        self.gymName = gymName
        self.summary = summary
        self.equipment = equipment
        self.mediaSource = mediaSource
        self.exercise = exercise
        self.exerciseID = exerciseID
        self.targetExerciseID = targetExerciseID
        self.exerciseName = exerciseName
        self.setEntries = setEntries
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.restSeconds = restSeconds
        self.durationMinutes = durationMinutes
        self.formScore = formScore
        self.intensity = intensity
        self.feedback = feedback
        self.mealType = mealType
        self.title = title
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.note = note
        self.items = items
        self.bodyFat = bodyFat
        self.waist = waist
        self.postureNote = postureNote
        self.safetyNote = safetyNote
        self.recordID = recordID
        self.recordType = recordType
        self.programID = programID
        self.sessionID = sessionID
        self.performanceID = performanceID
        self.inputFingerprint = inputFingerprint
        self.evidence = evidence
        self.limitations = limitations
        self.programName = programName
        self.goal = goal
        self.templateName = templateName
        self.scheduleHint = scheduleHint
        self.templateExercises = templateExercises
        self.autoRecordingPolicy = autoRecordingPolicy
    }
}

struct AgentToolCall: Codable, Equatable {
    var name: AgentToolName
    var arguments: AgentToolArguments

    /// ADR 0049：规范化语义键，避免字面 JSON 差异（同义字段、缺省与 null）绕过幂等。
    var signature: String {
        AgentToolCallSignature.canonical(name: name, arguments: arguments)
    }
}

enum AgentToolCallSignature {
    static func canonical(name: AgentToolName, arguments: AgentToolArguments) -> String {
        var object: [String: Any] = ["name": name.rawValue]
        var args: [String: Any] = [:]
        func put(_ key: String, _ value: String?) {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                args[key] = trimmed
            }
        }
        func put(_ key: String, _ value: Int?) {
            if let value {
                args[key] = value
            }
        }
        func put(_ key: String, _ value: Int64?) {
            if let value {
                args[key] = value
            }
        }
        func put(_ key: String, _ value: Double?) {
            if let value {
                args[key] = (value * 1000).rounded() / 1000
            }
        }

        put("skill_id", arguments.skillID)
        put("scope", arguments.scope)
        put("query", arguments.query)
        put("sort", arguments.sort)
        put("limit", arguments.limit)
        put("cursor", arguments.cursor)
        put("projection", arguments.projection)
        put("date_from", arguments.dateFrom)
        put("date_to", arguments.dateTo)
        put("group_by", arguments.groupBy)
        put("metric", arguments.metric)
        put("tool_group", arguments.toolGroup)
        put("operation", arguments.operation)
        put("occurred_at", arguments.occurredAt)
        put("gym_name", arguments.gymName)
        put("summary", arguments.summary)
        put("media_source", arguments.mediaSource)
        // exercise / exercise_name 同义，统一到 exercise_name。
        let exerciseName = nonempty(arguments.exerciseName) ?? nonempty(arguments.exercise)
        put("exercise_name", exerciseName)
        put("exercise_id", arguments.exerciseID)
        put("target_exercise_id", arguments.targetExerciseID)
        put("sets", arguments.sets)
        put("reps", arguments.reps)
        put("weight", arguments.weight)
        put("rest_seconds", arguments.restSeconds)
        put("duration_minutes", arguments.durationMinutes)
        put("form_score", arguments.formScore)
        put("intensity", arguments.intensity)
        put("feedback", arguments.feedback)
        put("meal_type", arguments.mealType)
        put("title", arguments.title)
        put("calories", arguments.calories)
        put("protein", arguments.protein)
        put("carbs", arguments.carbs)
        put("fat", arguments.fat)
        put("note", arguments.note)
        put("body_fat", arguments.bodyFat)
        put("waist", arguments.waist)
        put("posture_note", arguments.postureNote)
        put("safety_note", arguments.safetyNote)
        put("record_id", arguments.recordID)
        put("record_type", arguments.recordType)
        put("program_id", arguments.programID)
        put("session_id", arguments.sessionID)
        put("performance_id", arguments.performanceID)
        put("input_fingerprint", arguments.inputFingerprint)
        put("evidence", arguments.evidence)
        put("limitations", arguments.limitations)
        put("program_name", arguments.programName)
        put("goal", arguments.goal)
        put("template_name", arguments.templateName)
        put("schedule_hint", arguments.scheduleHint)
        put("auto_recording_policy", arguments.autoRecordingPolicy)

        if let fields = arguments.fields, !fields.isEmpty {
            args["fields"] = fields.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        }
        if let payload = arguments.payload,
           let data = try? JSONEncoder().encode(payload),
           let value = try? JSONSerialization.jsonObject(with: data)
        {
            args["payload"] = value
        }

        if let setEntries = arguments.setEntries, !setEntries.isEmpty {
            // 逐组顺序是事实（ADR 0023），不得排序打散。
            args["set_entries"] = setEntries.map { entry -> [String: Any] in
                var item: [String: Any] = [:]
                if let reps = entry.reps {
                    item["reps"] = reps
                }
                if let weight = entry.externalWeightKG {
                    item["external_weight_kg"] = (weight * 1000).rounded() / 1000
                }
                return item
            }
        }
        if let equipment = arguments.equipment, !equipment.isEmpty {
            args["equipment"] = equipment
                .map { item -> [String: Any] in
                    var row: [String: Any] = [
                        "name": item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        "category": item.category.trimmingCharacters(in: .whitespacesAndNewlines),
                        "capabilities": item.capabilities
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    ]
                    if let confidence = item.confidence {
                        row["confidence"] = (confidence * 1000).rounded() / 1000
                    }
                    return row
                }
                .sorted {
                    ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "")
                }
        }
        if let exercises = arguments.templateExercises, !exercises.isEmpty {
            args["template_exercises"] = exercises
                .sorted { $0.order < $1.order }
                .map { item -> [String: Any] in
                    var row: [String: Any] = [
                        "exercise_id": item.exerciseID,
                        "order": item.order
                    ]
                    if let value = item.targetSets {
                        row["target_sets"] = value
                    }
                    if let value = item.targetReps {
                        row["target_reps"] = value
                    }
                    if let value = item.targetWeightKG {
                        row["target_weight_kg"] = (value * 1000).rounded() / 1000
                    }
                    if let value = item.targetRestSeconds {
                        row["target_rest_seconds"] = value
                    }
                    if let value = item.firstSetIsWarmup {
                        row["first_set_is_warmup"] = value
                    }
                    if let value = nonempty(item.equipmentKind) {
                        row["equipment_kind"] = value
                    }
                    if let value = nonempty(item.notes) {
                        row["notes"] = value
                    }
                    return row
                }
        }
        if !args.isEmpty {
            object["arguments"] = args
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys]
              ),
              let text = String(data: data, encoding: .utf8)
        else {
            return name.rawValue
        }
        return text
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AgentObservation: Codable, Equatable {
    var step: Int
    var action: AgentToolCall
    var result: AgentToolResult
}

struct AgentOutcome: Equatable, @unchecked Sendable {
    var finalAnswer: String
    var observations: [AgentObservation]

    var primaryRecordType: ConversationIntent? {
        observations.compactMap(\.result.recordType).last
    }
}

/// ADR 0062：每个 LLM invoke / tool call 都是可恢复 step。
///
/// `toolBatches == nil` 代表旧版压缩检查点；新检查点保留原生 assistant.tool_calls
/// 与 role=tool 结果，恢复时不重新调用已经成功的模型或工具。
struct AgentLoopCheckpoint: Codable, Equatable, Sendable {
    var lastCompletedStep: Int
    var assistantPassages: [String]
    var observations: [AgentCheckpointObservation]
    var exposedGroups: [String]
    var nextModelStep: Int?
    var toolBatches: [AgentCheckpointToolBatch]?

    init(
        lastCompletedStep: Int,
        assistantPassages: [String],
        observations: [AgentCheckpointObservation],
        exposedGroups: [String],
        nextModelStep: Int? = nil,
        toolBatches: [AgentCheckpointToolBatch]? = nil
    ) {
        self.lastCompletedStep = lastCompletedStep
        self.assistantPassages = assistantPassages
        self.observations = observations
        self.exposedGroups = exposedGroups
        self.nextModelStep = nextModelStep
        self.toolBatches = toolBatches
    }

    static let empty = AgentLoopCheckpoint(
        lastCompletedStep: 0,
        assistantPassages: [],
        observations: [],
        exposedGroups: []
    )
}

struct AgentCheckpointToolCall: Codable, Equatable, @unchecked Sendable {
    var id: String
    var argumentsJSON: String
    var action: AgentToolCall

    var native: ToolCall {
        ToolCall(
            id: id,
            function: FunctionCall(
                arguments: argumentsJSON,
                name: action.name.rawValue
            )
        )
    }
}

struct AgentCheckpointToolResult: Codable, Equatable, @unchecked Sendable {
    var step: Int
    var call: AgentCheckpointToolCall
    var result: AgentToolResult
}

struct AgentCheckpointToolBatch: Codable, Equatable, @unchecked Sendable {
    var modelStep: Int
    var modelOperationStep: Int
    var passage: String
    var calls: [AgentCheckpointToolCall]
    var completedResults: [AgentCheckpointToolResult]

    var isComplete: Bool {
        completedResults.count == calls.count
    }
}

struct AgentCheckpointObservation: Codable, Equatable, Sendable {
    var step: Int
    var toolName: String
    var signature: String
    var observation: String
    var ok: Bool
    var recordTypeRaw: String?

    var recordType: ConversationIntent? {
        recordTypeRaw.flatMap(ConversationIntent.init(rawValue:))
    }

    init(step: Int, action: AgentToolCall, result: AgentToolResult) {
        self.step = step
        toolName = action.name.rawValue
        signature = action.signature
        observation = result.observation
        ok = result.ok
        recordTypeRaw = result.recordType?.rawValue
    }
}

struct AgentConversationExchange: Sendable {
    var userText: String
    var assistantText: String?
    var images: [Data]
    var imageAttachmentCount: Int
    var videoAttachmentCount: Int

    var traceSummary: String {
        let user = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAssistant = assistantText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = if let trimmedAssistant, !trimmedAssistant.isEmpty {
            trimmedAssistant
        } else {
            "无"
        }
        return """
        [HISTORY USER]
        \(user.isEmpty ? "无文字" : user)
        原始附件：\(imageAttachmentCount) 张图片、\(videoAttachmentCount) 个视频；本次重新提供 \(images.count) 张图片或视频关键帧。
        [HISTORY ASSISTANT]
        \(assistant)
        """
    }
}

/// ReAct 循环步数上限：高级设置可改，默认 100。
enum ReActAgentPreference {
    static let maxStepsKey = "agent.react.maxSteps"
    static let defaultMaxSteps = 100
    static let minimumMaxSteps = 1
    static let maximumMaxSteps = 500

    static func maxSteps(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.object(forKey: maxStepsKey) as? Int
        let raw = stored ?? defaultMaxSteps
        return min(maximumMaxSteps, max(minimumMaxSteps, raw))
    }

    static func setMaxSteps(_ value: Int, defaults: UserDefaults = .standard) {
        defaults.set(
            min(maximumMaxSteps, max(minimumMaxSteps, value)),
            forKey: maxStepsKey
        )
    }
}

enum ReActAgentError: LocalizedError {
    case invalidToolCall(String)
    case emptyResponse
    case stepLimit(maxSteps: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidToolCall(message):
            "模型发出了无效工具调用：\(message)"
        case .emptyResponse:
            "模型没有返回文字或工具调用，请重试或切换模型"
        case let .stepLimit(maxSteps):
            "Agent 在 \(maxSteps) 步内没有完成任务，请简化描述后重试，或在高级设置中提高步骤上限"
        }
    }
}

struct AgentStreamingToolCall {
    var id = ""
    var name = ""
    var arguments = ""

    mutating func append(_ delta: ToolCall) {
        if let id = delta.id, !id.isEmpty {
            self.id = id
        }
        if let name = delta.function.name, !name.isEmpty {
            self.name += name
        }
        arguments += delta.function.arguments
    }

    func resolved(fallbackID: String) throws -> (native: ToolCall, local: AgentToolCall) {
        guard let name = AgentToolName(rawValue: name) else {
            throw ReActAgentError.invalidToolCall("未知工具 \(name.isEmpty ? "（空名称）" : name)")
        }
        let argumentData = arguments.isEmpty ? Data("{}".utf8) : Data(arguments.utf8)
        try AgentToolSchemaValidator.validateTopLevelKeys(
            argumentData,
            for: name
        )
        let decoded: AgentToolArguments
        do {
            decoded = try JSONDecoder().decode(AgentToolArguments.self, from: argumentData)
        } catch {
            throw ReActAgentError.invalidToolCall("\(name.rawValue) 参数不是有效 JSON：\(error.localizedDescription)")
        }
        let callID = id.isEmpty ? fallbackID : id
        return (
            ToolCall(
                id: callID,
                function: FunctionCall(arguments: arguments.isEmpty ? "{}" : arguments, name: name.rawValue)
            ),
            AgentToolCall(name: name, arguments: decoded)
        )
    }
}

private enum AgentToolSchemaValidator {
    static func validateTopLevelKeys(
        _ argumentData: Data,
        for name: AgentToolName
    ) throws {
        guard let raw = try JSONSerialization.jsonObject(with: argumentData)
            as? [String: Any]
        else {
            throw ReActAgentError.invalidToolCall("\(name.rawValue) 参数必须是 JSON object。")
        }
        let encoded = try JSONEncoder().encode(name.chatTool)
        guard let tool = try JSONSerialization.jsonObject(with: encoded)
            as? [String: Any],
            let function = tool["function"] as? [String: Any],
            let parameters = function["parameters"] as? [String: Any],
            let properties = parameters["properties"] as? [String: Any]
        else {
            throw ReActAgentError.invalidToolCall("\(name.rawValue) 本地 Schema 无法读取。")
        }
        let unknown = Set(raw.keys).subtracting(properties.keys)
        guard unknown.isEmpty else {
            throw ReActAgentError.invalidToolCall(
                "\(name.rawValue) 包含未声明参数：\(unknown.sorted().joined(separator: "、"))。"
            )
        }
    }
}

extension AgentToolName {
    var chatTool: ChatCompletionParameters.Tool {
        ChatCompletionParameters.Tool(function: .init(
            name: rawValue,
            strict: true,
            description: toolDescription,
            parameters: toolParameters
        ))
    }

    private var toolDescription: String {
        switch self {
        case .searchExercises:
            "按名称搜索未归档动作，返回 Int64 exercise_id；记录训练或计划前使用，已注入的动作无需重复搜索。"
        case .createExercise:
            "仅在动作库没有语义等价项时创建标准动作，返回新的 Int64 exercise_id。"
        case .updateExercise:
            "按 Int64 exercise_id 修正动作标准名称。"
        case .archiveExercise:
            "按 Int64 exercise_id 归档动作；已有训练和计划关系保留。"
        case .mergeExercises:
            "把重复动作合并到目标动作，并重绑已有训练与计划关系。"
        case .listWorkouts:
            "按可选日期范围读取训练摘要；已预加载的当日记录无需重复读取。"
        case .getWorkout:
            "按 Int64 record_id 读取一条训练详情。"
        case .createWorkout:
            "创建一条绑定有效 Int64 exercise_id 的训练记录；occurred_at 省略时使用 Job 的稳定默认时间。"
        case .deleteWorkout:
            "删除指定 Int64 训练记录；仅在当前用户消息明确授权删除时使用。"
        case .listMeals:
            "按可选日期范围读取饮食摘要；已预加载的当日记录无需重复读取。"
        case .getMeal:
            "按 Int64 record_id 读取一条饮食详情。"
        case .createMeal:
            "创建饮食记录；未知营养字段省略，occurred_at 省略时使用 Job 的稳定默认时间。"
        case .deleteMeal:
            "删除指定 Int64 饮食记录；仅在当前用户消息明确授权删除时使用。"
        case .listBodyEntries:
            "按可选日期范围读取体重与体态摘要；已预加载的近期记录无需重复读取。"
        case .getBodyEntry:
            "按 Int64 record_id 读取一条身体记录详情。"
        case .createBodyEntry:
            "创建体重或体态记录；不得从外观猜数值，occurred_at 省略时使用 Job 的稳定默认时间。"
        case .deleteBodyEntry:
            "删除指定 Int64 身体记录；仅在当前用户消息明确授权删除时使用。"
        case .listPrograms:
            "读取可执行训练计划摘要。"
        case .getProgram:
            "按 Int64 program_id 读取计划当前版本和动作处方。"
        case .createProgram:
            "创建训练计划和首个不可变版本；每个动作必须使用有效 Int64 exercise_id。"
        case .createProgramVersion:
            "为已有计划创建新的不可变版本，不改写历史版本和已开始 Session。"
        case .archiveProgram:
            "归档训练计划，保留模板版本和训练历史。"
        case .deleteProgram:
            "永久删除训练计划；仅在当前用户消息明确授权时使用，训练历史保留。"
        case .startProgram:
            "按 Int64 program_id 创建不可变训练 Session 并开始带练。"
        case .loadSkill:
            "按需加载一项专业健身 Skill 的完整 Markdown 指令。可用 Skill：\(AgentSkill.catalogForToolDescription)。"
        case .queryUserData:
            "按范围、ID、日期、搜索、投影、字段和分页精确读取本机数据。detail 必须提供精确 ID；动作库必须提供 query。不得猜测未返回的数据。"
        case .mutateUserData:
            "统一新增、更新或删除训练、饮食、身体记录。更新必须使用 query_user_data 返回的稳定 record_id；删除还要求当前用户消息明确授权。未知字段保持省略。"
        case .listExerciseNames:
            "返回当前数据空间动作库中全部未归档动作的稳定 ID 和标准名称。记录训练前先调用，由模型完成语义匹配；匹配已有动作时使用 exercise_id，没有语义等价项时使用标准 exercise_name 新建。"
        case .listTrainingPrograms:
            "返回当前数据空间可执行训练计划的稳定 ID、名称、目标和当前模板摘要。用户要求开始带练前必须先调用；随后把返回的 program_id 交给 start_guided_workout。"
        case .getTrainingProgram:
            "读取一个训练计划的当前模板、动作顺序和处方详情。修改计划前先调用，并使用 list_training_programs 返回的 program_id。"
        case .recordWorkout:
            "新增一条训练。先调用 list_exercise_names；匹配已有动作时只传 exercise_id，确实没有语义等价动作时只传标准 exercise_name。未知训练字段必须省略。"
        case .recordMeal:
            "新增一餐。热量和宏量营养估算必须在 note 中说明不确定性。补图、纠错或同一餐的新视角应先查询并使用 update_meal；本工具仍有本地合并安全网。"
        case .recordBody:
            "新增一条体重或体态记录。补充同一时段的多角度照片时先查询并使用 update_body；不得从外观猜测体重、体脂或腰围，本工具仍有本地合并安全网。"
        case .updateWorkout:
            "按 query_user_data 返回的 record_id 更新一条训练记录，并把本次新媒体合并到原记录。修改动作身份时使用 list_exercise_names 返回的 exercise_id。"
        case .updateMeal:
            "按 query_user_data 返回的 record_id 更新一条饮食记录，并把本次新媒体合并到原记录。用户纠正食材、餐名或营养估算时优先使用。"
        case .updateBody:
            "按 query_user_data 返回的 record_id 更新一条身体记录，并把本次新媒体合并到原记录。不得补写没有证据的指标。"
        case .deleteRecord:
            "删除一条训练、饮食或身体记录。只有用户在当前消息明确要求删除时才能调用；先查询并使用准确 record_id。聊天原文和共享媒体不会删除。"
        case .updateGym:
            """
            新建或更新电子健身房及其可见器械，并把本次用于识别的照片保存到健身房档案。\
            未指定 gym_name 时更新当前健身房。若历史消息明确标记可引用紧邻上一轮的健身房\
            图片，必须传 media_source=recent_gym_turn；不得引用更早或无关媒体。
            """
        case .switchGym:
            "把一个已经存在或明确命名的健身房设为当前健身房。"
        case .createTrainingProgram:
            "创建训练计划及首个不可变模板版本。动作必须使用 query_user_data(scope=exercises) 返回的 exercise_id；缺失处方字段保持省略。"
        case .createWorkoutTemplateVersion:
            "为已有训练计划创建新的不可变模板版本。任何动作、顺序或处方修改都创建新版本，不改写旧版本。"
        case .updateWorkoutTemplate:
            "更新训练模板；实现为给已有计划创建一个新版本，不修改已开始训练的快照。"
        case .archiveTrainingProgram:
            "归档已有训练计划；保留模板版本和历史训练。"
        case .deleteTrainingProgram:
            "永久删除一个训练计划及其模板，已开始的训练 Session 快照和训练历史会保留。只有用户当前消息明确要求永久删除时才能调用；先查询并使用准确 program_id。"
        case .startGuidedWorkout:
            "按 query_user_data(scope=programs) 返回的 program_id 在本机创建一次不可变训练 Session，并立即打开带练。只在用户当前消息明确要求开始、执行或带练该计划时调用；未提供录像偏好时保持关闭。"
        case .recordPerformanceAnalysis:
            "把用户主动请求的视频复盘保存到指定 Performance。只记录画面可见证据、明确局限和一般训练建议；不得诊断伤病或修改训练事实。"
        case .submitFeedback:
            "向 Soma 维护者提交产品反馈。只有当前用户消息明确要求提交产品反馈时才能调用；发送内容固定为当前消息原文和当前附件，不得用于动作评价、饮食建议、身体观察或一般教练反馈。"
        case .expandToolGroup:
            "旧 Checkpoint 兼容工具；新请求由 App 在首轮绑定最小工具集。"
        }
    }

    private var toolParameters: JSONSchema {
        switch self {
        case .searchExercises:
            object([
                "query": string("动作名称或同义搜索词"),
                "limit": integer("最多返回多少条，默认 10，最大 20")
            ], required: ["query"])
        case .createExercise:
            object([
                "exercise_name": string("简洁、明确、去重后的标准动作名称")
            ], required: ["exercise_name"])
        case .updateExercise:
            object([
                "exercise_id": integer("要更新的动作 Int64 ID"),
                "exercise_name": string("新的标准动作名称")
            ], required: ["exercise_id", "exercise_name"])
        case .archiveExercise:
            object([
                "exercise_id": integer("要归档的动作 Int64 ID")
            ], required: ["exercise_id"])
        case .mergeExercises:
            object([
                "exercise_id": integer("要合并并归档的来源动作 Int64 ID"),
                "target_exercise_id": integer("保留的目标动作 Int64 ID")
            ], required: ["exercise_id", "target_exercise_id"])
        case .listWorkouts, .listMeals, .listBodyEntries:
            object([
                "date_from": string("ISO8601 或 yyyy-MM-dd 起始日期（含）"),
                "date_to": string("ISO8601 或 yyyy-MM-dd 结束日期（含）"),
                "sort": string("排序", values: ["newest", "oldest"]),
                "limit": integer("最多返回多少条，默认 3，最大 10")
            ])
        case .getWorkout, .getMeal, .getBodyEntry:
            object([
                "record_id": integer("记录 Int64 ID")
            ], required: ["record_id"])
        case .deleteWorkout, .deleteMeal, .deleteBodyEntry:
            object([
                "record_id": integer("要删除的记录 Int64 ID")
            ], required: ["record_id"])
        case .loadSkill:
            object(
                ["skill_id": string(
                    "要加载的 Skill ID",
                    values: AgentSkillRegistry.allDescriptors().map(\.id)
                )],
                required: ["skill_id"]
            )
        case .queryUserData:
            object([
                "scope": string(
                    "查询范围",
                    values: [
                        "overview", "profile", "workouts", "meals", "body",
                        "gyms", "exercises", "exercise_history", "programs",
                        "templates", "sessions", "aggregate"
                    ]
                ),
                "record_id": integer("detail 查询指定记录时使用的 Int64 ID"),
                "exercise_id": integer("查询指定动作历史时使用的 Int64 ID"),
                "program_id": integer("查询指定计划模板时使用的 Int64 ID"),
                "session_id": integer("查询指定计划训练时使用的 Int64 ID"),
                "query": string("动作库或文本字段的必填搜索词"),
                "date_from": string("ISO8601 或 yyyy-MM-dd 起始日期（含）"),
                "date_to": string("ISO8601 或 yyyy-MM-dd 结束日期（含）"),
                "sort": string("排序", values: ["newest", "oldest", "name"]),
                "cursor": string("上一页返回的不透明分页 cursor"),
                "projection": string("返回粒度", values: ["summary", "detail"]),
                "fields": array(string("按 scope 允许返回的字段"), description: "字段投影"),
                "group_by": string(
                    "聚合分组",
                    values: ["day", "week", "muscle_group", "exercise"]
                ),
                "metric": string(
                    "聚合指标",
                    values: ["sets", "volume", "calories", "frequency"]
                ),
                "limit": integer("最多返回多少条，默认 3，最大 10")
            ], required: ["scope"])
        case .mutateUserData:
            object([
                "operation": string("操作", values: ["create", "update", "delete"]),
                "record_type": string("记录类型", values: ["workout", "meal", "body"]),
                "record_id": integer("update/delete 必填的稳定 Int64 ID"),
                "payload": mutationPayload()
            ], required: ["operation", "record_type"])
        case .expandToolGroup:
            object([
                "tool_group": string(
                    "要展开的工具组",
                    values: AgentToolGroup.expandableCases.map(\.rawValue)
                )
            ], required: ["tool_group"])
        case .listPrograms, .listTrainingPrograms:
            object([:])
        case .getProgram, .getTrainingProgram:
            object([
                "program_id": integer("训练计划 Int64 ID")
            ], required: ["program_id"])
        case .listExerciseNames:
            object([:])
        case .createWorkout:
            object([
                "exercise_id": integer("必须存在且未归档的动作 Int64 ID"),
                "occurred_at": string("可选带时区 ISO-8601 发生时间；省略时使用 Job 冻结的默认记录时间"),
                "set_entries": workoutSetEntries(
                    "按实际顺序保存每组事实；次数或重量未知时省略对应字段"
                ),
                "rest_seconds": integer("用户明确提供的组间休息秒数"),
                "duration_minutes": integer("用户明确提供的训练时长分钟数"),
                "form_score": integer("有充分视频证据时的动作评分"),
                "intensity": string("有证据的负荷判断"),
                "feedback": string("有证据的动作反馈")
            ], required: ["exercise_id"])
        case .recordWorkout:
            object([
                "exercise_id": integer("动作搜索返回的已有动作 Int64 ID"),
                "exercise_name": string("仅在没有语义等价动作时使用的新标准动作名称"),
                "occurred_at": string("可选 ISO-8601 发生时间；省略时使用当前 Job 冻结的默认记录时间"),
                "set_entries": workoutSetEntries(
                    "按实际顺序保存每组事实；次数或重量未知时省略对应字段"
                ),
                "rest_seconds": integer("用户明确提供的组间休息秒数"),
                "duration_minutes": integer("用户明确提供的训练时长分钟数"),
                "form_score": integer("有充分视频证据时的动作评分"),
                "intensity": string("有证据的负荷判断"),
                "feedback": string("有证据的动作反馈")
            ])
        case .createMeal, .recordMeal:
            object([
                "occurred_at": string("可选 ISO-8601 发生时间；省略时使用当前 Job 冻结的默认记录时间"),
                "meal_type": string("早餐、午餐、晚餐或加餐"),
                "title": string("食物或餐食名称"),
                "calories": integer("估算千卡"),
                "protein": number("蛋白质克数"),
                "carbs": number("碳水克数"),
                "fat": number("脂肪克数"),
                "items": mealItemArray(),
                "note": string("估算依据、不确定性或用户原始补充")
            ], required: ["title"])
        case .createBodyEntry, .recordBody:
            object([
                "occurred_at": string("可选 ISO-8601 发生时间；省略时使用当前 Job 冻结的默认记录时间"),
                "weight": number("明确读到或用户提供的体重 kg"),
                "body_fat": number("明确读到或用户提供的体脂率"),
                "waist": number("明确读到或用户提供的腰围 cm"),
                "posture_note": string("中性、非诊断的可见体态观察"),
                "safety_note": string("局限性与安全提醒")
            ])
        case .updateWorkout:
            object([
                "record_id": integer("训练记录 Int64 ID"),
                "occurred_at": string("仅在用户明确纠正时间时提供的 ISO-8601 发生时间"),
                "exercise_id": integer("修正后动作 Int64 ID"),
                "set_entries": workoutSetEntries(
                    "替换后的完整有序组；不修改组数据时省略"
                ),
                "rest_seconds": integer("修正后的组间休息秒数"),
                "duration_minutes": integer("修正后的训练时长分钟数"),
                "form_score": integer("有充分视频证据时的动作评分"),
                "intensity": string("有证据的负荷判断"),
                "feedback": string("有证据的动作反馈")
            ], required: ["record_id"])
        case .updateMeal:
            object([
                "record_id": integer("饮食记录 Int64 ID"),
                "occurred_at": string("仅在用户明确纠正时间时提供的 ISO-8601 发生时间"),
                "meal_type": string("早餐、午餐、晚餐或加餐"),
                "title": string("修正后的食物或餐食名称"),
                "calories": integer("修正后的估算千卡"),
                "protein": number("修正后的蛋白质克数"),
                "carbs": number("修正后的碳水克数"),
                "fat": number("修正后的脂肪克数"),
                "items": mealItemArray(),
                "note": string("修正依据、不确定性或用户原始补充")
            ], required: ["record_id"])
        case .updateBody:
            object([
                "record_id": integer("身体记录 Int64 ID"),
                "occurred_at": string("仅在用户明确纠正时间时提供的 ISO-8601 发生时间"),
                "weight": number("明确读到或用户提供的体重 kg"),
                "body_fat": number("明确读到或用户提供的体脂率"),
                "waist": number("明确读到或用户提供的腰围 cm"),
                "posture_note": string("中性、非诊断的可见体态观察"),
                "safety_note": string("局限性与安全提醒")
            ], required: ["record_id"])
        case .deleteRecord:
            object([
                "record_type": string(
                    "记录类型",
                    values: ["workout", "meal", "body"]
                ),
                "record_id": integer("记录 Int64 ID")
            ], required: ["record_type", "record_id"])
        case .updateGym:
            object([
                "gym_name": string("场馆名称；省略则使用当前健身房"),
                "summary": string("与训练有关的环境总结"),
                "media_source": string(
                    "可选的照片来源声明；明确继续紧邻上一轮图片时选 recent_gym_turn",
                    values: ["current_turn", "recent_gym_turn"]
                ),
                "equipment": array(
                    object([
                        "name": string("器械名称"),
                        "category": string("力量、有氧、自由重量或功能训练"),
                        "capabilities": string("可支持的动作或肌群"),
                        "confidence": number("识别置信度 0 到 1")
                    ], required: ["name", "category", "capabilities"]),
                    description: "画面中可见的器械，合并重复视角"
                )
            ])
        case .switchGym:
            object(["gym_name": string("目标健身房名称")], required: ["gym_name"])
        case .createProgram, .createTrainingProgram:
            object([
                "program_name": string("训练计划名称"),
                "goal": string("用户明确提供的计划目标"),
                "template_name": string("首个训练模板名称"),
                "schedule_hint": string("用户明确提供的安排提示"),
                "template_exercises": templateExerciseArray()
            ], required: ["program_name", "template_name", "template_exercises"])
        case .createProgramVersion, .createWorkoutTemplateVersion, .updateWorkoutTemplate:
            object([
                "program_id": integer("训练计划 Int64 ID"),
                "template_name": string("新版本训练模板名称"),
                "schedule_hint": string("用户明确提供的安排提示"),
                "template_exercises": templateExerciseArray()
            ], required: ["program_id", "template_name", "template_exercises"])
        case .archiveProgram, .archiveTrainingProgram:
            object([
                "program_id": integer("训练计划 Int64 ID")
            ], required: ["program_id"])
        case .deleteProgram, .deleteTrainingProgram:
            object([
                "program_id": integer("训练计划 Int64 ID")
            ], required: ["program_id"])
        case .startProgram, .startGuidedWorkout:
            object([
                "program_id": integer("训练计划 Int64 ID"),
                "auto_recording_policy": string(
                    "本次明确选择的录像策略；省略则关闭",
                    values: ["disabled", "one_per_exercise", "every_set"]
                )
            ], required: ["program_id"])
        case .recordPerformanceAnalysis:
            object([
                "performance_id": integer("Performance Int64 ID"),
                "input_fingerprint": string("当前复盘任务明确提供的输入指纹"),
                "evidence": string("按动作阶段描述的可见画面证据"),
                "limitations": string("镜头、遮挡、采样或缺失阶段造成的局限"),
                "feedback": string("中性、可执行、非诊断的一般训练建议")
            ], required: [
                "performance_id",
                "input_fingerprint",
                "evidence",
                "limitations",
                "feedback"
            ])
        case .submitFeedback:
            object([:])
        }
    }

    private func object(
        _ properties: [String: JSONSchema],
        required: [String] = []
    ) -> JSONSchema {
        JSONSchema(
            type: .object,
            properties: properties,
            required: required.isEmpty ? nil : required,
            additionalProperties: false
        )
    }

    private func mutationPayload() -> JSONSchema {
        object([
            "exercise_id": integer("动作 Int64 ID"),
            "exercise_name": string("没有匹配动作时的新标准名称"),
            "set_entries": workoutSetEntries("有序训练组"),
            "rest_seconds": integer("组间休息秒数"),
            "duration_minutes": integer("训练时长分钟数"),
            "form_score": integer("有充分视频证据时的动作评分"),
            "intensity": string("负荷判断"),
            "feedback": string("动作反馈"),
            "meal_type": string("早餐、午餐、晚餐或加餐"),
            "title": string("餐食标题"),
            "calories": integer("估算千卡；未知时省略"),
            "protein": number("蛋白质克数；未知时省略"),
            "carbs": number("碳水克数；未知时省略"),
            "fat": number("脂肪克数；未知时省略"),
            "items": mealItemArray(),
            "note": string("说明和估算局限"),
            "weight": number("明确提供的体重 kg"),
            "body_fat": number("明确提供的体脂率"),
            "waist": number("明确提供的腰围 cm"),
            "posture_note": string("非诊断体态观察"),
            "safety_note": string("局限和安全提醒")
        ])
    }

    private func mealItemArray() -> JSONSchema {
        array(
            object([
                "id": string("更新已有食物项时使用的稳定 UUID"),
                "name": string("食物名称"),
                "portion_description": string("份量说明"),
                "calories": integer("分项千卡"),
                "protein": number("分项蛋白质克数"),
                "carbs": number("分项碳水克数"),
                "fat": number("分项脂肪克数")
            ], required: ["name"]),
            description: "有序食物项；未知营养字段省略"
        )
    }

    private func string(_ description: String, values: [String]? = nil) -> JSONSchema {
        JSONSchema(type: .string, description: description, enum: values)
    }

    private func integer(_ description: String) -> JSONSchema {
        JSONSchema(type: .integer, description: description)
    }

    private func number(_ description: String) -> JSONSchema {
        JSONSchema(type: .number, description: description)
    }

    private func array(_ items: JSONSchema, description: String) -> JSONSchema {
        JSONSchema(type: .array, description: description, items: items)
    }

    private func workoutSetEntries(_ description: String) -> JSONSchema {
        array(
            object([
                "reps": integer("该组明确完成的次数"),
                "external_weight_kg": number("该组外部负重 kg；明确自重时填 0")
            ]),
            description: description
        )
    }

    private func templateExerciseArray() -> JSONSchema {
        array(
            object([
                "exercise_id": integer("动作 Int64 ID"),
                "order": integer("从 1 开始且不重复的动作顺序"),
                "target_sets": integer("用户明确设定的目标组数"),
                "target_reps": integer("用户明确设定的每组目标次数"),
                "target_weight_kg": number("用户明确设定的外部重量 kg"),
                "target_rest_seconds": integer("用户明确设定的组间休息秒数"),
                "first_set_is_warmup": JSONSchema(
                    type: .boolean,
                    description: "第 1 组是否为热身组"
                ),
                "equipment_kind": string("用户明确指定的必要器械"),
                "notes": string("用户明确提供的动作备注")
            ], required: ["exercise_id", "order"]),
            description: "按顺序排列的动作处方"
        )
    }
}

enum AgentTraceText {
    static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8)
        else {
            return "无法编码"
        }
        return text
    }

    static func jsonObject(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(
                  withJSONObject: value,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let text = String(data: data, encoding: .utf8)
        else {
            return "无法编码"
        }
        return text
    }

    static func modelInput(
        systemPrompt: String,
        history: [AgentConversationExchange] = [],
        userPrompt: String
    ) -> String {
        let historyText = history
            .map(\.traceSummary)
            .joined(separator: "\n\n")
        let historySection = historyText.isEmpty
            ? ""
            : "\n\n[RECENT SESSION HISTORY]\n\(historyText)"
        return """
        [SYSTEM]
        \(systemPrompt)
        \(historySection)
        [USER]
        \(userPrompt)
        """
    }
}

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
            """
            使用简洁、自然、有同理心的中文，像一位长期了解用户的私人教练。先给结论，再给必要依据和下一步；简单问题通常用两到五句，复杂问题使用少量自然段或列表。避免复述用户输入、堆砌术语、冗长表格和多级标题。
            """
        case .policy:
            ReActAgentPrompt.fixedContract
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

enum AgentSkill: String, CaseIterable, Identifiable {
    case gymAnalysis = "gym_analysis"
    case trainingPlan = "training_plan"
    case movementAnalysis = "movement_analysis"
    case nutritionAnalysis = "nutrition_analysis"
    case postureAnalysis = "posture_analysis"
    case trendAnalysis = "trend_analysis"
    case trainingVolumeAnalysis = "training_volume_analysis"
    case calorieEstimation = "calorie_estimation"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .gymAnalysis: "健身房分析"
        case .trainingPlan: "用户健身计划制定"
        case .movementAnalysis: "动作分析"
        case .nutritionAnalysis: "饮食分析"
        case .postureAnalysis: "体态分析"
        case .trendAnalysis: "运动趋势分析"
        case .trainingVolumeAnalysis: "运动量分析"
        case .calorieEstimation: "运动热量估算"
        }
    }

    var summary: String {
        switch self {
        case .gymAnalysis: "识别环境与器械，区分可见证据和推断，并更新电子健身房。"
        case .trainingPlan: "结合目标、历史、身体状态和当前器械制定可执行训练计划。"
        case .movementAnalysis: "基于图片或视频关键帧评估动作、负荷与安全边界。"
        case .nutritionAnalysis: "识别食物与份量，给出带不确定性的热量和宏量营养估算。"
        case .postureAnalysis: "以中性、非诊断方式记录体态与标准化照片的可比变化。"
        case .trendAnalysis: "分析训练、体重和饮食的周期趋势，区分信号、噪声和缺失数据。"
        case .trainingVolumeAnalysis: "按可验证记录计算训练容量，并支持不同时间粒度的可比分析。"
        case .calorieEstimation: "用本地 MET 规则和可追溯时长估算训练消耗，不让模型自由计算。"
        }
    }

    var whenToUse: String {
        switch self {
        case .gymAnalysis: "用户上传或描述健身房、器械、场馆切换时"
        case .trainingPlan: "用户希望制定、调整、查看或开始训练计划时"
        case .movementAnalysis: "用户要求分析动作照片、视频、技术或负荷时"
        case .nutritionAnalysis: "用户记录、识别或分析餐食与营养时"
        case .postureAnalysis: "用户记录或比较体态、体重、体脂、腰围时"
        case .trendAnalysis: "用户询问跨日或跨周期的训练、饮食、身体趋势时"
        case .trainingVolumeAnalysis: "用户询问训练量、容量、频率或周期对比时"
        case .calorieEstimation: "用户希望估算训练消耗或记录可计算训练时"
        }
    }

    var defaultsKey: String {
        "ai.react.skill.\(rawValue)"
    }

    var toolGroups: Set<AgentToolGroup> {
        switch self {
        case .gymAnalysis: [.gym]
        case .trainingPlan: [.exercises, .plans]
        case .movementAnalysis: [.exercises, .workouts, .review]
        case .nutritionAnalysis: [.meals]
        case .postureAnalysis: [.body]
        case .trendAnalysis: [.workouts, .meals, .body]
        case .trainingVolumeAnalysis: [.workouts]
        case .calorieEstimation: [.exercises, .workouts]
        }
    }

    static var defaultQuickSkills: [AgentSkill] {
        [
            .trainingPlan,
            .nutritionAnalysis,
            .movementAnalysis,
            .postureAnalysis,
            .trendAnalysis,
            .gymAnalysis
        ]
    }

    static var catalogForToolDescription: String {
        allCases.map { "\($0.rawValue)=\($0.title)" }.joined(separator: "；")
    }

    var defaultText: String {
        switch self {
        case .gymAnalysis:
            """
            # 健身房分析

            目标：把用户上传的健身房环境和器械媒体转化为可审查的电子健身房。

            执行规则：
            1. 逐项识别画面中确实可见的器械，合并同一器械的重复视角；器械名称、类别和支持动作保持简洁。
            2. 明确区分“画面可见”和“根据外形推断”。没有视觉证据的器械不得补齐；置信度只反映识别把握，不代表器械质量。
            3. 看不清型号、重量范围或附件时省略，不根据常见健身房配置猜测。
            4. 环境总结只描述与训练有关的空间、地面、照明或安全信息，不评价装修。
            5. 信息足够时调用 update_gym；用户未指定场馆名时更新当前健身房。发现歧义时先用一句简短问题确认。
            """
        case .trainingPlan:
            """
            # 用户健身计划制定

            目标：依据用户目标、训练历史、身体状态、恢复情况与当前健身房器械，生成可以直接执行并能渐进调整的计划。

            执行规则：
            1. 优先使用首轮已注入的身体、健身房、当日记录和近期变化；只有缺少必要精确事实时才调用对应 list 工具。
            2. 目标、每周可训练次数、伤痛限制等关键约束缺失且会改变方案时，只追问最重要的一到两个问题。
            3. 计划写清频率、动作模式、动作、组次、强度或 RIR、休息与进阶规则；只推荐当前场馆可用器械。
            4. 用用户近期可完成的训练作为起点，避免突然增加容量或负荷；同时安排恢复和降载条件。
            5. 写计划前用 search_exercises 复用动作；不存在时先 create_exercise，再把返回的 exercise_id 交给 create_program。计划是训练建议而非医疗处方。
            """
        case .movementAnalysis:
            """
            # 动作分析

            目标：基于图片或视频关键帧提供有证据、可执行的动作反馈，并判断当前负荷是否明显过轻或过重。

            执行规则：
            1. 先说明拍摄角度、遮挡、帧率和关键阶段是否足够；单张照片不能假装覆盖完整动作过程。
            2. 按起始、离心、底部、向心和结束阶段观察关节轨迹、躯干稳定、活动范围、节奏与左右差异。
            3. 只指出画面支持的问题，并给一到三个优先级最高的纠正提示；不能可靠观察时明确说“不确定”。
            4. 负荷判断结合速度、代偿、动作幅度和用户主观难度。证据不足时不判断过轻或过重，也不生成 form_score。
            5. 不做伤病诊断；锐痛、麻木、眩晕、明显失稳等情况建议立即停止并寻求专业评估。
            """
        case .nutritionAnalysis:
            """
            # 饮食分析

            目标：从文字和食物照片中提取可记录的餐食信息，并提供诚实的热量与宏量营养估算。

            执行规则：
            1. 识别可见食物、烹饪方式和可判断的份量；餐具尺寸未知、食物被遮挡或混合时说明不确定性。
            2. 热量、蛋白质、碳水和脂肪优先给合理区间；写入单值时使用区间中位估计，并在 note 中保留估算依据和误差来源。
            3. 不把照片外不可见的油、酱料或配料当作确定事实，可作为可能的偏差来源提示。
            4. 只有证据足够时调用 create_meal，按可见食物写入有序 items；无法识别核心食物或份量差异会显著影响结果时先询问用户。未知营养必须省略，不得写成 0。
            5. 记录成功后最多补充两句不重复结果卡数据的教练说明。提供平衡饮食建议，不使用羞辱性语言，不把估算当作医学或营养治疗结论。
            """
        case .postureAnalysis:
            """
            # 体态分析

            目标：以中性、非诊断方式描述体型和体态照片中的可见信息，帮助用户长期比较变化。

            执行规则：
            1. 只描述可见的对齐、姿势、拍摄条件和左右差异，不评价外貌、不推断人格或健康状况。
            2. 比较多张照片前检查机位、距离、光线、服装、站姿和时间是否接近；条件不同必须提示可比性有限。
            3. 体重、体脂和腰围只有在文字、秤面或用户输入明确可读时才记录；不得从外观猜测数值。
            4. 姿势差异不是疾病诊断。疼痛、活动受限或持续不对称需要由合格专业人员评估。
            5. 信息足够时调用 create_body_entry，并把观察局限写入 posture_note 或 safety_note。
            """
        case .trendAnalysis:
            """
            # 运动趋势分析

            目标：从一段时间的训练、身体和饮食记录中识别可解释的变化，而不是把短期波动误认为趋势。

            执行规则：
            1. 先使用已注入记录；范围不足时按需调用 list_workouts、list_meals 或 list_body_entries，并说明观察窗口、样本数和缺失情况。
            2. 比较一致时间粒度下的训练频率、主要动作表现、体重和饮食；将单日波动、测量条件差异与持续变化分开。
            3. 只对数据支持的相关性做谨慎解释，不宣称因果关系；样本不足时明确给出需要继续记录多久。
            4. 同时指出正向趋势、停滞和恢复风险，并给出一个下一周期可验证的调整建议。
            5. 不补造没有记录的训练日、体重或摄入值。
            """
        case .trainingVolumeAnalysis:
            """
            # 运动量分析

            目标：以一致口径分析训练容量和训练量变化，支持周、双周、月、季度等时间粒度。

            执行规则：
            1. 先使用已注入训练；范围不足时调用 list_workouts。外部负重容量仅对组数、次数和正重量都存在的记录计算：容量 = 组数 × 次数 × 重量。
            2. 自重动作、缺少重量或缺少组次的记录不得假设重量；应单独按有效组数、次数、时长或训练频率描述。
            3. 跨周期比较时使用相同动作或动作类别和相同统计口径，标注不完整周期、缺失记录和样本量变化。
            4. 同时观察容量、强度、频率与恢复信号；容量上升不自动等于进步，也不应鼓励无上限加量。
            5. 百分比变化只在基准值有效且周期可比时给出，否则使用绝对变化和局限说明。
            """
        case .calorieEstimation:
            """
            # 运动热量估算

            目标：在训练记录信息足够时生成可解释、可复现的热量估算，数值计算由 App 内置规则完成，不由模型自由心算。

            执行规则：
            1. 记录训练时先 search_exercises，必要时 create_exercise，再用有效 exercise_id 调用 create_workout。App 以用户最近身体记录的体重为优先，其次使用身体信息中的参考体重；不得从照片、身高或外观推测体重。
            2. 用户明确提供训练时长时原样传入 duration_minutes，不得改写。
               禁止用「组数 × 次数 × 间歇秒数 / 60」估算时长（例如 4×8×90/60=48 是错误的）。
               如果没有时长，但明确提供组数、次数和间歇，不要自行填写 duration_minutes；
               App 可只为热量计算推算：组数 × 次数 × 每次约 4 秒 +（组数 − 1）× 间歇秒数。
            3. 推算时长不写回用户的原始“训练时长”字段，必须标记为估算；它不包含热身、换器械、动作之间等待或训练后过量耗氧。
            4. App 使用 2024 Adult Compendium 的 MET 口径，按 MET × 体重(kg) × 时长(小时)计算总消耗估算并四舍五入为整数 kcal。
            5. 缺少体重，或既无明确时长也无法用完整组次与间歇推算时，不生成热量值。向用户说明缺少什么，不补默认值。
            6. MET 只是人群平均近似，抗阻训练的间歇性使误差可能较大。回答使用“预计约”并避免把数值当作精确测量或医疗结论。
            """
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

    static func catalogPrompt(defaults: UserDefaults = .standard) -> String {
        let entries = AgentSkillRegistry.allDescriptors(defaults: defaults).map {
            "- name: \($0.id)\n  description: \($0.summary)\n  when_to_use: \($0.whenToUse)"
        }.joined(separator: "\n")
        return """
        ## 可用 Skills
        \(entries)

        目录只披露元数据。当前输入若已包含选中 Skill 全文，直接执行，不要重复加载；否则只在
        任务明显匹配且确实需要专业流程时渐进加载一次。不要臆造目录外 Skill。
        """
    }
}
