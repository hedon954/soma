import Foundation

struct AgentEquipmentInput: Codable, Equatable {
    var name: String
    var category: String
    var capabilities: String
    var confidence: Double?
}

struct AgentWorkoutSetInput: Codable, Equatable {
    var reps: Int?
    var durationSeconds: Int?
    var externalWeightKG: Double?

    enum CodingKeys: String, CodingKey {
        case reps
        case durationSeconds = "duration_seconds"
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
    var glycemicSpeed: String? = nil
    var glycemicAssessment: String? = nil
    var recommendedEatingOrder: String? = nil
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
        case glycemicSpeed = "glycemic_speed"
        case glycemicAssessment = "glycemic_assessment"
        case recommendedEatingOrder = "recommended_eating_order"
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
            glycemicSpeed: glycemicSpeed,
            glycemicAssessment: glycemicAssessment,
            recommendedEatingOrder: recommendedEatingOrder,
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
    var notes: String? = nil

    enum CodingKeys: String, CodingKey {
        case order, kind, notes
        case targetKind = "target_kind"
        case targetReps = "target_reps"
        case targetDurationSeconds = "target_duration_seconds"
        case targetWeightKG = "target_weight_kg"
        case leftWeightKG = "left_weight_kg"
        case rightWeightKG = "right_weight_kg"
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
    var restBetweenSidesSeconds: Int? = nil
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
        case restBetweenSidesSeconds = "rest_between_sides_seconds"
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
    var glycemicSpeed: String?
    var glycemicAssessment: String?
    var recommendedEatingOrder: String?
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
    var scheduleHint: String?
    var templateExercises: [AgentTemplateExerciseInput]?
    var sourceWorkoutRecordIDs: [Int64]?
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
        case glycemicSpeed = "glycemic_speed"
        case glycemicAssessment = "glycemic_assessment"
        case recommendedEatingOrder = "recommended_eating_order"
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
        case scheduleHint = "schedule_hint"
        case templateExercises = "template_exercises"
        case sourceWorkoutRecordIDs = "source_workout_record_ids"
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
        glycemicSpeed: String? = nil,
        glycemicAssessment: String? = nil,
        recommendedEatingOrder: String? = nil,
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
        scheduleHint: String? = nil,
        templateExercises: [AgentTemplateExerciseInput]? = nil,
        sourceWorkoutRecordIDs: [Int64]? = nil,
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
        self.glycemicSpeed = glycemicSpeed
        self.glycemicAssessment = glycemicAssessment
        self.recommendedEatingOrder = recommendedEatingOrder
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
        self.scheduleHint = scheduleHint
        self.templateExercises = templateExercises
        self.sourceWorkoutRecordIDs = sourceWorkoutRecordIDs
        self.autoRecordingPolicy = autoRecordingPolicy
        self.exerciseNames = exerciseNames
        self.workouts = workouts
    }
}
