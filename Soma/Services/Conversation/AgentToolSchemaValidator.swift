import CoreFoundation
import Foundation

enum AgentToolSchemaValidator {
    private static let maximumJSONInteger = 9_007_199_254_740_991.0

    static func validateTopLevelKeys(
        _ argumentData: Data,
        for name: AgentToolName
    ) throws {
        try validate(argumentData, for: name, schemaVersion: name.schemaVersion)
    }

    static func validate(
        _ argumentData: Data,
        for name: AgentToolName,
        schemaVersion: Int
    ) throws {
        guard let raw = try JSONSerialization.jsonObject(with: argumentData)
            as? [String: Any]
        else {
            throw ReActAgentError.invalidToolCall("\(name.rawValue) 参数必须是 JSON object。")
        }
        if schemaVersion == 2,
           [.createProgram, .updateProgram, .getProgram].contains(name)
        {
            try validatePlanV2(raw, for: name)
            return
        }
        if schemaVersion == 2, [.createExercise, .createWorkout].contains(name) {
            try validateCreateV2(raw, for: name)
            return
        }
        // 旧 schema 1 的形状由历史 decoder 与业务 Store 继续兜底；当前版本始终严格递归验证。
        guard schemaVersion == name.schemaVersion else { return }
        let parameters = try parameterSchema(for: name)
        try validate(raw, schema: parameters, path: name.rawValue)
        if [.createProgram, .updateProgram, .getProgram].contains(name) {
            try validatePlanV3(raw, for: name)
        }
        if [.createExercise, .createWorkout].contains(name) {
            try validateBatchCreateV3(raw, for: name)
        }
    }

    static func parameterSchema(for name: AgentToolName) throws -> [String: Any] {
        let encoded = try JSONEncoder().encode(name.chatTool)
        guard let tool = try JSONSerialization.jsonObject(with: encoded)
            as? [String: Any],
            let function = tool["function"] as? [String: Any],
            let parameters = function["parameters"] as? [String: Any]
        else {
            throw ReActAgentError.invalidToolCall("\(name.rawValue) 本地 Schema 无法读取。")
        }
        return parameters
    }

