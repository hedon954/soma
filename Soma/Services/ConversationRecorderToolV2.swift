import Foundation
import SwiftData

extension ConversationRecorder {
    static func mutateUserData(
        _ arguments: AgentToolArguments,
        sourceText: String,
        sourceDate: Date = .now,
        sourceSessionID: UUID? = nil,
        sourceTurnID: UUID? = nil,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference] = [],
        in context: ModelContext
    ) -> AgentToolResult {
        guard let operation = arguments.operation?.lowercased(),
              ["create", "update", "delete"].contains(operation)
        else {
            return .failure("operation 仅支持 create、update、delete。")
        }
        guard let recordType = arguments.recordType?.lowercased(),
              ["workout", "meal", "body"].contains(recordType)
        else {
            return .failure("record_type 仅支持 workout、meal、body。")
        }
        if operation == "delete" {
            guard arguments.payload == nil else {
                return .failure("delete 不接受 payload。")
            }
            return deleteRecord(arguments, sourceText: sourceText, in: context)
        }
        guard let payload = arguments.payload else {
            return .failure("create/update 必须提供与 record_type 对应的 payload。")
        }
        let invalidFields = payload.invalidFields(for: recordType)
        guard invalidFields.isEmpty else {
            return .failure(
                "payload 字段 \(invalidFields.joined(separator: "、")) 不属于 \(recordType) 记录。"
            )
        }
        guard payload.hasValue(for: recordType) else {
            return .failure("payload 至少需要一个属于 \(recordType) 的字段。")
        }
        if operation == "create", arguments.recordID != nil {
            return .failure("create 不接受 record_id。")
        }
        if operation == "update", (arguments.recordID ?? 0) <= 0 {
            return .failure("update 必须提供有效的 record_id。")
        }
        let routed = payload.toolArguments(
            recordID: arguments.recordID,
            recordType: recordType
        )
        return switch (operation, recordType) {
        case ("create", "workout"):
            recordWorkout(
                routed,
                sourceText: sourceText,
                sourceDate: sourceDate,
                sourceSessionID: sourceSessionID,
                sourceTurnID: sourceTurnID,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case ("create", "meal"):
            recordMeal(
                routed,
                sourceText: sourceText,
                sourceDate: sourceDate,
                sourceSessionID: sourceSessionID,
                sourceTurnID: sourceTurnID,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case ("create", "body"):
            recordBody(
                routed,
                sourceText: sourceText,
                sourceDate: sourceDate,
                sourceSessionID: sourceSessionID,
                sourceTurnID: sourceTurnID,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case ("update", "workout"):
            updateWorkout(
                routed,
                sourceText: sourceText,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case ("update", "meal"):
            updateMeal(
                routed,
                sourceText: sourceText,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case ("update", "body"):
            updateBody(
                routed,
                sourceText: sourceText,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        default:
            .failure("不支持的记录操作。")
        }
    }

    static func validDateArgument(_ value: String?) -> Bool {
        value == nil || parsedQueryDate(value) != nil
    }

    static func queryValidationFailure(
        scope: String,
        arguments: AgentToolArguments
    ) -> AgentToolResult? {
        if arguments.projection == "detail" {
            let exactID: Int64? = switch scope {
            case "exercises", "exercise_history": arguments.exerciseID
            case "programs": arguments.programID
            case "sessions": arguments.sessionID
            default: arguments.recordID
            }
            guard (exactID ?? 0) > 0 else {
                return .failure("projection=detail 必须提供当前 scope 对应的精确 ID。")
            }
        }
        guard validDateArgument(arguments.dateFrom), validDateArgument(arguments.dateTo) else {
            return .failure("date_from/date_to 必须是 ISO8601 或 yyyy-MM-dd。")
        }
        if let fields = arguments.fields,
           let invalid = fields.first(where: {
               !queryFields(for: scope).contains($0)
           })
        {
            return .failure("字段 \(invalid) 不适用于 scope=\(scope)。")
        }
        return nil
    }

    static func queryFields(for scope: String) -> Set<String> {
        switch scope {
        case "workouts": [
                "record_id", "date", "title", "summary", "exercise_id",
                "set_entries", "rest_seconds", "duration_minutes", "feedback"
            ]
        case "meals": [
                "record_id", "date", "meal_type", "title", "calories",
                "protein", "carbs", "fat", "total_sugar", "glycemic_speed",
                "glycemic_assessment", "items", "note"
            ]
        case "body": [
                "record_id", "date", "weight", "body_fat", "waist",
                "analysis"
            ]
        case "profile": ["record_id", "summary"]
        case "gyms": ["record_id", "name", "is_current", "equipment"]
        case "exercises": ["exercise_id", "name"]
        case "exercise_history": ["record_id", "date", "summary"]
        case "programs": [
                "program_id", "name", "goal", "status", "current_template"
            ]
        case "templates": [
                "record_id", "program_id", "name", "version", "schedule_hint",
                "exercises"
            ]
        case "sessions": ["session_id", "date", "status", "summary", "details"]
        case "aggregate": ["group", "value", "missing_count"]
        default: []
        }
    }

    static func parsedQueryDate(_ value: String?) -> Date? {
        guard let value = value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    static func filteredByDate<T>(
        _ values: [T],
        arguments: AgentToolArguments,
        date: KeyPath<T, Date>
    ) -> [T] {
        let lower = parsedQueryDate(arguments.dateFrom)
        let rawUpper = parsedQueryDate(arguments.dateTo)
        let upper = rawUpper.flatMap { value in
            guard arguments.dateTo?.count == 10 else { return value }
            return Calendar.current.date(byAdding: .day, value: 1, to: value)
        }
        let filtered = values.filter { item in
            let itemDate = item[keyPath: date]
            return (lower == nil || itemDate >= lower!)
                && (upper == nil || itemDate < upper!)
        }
        return arguments.sort == "oldest" ? Array(filtered.reversed()) : filtered
    }

    static func pagedResult(
        _ sourceItems: [[String: AgentJSONValue]],
        noun: String,
        arguments: AgentToolArguments,
        limit: Int
    ) -> AgentToolResult {
        var items = sourceItems
        if arguments.sort == "name" {
            items.sort {
                textValue($0["name"] ?? $0["title"])
                    .localizedStandardCompare(textValue($1["name"] ?? $1["title"]))
                    == .orderedAscending
            }
        }
        let offset = cursorOffset(arguments.cursor)
        guard offset <= items.count else {
            return .failure("cursor 已失效，请从第一页重新查询。")
        }
        let end = min(items.count, offset + limit)
        let selected = items[offset ..< end].map { item -> AgentJSONValue in
            guard let fields = arguments.fields, !fields.isEmpty else {
                return .object(item)
            }
            let identityFields = ["record_id", "exercise_id", "program_id", "session_id"]
            let allowed = Set(fields + identityFields)
            return .object(item.filter { allowed.contains($0.key) })
        }
        let nextCursor = end < items.count
            ? Data("offset:\(end)".utf8).base64EncodedString()
            : nil
        return .success(
            selected.isEmpty ? "没有匹配的\(noun)。" : "返回 \(selected.count) 条\(noun)。",
            data: .object(["items": .array(selected)]),
            page: AgentToolPage(nextCursor: nextCursor)
        )
    }

    private static func cursorOffset(_ cursor: String?) -> Int {
        guard let cursor,
              let data = Data(base64Encoded: cursor),
              let text = String(data: data, encoding: .utf8),
              text.hasPrefix("offset:"),
              let value = Int(text.dropFirst("offset:".count)),
              value >= 0
        else {
            return cursor == nil ? 0 : .max
        }
        return value
    }

    private static func textValue(_ value: AgentJSONValue?) -> String {
        guard case let .string(text) = value else { return "" }
        return text
    }

    static func mealReference(_ entry: MealEntry) -> AgentRecordReference {
        AgentRecordReference(
            recordType: ConversationIntent.meal.rawValue,
            recordID: entry.businessID ?? 0,
            title: entry.title
        )
    }

    static func workoutReference(_ entry: WorkoutEntry) -> AgentRecordReference {
        AgentRecordReference(
            recordType: ConversationIntent.workout.rawValue,
            recordID: entry.businessID ?? 0,
            title: entry.exercise
        )
    }

    static func bodyReference(_ entry: BodyEntry) -> AgentRecordReference {
        AgentRecordReference(
            recordType: ConversationIntent.body.rawValue,
            recordID: entry.businessID ?? 0,
            title: entry.weight.map {
                "\($0.formatted(.number.precision(.fractionLength(0 ... 1))))kg"
            }
        )
    }

    static func gymReference(_ gym: GymProfile) -> AgentRecordReference {
        AgentRecordReference(
            recordType: ConversationIntent.gym.rawValue,
            recordID: gym.businessID ?? 0,
            title: gym.name
        )
    }

    static func mealResultData(_ entry: MealEntry) -> AgentJSONValue {
        .object([
            "record_id": .number(Double(entry.businessID ?? 0)),
            "meal_type": .string(entry.mealType.rawValue),
            "title": .string(entry.title),
            "date": .string(entry.date.ISO8601Format()),
            "calories": entry.calories.map { .number(Double($0)) } ?? .null,
            "protein": entry.protein.map(AgentJSONValue.number) ?? .null,
            "carbs": entry.carbs.map(AgentJSONValue.number) ?? .null,
            "fat": entry.fat.map(AgentJSONValue.number) ?? .null,
            "total_sugar": entry.totalSugar.map(AgentJSONValue.number) ?? .null,
            "glycemic_speed": entry.glycemicSpeedRaw
                .map(AgentJSONValue.string) ?? .null,
            "glycemic_assessment": entry.glycemicAssessment.isEmpty
                ? .null : .string(entry.glycemicAssessment),
            "items": .array(entry.items.map { item in
                .object([
                    "id": .string(item.id.uuidString),
                    "name": .string(item.name),
                    "portion_description": item.portionDescription
                        .map(AgentJSONValue.string) ?? .null,
                    "total_sugar": item.totalSugar
                        .map(AgentJSONValue.number) ?? .null
                ])
            })
        ])
    }
}

private extension AgentMutationPayload {
    func invalidFields(for recordType: String) -> [String] {
        let populated = populatedFields
        let allowed: Set<String> = switch recordType {
        case "workout": [
                "exercise_id", "exercise_name", "set_entries", "rest_seconds",
                "duration_minutes", "form_score", "intensity", "feedback"
            ]
        case "meal": [
                "meal_type", "title", "calories", "protein", "carbs", "fat",
                "total_sugar", "glycemic_speed", "glycemic_assessment", "items", "note"
            ]
        case "body": [
                "weight", "body_fat", "waist", "posture_note", "safety_note"
            ]
        default: []
        }
        return populated.subtracting(allowed).sorted()
    }

    func hasValue(for recordType: String) -> Bool {
        !populatedFields.isEmpty && invalidFields(for: recordType).count < populatedFields.count
    }

    var populatedFields: Set<String> {
        var fields = Set<String>()
        if exerciseID != nil {
            fields.insert("exercise_id")
        }
        if exerciseName != nil {
            fields.insert("exercise_name")
        }
        if setEntries != nil {
            fields.insert("set_entries")
        }
        if restSeconds != nil {
            fields.insert("rest_seconds")
        }
        if durationMinutes != nil {
            fields.insert("duration_minutes")
        }
        if formScore != nil {
            fields.insert("form_score")
        }
        if intensity != nil {
            fields.insert("intensity")
        }
        if feedback != nil {
            fields.insert("feedback")
        }
        if mealType != nil {
            fields.insert("meal_type")
        }
        if title != nil {
            fields.insert("title")
        }
        if calories != nil {
            fields.insert("calories")
        }
        if protein != nil {
            fields.insert("protein")
        }
        if carbs != nil {
            fields.insert("carbs")
        }
        if fat != nil {
            fields.insert("fat")
        }
        if totalSugar != nil {
            fields.insert("total_sugar")
        }
        if glycemicSpeed != nil {
            fields.insert("glycemic_speed")
        }
        if glycemicAssessment != nil {
            fields.insert("glycemic_assessment")
        }
        if items != nil {
            fields.insert("items")
        }
        if note != nil {
            fields.insert("note")
        }
        if weight != nil {
            fields.insert("weight")
        }
        if bodyFat != nil {
            fields.insert("body_fat")
        }
        if waist != nil {
            fields.insert("waist")
        }
        if postureNote != nil {
            fields.insert("posture_note")
        }
        if safetyNote != nil {
            fields.insert("safety_note")
        }
        return fields
    }
}
