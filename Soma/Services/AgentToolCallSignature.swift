import Foundation

/// ADR 0049：规范化语义键，避免字面 JSON 差异（同义字段、缺省与 null）绕过幂等。
enum AgentToolCallSignature {
    static func canonical(
        name: AgentToolName,
        arguments: AgentToolArguments
    ) -> String {
        var object: [String: Any] = ["name": name.rawValue]
        let canonicalArguments = AgentToolSignatureArguments(arguments).values
        if !canonicalArguments.isEmpty {
            object["arguments"] = canonicalArguments
        }
        return serialized(object, fallback: name.rawValue)
    }

    private static func serialized(
        _ object: [String: Any],
        fallback: String
    ) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys]
              ),
              let text = String(data: data, encoding: .utf8)
        else {
            return fallback
        }
        return text
    }
}

private struct AgentToolSignatureArguments {
    private(set) var values: [String: Any] = [:]

    init(_ arguments: AgentToolArguments) {
        appendScalarArguments(arguments)
        appendFields(arguments.fields)
        appendPayload(arguments.payload)
        appendSetEntries(arguments.setEntries)
        appendExerciseNames(arguments.exerciseNames)
        appendWorkouts(arguments.workouts)
        appendEquipment(arguments.equipment)
        appendTemplateExercises(arguments.templateExercises)
    }

    private mutating func appendScalarArguments(
        _ arguments: AgentToolArguments
    ) {
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
        put("operation", arguments.operation)
        put("occurred_at", arguments.occurredAt)
        put("gym_name", arguments.gymName)
        put("summary", arguments.summary)
        put("media_source", arguments.mediaSource)
        // exercise / exercise_name 同义，统一到 exercise_name。
        put(
            "exercise_name",
            Self.nonempty(arguments.exerciseName)
                ?? Self.nonempty(arguments.exercise)
        )
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
        put("total_sugar", arguments.totalSugar)
        put("glycemic_speed", arguments.glycemicSpeed)
        put("glycemic_assessment", arguments.glycemicAssessment)
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
        put("overview", arguments.overview)
        put("template_name", arguments.templateName)
        put("schedule_hint", arguments.scheduleHint)
        put("auto_recording_policy", arguments.autoRecordingPolicy)
    }

    private mutating func appendFields(_ fields: [String]?) {
        guard let fields, !fields.isEmpty else { return }
        values["fields"] = fields.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    private mutating func appendPayload(_ payload: AgentMutationPayload?) {
        guard let payload,
              let data = try? JSONEncoder().encode(payload),
              let value = try? JSONSerialization.jsonObject(with: data)
        else { return }
        values["payload"] = value
    }

    private mutating func appendSetEntries(
        _ setEntries: [AgentWorkoutSetInput]?
    ) {
        guard let setEntries, !setEntries.isEmpty else { return }
        // 逐组顺序是事实（ADR 0023），不得排序打散。
        values["set_entries"] = setEntries.map(Self.canonicalSetEntry)
    }

    private mutating func appendExerciseNames(_ names: [String]?) {
        guard let names, !names.isEmpty else { return }
        values["exercise_names"] = names.compactMap { Self.nonempty($0) }
    }

    private mutating func appendWorkouts(
        _ workouts: [AgentWorkoutCreateInput]?
    ) {
        guard let workouts, !workouts.isEmpty else { return }
        values["workouts"] = workouts.map(Self.canonicalWorkoutCreate)
    }

    private mutating func appendEquipment(
        _ equipment: [AgentEquipmentInput]?
    ) {
        guard let equipment, !equipment.isEmpty else { return }
        values["equipment"] = equipment
            .map(Self.canonicalEquipment)
            .sorted {
                ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "")
            }
    }

    private mutating func appendTemplateExercises(
        _ exercises: [AgentTemplateExerciseInput]?
    ) {
        guard let exercises, !exercises.isEmpty else { return }
        values["template_exercises"] = exercises
            .sorted { $0.order < $1.order }
            .map(Self.canonicalTemplateExercise)
    }