    private static func validatePlanV2(
        _ raw: [String: Any],
        for name: AgentToolName
    ) throws {
        let allowedTopLevel: Set<String>
        let requiredTopLevel: Set<String>
        switch name {
        case .getProgram:
            allowedTopLevel = ["program_id"]
            requiredTopLevel = allowedTopLevel
        case .createProgram:
            allowedTopLevel = [
                "program_name", "goal", "schedule_hint",
                "template_exercises"
            ]
            requiredTopLevel = ["program_name", "template_exercises"]
        case .updateProgram:
            allowedTopLevel = [
                "program_id", "program_name", "schedule_hint", "template_exercises"
            ]
            requiredTopLevel = ["program_id", "template_exercises"]
        default:
            return
        }
        let unknown = Set(raw.keys).subtracting(allowedTopLevel)
        guard unknown.isEmpty else {
            throw invalid(name.rawValue, "包含未声明参数：\(unknown.sorted().joined(separator: "、"))")
        }
        if let missing = requiredTopLevel.first(where: { raw[$0] == nil }) {
            throw invalid("\(name.rawValue).\(missing)", "缺少必填字段")
        }
        for key in ["program_name", "goal", "schedule_hint"]
            where raw[key] != nil && !(raw[key] is String)
        {
            throw invalid("\(name.rawValue).\(key)", "类型必须是 string")
        }
        if let programID = raw["program_id"] {
            try requireInteger(
                programID,
                in: 1 ... maximumJSONInteger,
                path: "\(name.rawValue).program_id"
            )
        }
        guard name != .getProgram else { return }
        guard let exercises = raw["template_exercises"] as? [[String: Any]],
              !exercises.isEmpty,
              exercises.count <= 100
        else {
            throw invalid("\(name.rawValue).template_exercises", "必须包含 1 到 100 个动作")
        }
        let allowedExerciseKeys: Set = [
            "exercise_id", "order", "target_sets", "target_reps", "target_weight_kg",
            "target_rest_seconds", "first_set_is_warmup", "equipment_kind", "notes"
        ]
        var orders = Set<Int>()
        for (index, exercise) in exercises.enumerated() {
            let path = "\(name.rawValue).template_exercises[\(index)]"
            let unknown = Set(exercise.keys).subtracting(allowedExerciseKeys)
            guard unknown.isEmpty else {
                throw invalid(path, "包含未声明参数：\(unknown.sorted().joined(separator: "、"))")
            }
            try requireInteger(
                exercise["exercise_id"],
                in: 1 ... maximumJSONInteger,
                path: "\(path).exercise_id"
            )
            let order = try requireInteger(exercise["order"], in: 1 ... 100, path: "\(path).order")
            guard orders.insert(order).inserted else {
                throw invalid("\(path).order", "动作顺序不能重复")
            }
            if exercise["target_sets"] != nil {
                try requireInteger(exercise["target_sets"], in: 1 ... 100, path: "\(path).target_sets")
            }
            if exercise["target_reps"] != nil {
                try requireInteger(exercise["target_reps"], in: 1 ... 1000, path: "\(path).target_reps")
            }
            if exercise["target_weight_kg"] != nil {
                try requireNumber(exercise["target_weight_kg"], in: 0 ... 1000, path: "\(path).target_weight_kg")
            }
            if exercise["target_rest_seconds"] != nil {
                try requireInteger(exercise["target_rest_seconds"], in: 0 ... 3600, path: "\(path).target_rest_seconds")
            }
            if let warmup = exercise["first_set_is_warmup"], !isBoolean(warmup) {
                throw invalid("\(path).first_set_is_warmup", "类型必须是 boolean")
            }
            for key in ["equipment_kind", "notes"]
                where exercise[key] != nil && !(exercise[key] is String)
            {
                throw invalid("\(path).\(key)", "类型必须是 string")
            }
        }
    }

