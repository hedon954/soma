import Foundation
import SwiftOpenAI

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
    case createProgramVersion = "create_program_version"
    case archiveProgram = "archive_program"
    case deleteProgram = "delete_program"
    case startProgram = "start_program"
    case loadSkill = "load_skill"
    case updateWorkout = "update_workout"
    case updateMeal = "update_meal"
    case updateBody = "update_body"
    case updateGym = "update_gym"
    case switchGym = "switch_gym"
    case recordPerformanceAnalysis = "record_performance_analysis"
    case submitFeedback = "submit_feedback"

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
             .loadSkill:
            false
        default:
            true
        }
    }

    var schemaVersion: Int {
        switch self {
        case .getProgram,
             .createProgram,
             .createProgramVersion,
             .createExercise,
             .createWorkout:
            3
        case .searchExercises,
             .updateExercise,
             .archiveExercise,
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
             .updateWorkout,
             .updateMeal,
             .updateBody,
             .updateGym,
             .switchGym,
             .recordPerformanceAnalysis,
             .submitFeedback:
            2
        }
    }

    /// 新计划、批量动作/训练写入只广告 schema 3；升级前持久化的远程 Job 仍可按原版本交回设备执行。
    var supportedSchemaVersions: Set<Int> {
        switch self {
        case .getProgram, .createProgram, .createProgramVersion,
             .createExercise, .createWorkout:
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
        case .listPrograms: "读取计划列表"
        case .getProgram: "读取计划详情"
        case .createProgram: "创建训练计划"
        case .createProgramVersion: "创建计划版本"
        case .archiveProgram: "归档训练计划"
        case .deleteProgram: "删除训练计划"
        case .startProgram: "开始计划带练"
        case .loadSkill: "加载 Skill"
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

/// schema 3 `create_workout` 的一条训练；`record_id` 由本机分配，模型不得指定。
struct AgentWorkoutCreateInput: Codable, Equatable {
    var exerciseID: Int64
    var occurredAt: String? = nil
    var setEntries: [AgentWorkoutSetInput]? = nil
    var restSeconds: Int? = nil
    var durationMinutes: Int? = nil
    var formScore: Int? = nil
    var intensity: String? = nil
    var feedback: String? = nil

    enum CodingKeys: String, CodingKey {
        case intensity, feedback
        case exerciseID = "exercise_id"
        case occurredAt = "occurred_at"
        case setEntries = "set_entries"
        case restSeconds = "rest_seconds"
        case durationMinutes = "duration_minutes"
        case formScore = "form_score"
    }

    func toolArguments() -> AgentToolArguments {
        AgentToolArguments(
            occurredAt: occurredAt,
            exerciseID: exerciseID,
            setEntries: setEntries,
            restSeconds: restSeconds,
            durationMinutes: durationMinutes,
            formScore: formScore,
            intensity: intensity,
            feedback: feedback
        )
    }

    static func fromLegacyCreate(_ arguments: AgentToolArguments) -> AgentWorkoutCreateInput? {
        guard let exerciseID = arguments.exerciseID, exerciseID > 0 else {
            return nil
        }
        return AgentWorkoutCreateInput(
            exerciseID: exerciseID,
            setEntries: arguments.setEntries,
            restSeconds: arguments.restSeconds,
            durationMinutes: arguments.durationMinutes,
            formScore: arguments.formScore,
            intensity: arguments.intensity,
            feedback: arguments.feedback
        )
    }
}

enum AgentBatchWriteLimit {
    static let maxItems = 20
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

struct AgentTemplateSetPrescriptionInput: Codable, Equatable {
    var order: Int
    var kind: WorkoutSetKind
    var targetKind: WorkoutTargetKind
    var targetReps: Int? = nil
    var targetDurationSeconds: Int? = nil
    var targetWeightKG: Double? = nil
    var leftWeightKG: Double? = nil
    var rightWeightKG: Double? = nil
    var restBetweenSidesSeconds: Int? = nil
    var restAfterSetSeconds: Int? = nil
    var notes: String? = nil

    enum CodingKeys: String, CodingKey {
        case order, kind, notes
        case targetKind = "target_kind"
        case targetReps = "target_reps"
        case targetDurationSeconds = "target_duration_seconds"
        case targetWeightKG = "target_weight_kg"
        case leftWeightKG = "left_weight_kg"
        case rightWeightKG = "right_weight_kg"
        case restBetweenSidesSeconds = "rest_between_sides_seconds"
        case restAfterSetSeconds = "rest_after_set_seconds"
    }
}

struct AgentTemplateExerciseInput: Codable, Equatable {
    var exerciseID: Int64
    var order: Int
    /// schema 2 compatibility fields. New calls use `laterality + set_prescriptions`.
    var targetSets: Int? = nil
    var targetReps: Int? = nil
    var targetWeightKG: Double? = nil
    var targetRestSeconds: Int? = nil
    var firstSetIsWarmup: Bool? = nil
    var equipmentKind: String? = nil
    var notes: String? = nil
    var laterality: ExerciseLaterality? = nil
    var setPrescriptions: [AgentTemplateSetPrescriptionInput]? = nil

    enum CodingKeys: String, CodingKey {
        case order, notes, laterality
        case exerciseID = "exercise_id"
        case targetSets = "target_sets"
        case targetReps = "target_reps"
        case targetWeightKG = "target_weight_kg"
        case targetRestSeconds = "target_rest_seconds"
        case firstSetIsWarmup = "first_set_is_warmup"
        case equipmentKind = "equipment_kind"
        case setPrescriptions = "set_prescriptions"
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
    var overview: String?
    var templateName: String?
    var scheduleHint: String?
    var templateExercises: [AgentTemplateExerciseInput]?
    var autoRecordingPolicy: String?
    var exerciseNames: [String]?
    var workouts: [AgentWorkoutCreateInput]?

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
        case goal, overview
        case templateName = "template_name"
        case scheduleHint = "schedule_hint"
        case templateExercises = "template_exercises"
        case autoRecordingPolicy = "auto_recording_policy"
        case exerciseNames = "exercise_names"
        case workouts
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
        overview: String? = nil,
        templateName: String? = nil,
        scheduleHint: String? = nil,
        templateExercises: [AgentTemplateExerciseInput]? = nil,
        autoRecordingPolicy: String? = nil,
        exerciseNames: [String]? = nil,
        workouts: [AgentWorkoutCreateInput]? = nil
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
        self.overview = overview
        self.templateName = templateName
        self.scheduleHint = scheduleHint
        self.templateExercises = templateExercises
        self.autoRecordingPolicy = autoRecordingPolicy
        self.exerciseNames = exerciseNames
        self.workouts = workouts
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
            "仅在动作库没有语义等价项时批量创建标准动作，返回各 Int64 exercise_id；已存在名称复用原 ID，不要指定动作或记录 ID。"
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
            "一次创建一条或多条绑定有效 Int64 exercise_id 的训练记录；同一轮可多次写入，每次都新增。不要指定 record_id，由本机分配。修改已有训练必须先读取再用 update_workout。"
        case .deleteWorkout:
            "删除指定 Int64 训练记录；仅在当前用户消息明确授权删除时使用。"
        case .listMeals:
            "按可选日期范围读取饮食摘要；已预加载的当日记录无需重复读取。"
        case .getMeal:
            "按 Int64 record_id 读取一条饮食详情。"
        case .createMeal:
            "创建一餐新记录；同一轮可多次调用，每次都新增。未知营养字段省略。纠正、补图或同一餐新视角必须先读取再用 update_meal，不要用本工具代替更新。"
        case .deleteMeal:
            "删除指定 Int64 饮食记录；仅在当前用户消息明确授权删除时使用。"
        case .listBodyEntries:
            "按可选日期范围读取体重与体态摘要；已预加载的近期记录无需重复读取。"
        case .getBodyEntry:
            "按 Int64 record_id 读取一条身体记录详情。"
        case .createBodyEntry:
            "创建一条新的体重或体态记录；同一轮可多次写入，每次都新增。不得从外观猜数值。补充已有记录的多角度照片必须先读取再用 update_body。"
        case .deleteBodyEntry:
            "删除指定 Int64 身体记录；仅在当前用户消息明确授权删除时使用。"
        case .listPrograms:
            "读取可执行训练计划摘要。"
        case .getProgram:
            "按 Int64 program_id 读取计划概览、当前版本和独立逐组处方。"
        case .createProgram:
            "创建训练计划和首个不可变版本；每个动作必须使用有效 Int64 exercise_id，并以独立逐组处方表达左右、次数或时长。"
        case .createProgramVersion:
            "用完整独立逐组处方为已有计划创建不可变新版本，不改写历史版本和已开始 Session。"
        case .archiveProgram:
            "归档训练计划，保留模板版本和训练历史。"
        case .deleteProgram:
            "永久删除训练计划；仅在当前用户消息明确授权时使用，训练历史保留。"
        case .startProgram:
            "按 Int64 program_id 创建不可变训练 Session 并开始带练。"
        case .loadSkill:
            "按需加载一项专业健身 Skill 的完整 Markdown 指令。可用 Skill：\(AgentSkill.catalogForToolDescription)。"
        case .updateWorkout:
            "按 list_workouts 或 get_workout 返回的 Int64 record_id 更新一条训练记录，并把本次新媒体合并到原记录。"
        case .updateMeal:
            "按 list_meals 或 get_meal 返回的 Int64 record_id 更新一条饮食记录，并把本次新媒体合并到原记录。用户纠正食材、餐名或营养估算时优先使用。"
        case .updateBody:
            "按 list_body_entries 或 get_body_entry 返回的 Int64 record_id 更新一条身体记录，并把本次新媒体合并到原记录。不得补写没有证据的指标。"
        case .updateGym:
            """
            新建或更新电子健身房及其可见器械，并把本次用于识别的照片保存到健身房档案。\
            未指定 gym_name 时更新当前健身房。若历史消息明确标记可引用紧邻上一轮的健身房\
            图片，必须传 media_source=recent_gym_turn；不得引用更早或无关媒体。
            """
        case .switchGym:
            "把一个已经存在或明确命名的健身房设为当前健身房。"
        case .recordPerformanceAnalysis:
            "把用户主动请求的视频复盘保存到指定 Performance。只记录画面可见证据、明确局限和一般训练建议；不得诊断伤病或修改训练事实。"
        case .submitFeedback:
            "向 Soma 维护者提交产品反馈。只有当前用户消息明确要求提交产品反馈时才能调用；发送内容固定为当前消息原文和当前附件，不得用于动作评价、饮食建议、身体观察或一般教练反馈。"
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
                "exercise_names": array(
                    string("简洁、明确、去重后的标准动作名称"),
                    description: "一次创建 1 到 20 个新动作；已存在名称返回原 exercise_id"
                )
            ], required: ["exercise_names"])
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
        case .listPrograms:
            object([:])
        case .getProgram:
            object([
                "program_id": integer("训练计划 Int64 ID")
            ], required: ["program_id"])
        case .createWorkout:
            object([
                "workouts": workoutCreateItems()
            ], required: ["workouts"])
        case .createMeal:
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
        case .createBodyEntry:
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
        case .createProgram:
            object([
                "program_name": string("训练计划名称"),
                "overview": string("用户明确提供、可编辑的计划概览"),
                "template_name": string("首个训练模板名称"),
                "schedule_hint": string("用户明确提供的安排提示"),
                "template_exercises": templateExerciseArrayV3()
            ], required: ["program_name", "template_name", "template_exercises"])
        case .createProgramVersion:
            object([
                "program_id": integer("训练计划 Int64 ID"),
                "template_name": string("新版本训练模板名称"),
                "schedule_hint": string("用户明确提供的安排提示"),
                "template_exercises": templateExerciseArrayV3()
            ], required: ["program_id", "template_name", "template_exercises"])
        case .archiveProgram:
            object([
                "program_id": integer("训练计划 Int64 ID")
            ], required: ["program_id"])
        case .deleteProgram:
            object([
                "program_id": integer("训练计划 Int64 ID")
            ], required: ["program_id"])
        case .startProgram:
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

    private func workoutCreateItems() -> JSONSchema {
        array(
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
            ], required: ["exercise_id"]),
            description: "一次课的多条训练记录，每条绑定已有动作 ID；不要指定 record_id。最多 20 条。"
        )
    }

    private func templateExerciseArrayV3() -> JSONSchema {
        array(
            object([
                "exercise_id": integer("动作 Int64 ID，必须大于 0"),
                "order": integer("从 1 开始且不重复的动作顺序"),
                "laterality": string(
                    "none=左右同时或不区分；both=先左后右；left/right=仅单侧",
                    values: ExerciseLaterality.allCases.map(\.rawValue)
                ),
                "equipment_kind": string("用户明确指定的必要器械"),
                "notes": string("用户明确提供的动作备注"),
                "set_prescriptions": array(
                    object([
                        "order": integer("从 1 开始且不重复的逻辑组顺序"),
                        "kind": string(
                            "组类型",
                            values: [WorkoutSetKind.warmup.rawValue, WorkoutSetKind.working.rawValue]
                        ),
                        "target_kind": string(
                            "目标类型；repetitions 只提供 target_reps，duration 只提供 target_duration_seconds",
                            values: WorkoutTargetKind.allCases.map(\.rawValue)
                        ),
                        "target_reps": integer("次数目标，1 到 1000"),
                        "target_duration_seconds": integer("时长目标秒数，1 到 86400"),
                        "target_weight_kg": number("不区分侧别或双侧共用的外部重量，0 到 1000 kg"),
                        "left_weight_kg": number("左侧外部重量，0 到 1000 kg"),
                        "right_weight_kg": number("右侧外部重量，0 到 1000 kg"),
                        "rest_between_sides_seconds": integer("左右之间间歇，0 到 3600 秒"),
                        "rest_after_set_seconds": integer("本逻辑组结束后的间歇，0 到 3600 秒"),
                        "notes": string("本组备注")
                    ], required: ["order", "kind", "target_kind"]),
                    description: "每组互相独立；至少一组"
                )
            ], required: ["exercise_id", "order", "laterality", "set_prescriptions"]),
            description: "按顺序排列的动作；每个动作包含独立逻辑组"
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
            4. 只有证据足够时调用 create_meal，按可见食物写入有序 items；一餐一张新记录，同一轮可记录多餐。纠正、补图或改已有餐必须先 list/get 再用 update_meal。无法识别核心食物或份量差异会显著影响结果时先询问用户。未知营养必须省略，不得写成 0。
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
            5. 信息足够时调用 create_body_entry 新增记录；纠正或给已有测量补图必须先读取再用 update_body，并把观察局限写入 posture_note 或 safety_note。
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
            1. 记录训练时先 search_exercises，必要时一次 create_exercise，再用有效 exercise_id 一次 create_workout 写入全部动作。新建训练记录编号由本机分配。App 以用户最近身体记录的体重为优先，其次使用身体信息中的参考体重；不得从照片、身高或外观推测体重。
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