    private mutating func put(_ key: String, _ value: String?) {
        guard let value = Self.nonempty(value) else { return }
        values[key] = value
    }

    private mutating func put(_ key: String, _ value: Int?) {
        guard let value else { return }
        values[key] = value
    }

    private mutating func put(_ key: String, _ value: Int64?) {
        guard let value else { return }
        values[key] = value
    }

    private mutating func put(_ key: String, _ value: Double?) {
        guard let value else { return }
        values[key] = Self.rounded(value)
    }

    private static func canonicalSetEntry(
        _ entry: AgentWorkoutSetInput
    ) -> [String: Any] {
        var item: [String: Any] = [:]
        if let reps = entry.reps {
            item["reps"] = reps
        }
        if let weight = entry.externalWeightKG {
            item["external_weight_kg"] = rounded(weight)
        }
        return item
    }

    private static func canonicalWorkoutCreate(
        _ item: AgentWorkoutCreateInput
    ) -> [String: Any] {
        var row: [String: Any] = ["exercise_id": item.exerciseID]
        if let occurredAt = nonempty(item.occurredAt) {
            row["occurred_at"] = occurredAt
        }
        if let entries = item.setEntries, !entries.isEmpty {
            row["set_entries"] = entries.map(canonicalSetEntry)
        }
        if let rest = item.restSeconds {
            row["rest_seconds"] = rest
        }
        if let duration = item.durationMinutes {
            row["duration_minutes"] = duration
        }
        if let score = item.formScore {
            row["form_score"] = score
        }
        if let intensity = nonempty(item.intensity) {
            row["intensity"] = intensity
        }
        if let feedback = nonempty(item.feedback) {
            row["feedback"] = feedback
        }
        return row
    }

    private static func canonicalEquipment(
        _ item: AgentEquipmentInput
    ) -> [String: Any] {
        var row: [String: Any] = [
            "name": item.name.trimmingCharacters(in: .whitespacesAndNewlines),
            "category": item.category.trimmingCharacters(in: .whitespacesAndNewlines),
            "capabilities": item.capabilities
                .trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        if let confidence = item.confidence {
            row["confidence"] = rounded(confidence)
        }
        return row
    }

    private static func canonicalTemplateExercise(
        _ item: AgentTemplateExerciseInput
    ) -> [String: Any] {
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
            row["target_weight_kg"] = rounded(value)
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
        if let laterality = item.laterality {
            row["laterality"] = laterality.rawValue
        }
        if let sets = item.setPrescriptions, !sets.isEmpty {
            row["set_prescriptions"] = sets
                .sorted { $0.order < $1.order }
                .map(canonicalSetPrescription)
        }
        return row
    }

    private static func canonicalSetPrescription(
        _ set: AgentTemplateSetPrescriptionInput
    ) -> [String: Any] {
        var value: [String: Any] = [
            "order": set.order,
            "kind": set.kind.rawValue,
            "target_kind": set.targetKind.rawValue
        ]
        if let target = set.targetReps {
            value["target_reps"] = target
        }
        if let target = set.targetDurationSeconds {
            value["target_duration_seconds"] = target
        }
        if let weight = set.targetWeightKG {
            value["target_weight_kg"] = rounded(weight)
        }
        if let weight = set.leftWeightKG {
            value["left_weight_kg"] = rounded(weight)
        }
        if let weight = set.rightWeightKG {
            value["right_weight_kg"] = rounded(weight)
        }
        if let rest = set.restBetweenSidesSeconds {
            value["rest_between_sides_seconds"] = rest
        }
        if let rest = set.restAfterSetSeconds {
            value["rest_after_set_seconds"] = rest
        }
        if let notes = nonempty(set.notes) {
            value["notes"] = notes
        }
        return value
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }
}