    private static func validateCreateV2(
        _ raw: [String: Any],
        for name: AgentToolName
    ) throws {
        switch name {
        case .createExercise:
            let allowed: Set = ["exercise_name"]
            let unknown = Set(raw.keys).subtracting(allowed)
            guard unknown.isEmpty else {
                throw invalid(name.rawValue, "包含未声明参数：\(unknown.sorted().joined(separator: "、"))")
            }
            guard let nameValue = raw["exercise_name"] as? String,
                  !nameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw invalid("\(name.rawValue).exercise_name", "缺少必填字段")
            }
        case .createWorkout:
            let allowed: Set = [
                "exercise_id", "occurred_at", "set_entries", "rest_seconds",
                "duration_minutes", "form_score", "intensity", "feedback"
            ]
            let unknown = Set(raw.keys).subtracting(allowed)
            guard unknown.isEmpty else {
                throw invalid(name.rawValue, "包含未声明参数：\(unknown.sorted().joined(separator: "、"))")
            }
            try requireInteger(
                raw["exercise_id"],
                in: 1 ... maximumJSONInteger,
                path: "\(name.rawValue).exercise_id"
            )
            if raw["occurred_at"] != nil, !(raw["occurred_at"] is String) {
                throw invalid("\(name.rawValue).occurred_at", "类型必须是 string")
            }
            for key in ["intensity", "feedback"]
                where raw[key] != nil && !(raw[key] is String)
            {
                throw invalid("\(name.rawValue).\(key)", "类型必须是 string")
            }
            if raw["rest_seconds"] != nil {
                try requireInteger(raw["rest_seconds"], in: 0 ... 3600, path: "\(name.rawValue).rest_seconds")
            }
            if raw["duration_minutes"] != nil {
                try requireInteger(
                    raw["duration_minutes"],
                    in: 0 ... 1440,
                    path: "\(name.rawValue).duration_minutes"
                )
            }
            if raw["form_score"] != nil {
                try requireInteger(raw["form_score"], in: 0 ... 100, path: "\(name.rawValue).form_score")
            }
            try validateWorkoutSetEntries(
                raw["set_entries"],
                path: "\(name.rawValue).set_entries"
            )
        default:
            return
        }
    }

    private static func validate(
        _ value: Any,
        schema: [String: Any],
        path: String
    ) throws {
        let expectedTypes: [String]
        if let type = schema["type"] as? String {
            expectedTypes = [type]
        } else {
            expectedTypes = schema["type"] as? [String] ?? []
        }
        if !expectedTypes.isEmpty,
           !expectedTypes.contains(where: { matches(value, type: $0) })
        {
            throw invalid(path, "类型必须是 \(expectedTypes.joined(separator: " 或 "))")
        }
        if let allowed = schema["enum"] as? [String] {
            guard let text = value as? String, allowed.contains(text) else {
                throw invalid(path, "枚举值无效")
            }
        }
        if expectedTypes.contains("object"), let object = value as? [String: Any] {
            let properties = schema["properties"] as? [String: Any] ?? [:]
            let required = schema["required"] as? [String] ?? []
            if let missing = required.first(where: { object[$0] == nil }) {
                throw invalid("\(path).\(missing)", "缺少必填字段")
            }
            if schema["additionalProperties"] as? Bool == false {
                let unknown = Set(object.keys).subtracting(properties.keys)
                if !unknown.isEmpty {
                    throw invalid(path, "包含未声明参数：\(unknown.sorted().joined(separator: "、"))")
                }
            }
            for (key, item) in object {
                guard let child = properties[key] as? [String: Any] else { continue }
                try validate(item, schema: child, path: "\(path).\(key)")
            }
        }
        if expectedTypes.contains("array"), let values = value as? [Any],
           let itemSchema = schema["items"] as? [String: Any]
        {
            for (index, item) in values.enumerated() {
                try validate(item, schema: itemSchema, path: "\(path)[\(index)]")
            }
        }
    }

    private static func matches(_ value: Any, type: String) -> Bool {
        switch type {
        case "object":
            return value is [String: Any]
        case "array":
            return value is [Any]
        case "string":
            return value is String
        case "boolean":
            return isBoolean(value)
        case "integer":
            guard let number = number(value), !isBoolean(value) else { return false }
            return number.rounded() == number
        case "number":
            return number(value) != nil && !isBoolean(value)
        case "null":
            return value is NSNull
        default:
            return false
        }
    }

    private static func validateBatchCreateV3(
        _ raw: [String: Any],
        for name: AgentToolName
    ) throws {
        switch name {
        case .createExercise:
            guard let names = raw["exercise_names"] as? [Any],
                  (1 ... AgentBatchWriteLimit.maxItems).contains(names.count)
            else {
                throw invalid(
                    "\(name.rawValue).exercise_names",
                    "必须包含 1 到 \(AgentBatchWriteLimit.maxItems) 个名称"
                )
            }
        case .createWorkout:
            guard let workouts = raw["workouts"] as? [[String: Any]],
                  (1 ... AgentBatchWriteLimit.maxItems).contains(workouts.count)
            else {
                throw invalid(
                    "\(name.rawValue).workouts",
                    "必须包含 1 到 \(AgentBatchWriteLimit.maxItems) 条训练记录"
                )
            }
            for (index, workout) in workouts.enumerated() {
                try validateWorkoutSetEntries(
                    workout["set_entries"],
                    path: "\(name.rawValue).workouts[\(index)].set_entries"
                )
            }
        default:
            return
        }
    }

    private static func validateWorkoutSetEntries(
        _ value: Any?,
        path: String
    ) throws {
        guard let value else { return }
        guard let rows = value as? [[String: Any]] else {
            throw invalid(path, "类型必须是 array")
        }
        let allowedEntry: Set = ["reps", "duration_seconds", "external_weight_kg"]
        for (index, row) in rows.enumerated() {
            let rowPath = "\(path)[\(index)]"
            let unknownEntry = Set(row.keys).subtracting(allowedEntry)
            guard unknownEntry.isEmpty else {
                throw invalid(
                    rowPath,
                    "包含未声明参数：\(unknownEntry.sorted().joined(separator: "、"))"
                )
            }
            if row["reps"] != nil {
                try requireInteger(row["reps"], in: 1 ... 1000, path: "\(rowPath).reps")
            }
            if row["duration_seconds"] != nil {
                try requireInteger(
                    row["duration_seconds"],
                    in: 1 ... 86400,
                    path: "\(rowPath).duration_seconds"
                )
            }
            guard row["reps"] == nil || row["duration_seconds"] == nil else {
                throw invalid(rowPath, "reps 与 duration_seconds 只能提供一个")
            }
            if row["external_weight_kg"] != nil {
                try requireNumber(
                    row["external_weight_kg"],
                    in: 0 ... 1000,
                    path: "\(rowPath).external_weight_kg"
                )
            }
        }
    }

    private static func validatePlanV3(
        _ raw: [String: Any],
        for name: AgentToolName
    ) throws {
        if name == .getProgram {
            try requireInteger(raw["program_id"], in: 1 ... maximumJSONInteger, path: "get_program.program_id")
            return
        }
        if name == .updateProgram {
            try requireInteger(
                raw["program_id"],
                in: 1 ... maximumJSONInteger,
                path: "update_program.program_id"
            )
        }
        let exercises = try requirePlanExercises(raw, for: name)
        var exerciseOrders = Set<Int>()
        for (exerciseIndex, exercise) in exercises.enumerated() {
            let path = "\(name.rawValue).template_exercises[\(exerciseIndex)]"
            let laterality = try validatePlanExercise(
                exercise,
                path: path,
                exerciseOrders: &exerciseOrders
            )
            let sets = try requireSetPrescriptions(exercise, path: path)
            var setOrders = Set<Int>()
            for (setIndex, set) in sets.enumerated() {
                let setPath = "\(path).set_prescriptions[\(setIndex)]"
                try validateSetPrescription(
                    set,
                    path: setPath,
                    laterality: laterality,
                    setOrders: &setOrders
                )
            }
        }
    }

    private static func requirePlanExercises(
        _ raw: [String: Any],
        for name: AgentToolName
    ) throws -> [[String: Any]] {
        guard let exercises = raw["template_exercises"] as? [[String: Any]],
              !exercises.isEmpty,
              exercises.count <= 100
        else {
            throw invalid("\(name.rawValue).template_exercises", "必须包含 1 到 100 个动作")
        }
        return exercises
    }

    private static func validatePlanExercise(
        _ exercise: [String: Any],
        path: String,
        exerciseOrders: inout Set<Int>
    ) throws -> ExerciseLaterality {
        try requireInteger(
            exercise["exercise_id"],
            in: 1 ... maximumJSONInteger,
            path: "\(path).exercise_id"
        )
        let order = try requireInteger(
            exercise["order"],
            in: 1 ... 100,
            path: "\(path).order"
        )
        guard exerciseOrders.insert(order).inserted else {
            throw invalid("\(path).order", "动作顺序不能重复")
        }
        guard let lateralityText = exercise["laterality"] as? String,
              let laterality = ExerciseLaterality(rawValue: lateralityText)
        else {
            throw invalid("\(path).laterality", "侧别无效")
        }
        if exercise["target_rest_seconds"] != nil {
            try requireInteger(
                exercise["target_rest_seconds"],
                in: 0 ... 3600,
                path: "\(path).target_rest_seconds"
            )
        }
        if exercise["rest_between_sides_seconds"] != nil {
            try requireInteger(
                exercise["rest_between_sides_seconds"],
                in: 0 ... 3600,
                path: "\(path).rest_between_sides_seconds"
            )
            guard laterality == .both else {
                throw invalid(
                    "\(path).rest_between_sides_seconds",
                    "只有 both 可设置左右间歇"
                )
            }
        }
        return laterality
    }

    private static func requireSetPrescriptions(
        _ exercise: [String: Any],
        path: String
    ) throws -> [[String: Any]] {
        guard let sets = exercise["set_prescriptions"] as? [[String: Any]],
              !sets.isEmpty,
              sets.count <= 100
        else {
            throw invalid("\(path).set_prescriptions", "必须包含 1 到 100 个独立组")
        }
        return sets
    }

    private static func validateSetPrescription(
        _ set: [String: Any],
        path: String,
        laterality: ExerciseLaterality,
        setOrders: inout Set<Int>
    ) throws {
        let order = try requireInteger(
            set["order"],
            in: 1 ... 100,
            path: "\(path).order"
        )
        guard setOrders.insert(order).inserted else {
            throw invalid("\(path).order", "组顺序不能重复")
        }
        try validateTargetUnion(set, path: path)
        try validateOptionalSetNumbers(set, path: path)
        try validateLaterality(set, path: path, laterality: laterality)
    }

    private static func validateTargetUnion(
        _ set: [String: Any],
        path: String
    ) throws {
        guard let targetKind = set["target_kind"] as? String else {
            throw invalid("\(path).target_kind", "缺少目标类型")
        }
        switch targetKind {
        case WorkoutTargetKind.repetitions.rawValue:
            try requireInteger(
                set["target_reps"],
                in: 1 ... 1000,
                path: "\(path).target_reps"
            )
            guard set["target_duration_seconds"] == nil else {
                throw invalid(path, "次数组不能同时设置时长")
            }
        case WorkoutTargetKind.duration.rawValue:
            try requireInteger(
                set["target_duration_seconds"],
                in: 1 ... 86400,
                path: "\(path).target_duration_seconds"
            )
            guard set["target_reps"] == nil else {
                throw invalid(path, "时长组不能同时设置次数")
            }
        default:
            throw invalid("\(path).target_kind", "目标类型无效")
        }
    }

    private static func validateOptionalSetNumbers(
        _ set: [String: Any],
        path: String
    ) throws {
        for key in ["target_weight_kg", "left_weight_kg", "right_weight_kg"]
            where set[key] != nil
        {
            try requireNumber(set[key], in: 0 ... 1000, path: "\(path).\(key)")
        }
    }

    private static func validateLaterality(
        _ set: [String: Any],
        path: String,
        laterality: ExerciseLaterality
    ) throws {
        if laterality == .none,
           set["left_weight_kg"] != nil || set["right_weight_kg"] != nil
        {
            throw invalid(path, "none 不能设置逐侧重量")
        }
        if laterality == .left, set["right_weight_kg"] != nil {
            throw invalid(path, "left 不能设置右侧重量")
        }
        if laterality == .right, set["left_weight_kg"] != nil {
            throw invalid(path, "right 不能设置左侧重量")
        }
    }

    @discardableResult
    private static func requireInteger(
        _ value: Any?,
        in range: ClosedRange<Double>,
        path: String
    ) throws -> Int {
        guard let value, let number = number(value), !isBoolean(value),
              number.rounded() == number, range.contains(number),
              number <= Double(Int.max)
        else {
            throw invalid(path, "必须是范围 \(Int(range.lowerBound)) 到 \(range.upperBound.formatted()) 的整数")
        }
        return Int(number)
    }

    private static func requireNumber(
        _ value: Any?,
        in range: ClosedRange<Double>,
        path: String
    ) throws {
        guard let value, let number = number(value), !isBoolean(value),
              number.isFinite, range.contains(number)
        else {
            throw invalid(path, "数值超出允许范围")
        }
    }

    private static func number(_ value: Any) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func invalid(_ path: String, _ reason: String) -> ReActAgentError {
        .invalidToolCall("\(path)：\(reason)。")
    }
}
