import Foundation
import SwiftData

struct TypedAgentToolSource {
    var text: String
    var date: Date
    var explicitOccurredAt: Date?
    var sessionID: UUID?
    var turnID: UUID?
    var mediaKind: MediaKind
    var mediaPath: String?
    var mediaAttachments: [MediaAttachmentReference]
}

@MainActor
extension ConversationRecorder {
    static func executeTypedAgentTool(
        _ call: AgentToolCall,
        source: TypedAgentToolSource,
        in context: ModelContext
    ) -> AgentToolResult {
        switch call.name {
        case .searchExercises, .createExercise, .updateExercise,
             .archiveExercise, .mergeExercises:
            executeExerciseTool(call, in: context)
        case .listWorkouts, .getWorkout, .createWorkout,
             .updateWorkout, .deleteWorkout:
            executeWorkoutTool(
                call,
                source: source,
                in: context
            )
        case .listMeals, .getMeal, .createMeal, .updateMeal, .deleteMeal:
            executeMealTool(
                call,
                source: source,
                in: context
            )
        case .listBodyEntries, .getBodyEntry, .createBodyEntry,
             .updateBody, .deleteBodyEntry:
            executeBodyTool(
                call,
                source: source,
                in: context
            )
        case .listPrograms, .getProgram, .createProgram,
             .createProgramVersion, .archiveProgram, .deleteProgram,
             .startProgram:
            executeProgramTool(call, in: context)
        default: .failure("不是 v3 单一职责 Tool。", code: "internal_error")
        }
    }

    private static func executeExerciseTool(
        _ call: AgentToolCall,
        in context: ModelContext
    ) -> AgentToolResult {
        switch call.name {
        case .searchExercises: searchExercises(call.arguments, in: context)
        case .createExercise: createExercise(call.arguments, in: context)
        case .updateExercise: updateExercise(call.arguments, in: context)
        case .archiveExercise: archiveExercise(call.arguments, in: context)
        case .mergeExercises: mergeExercises(call.arguments, in: context)
        default: .failure("动作 Tool 路由异常。", code: "internal_error")
        }
    }

    private static func executeWorkoutTool(
        _ call: AgentToolCall,
        source: TypedAgentToolSource,
        in context: ModelContext
    ) -> AgentToolResult {
        switch call.name {
        case .listWorkouts:
            typedList(scope: "workouts", arguments: call.arguments, in: context)
        case .getWorkout:
            typedGet(scope: "workouts", arguments: call.arguments, in: context)
        case .createWorkout:
            createTypedWorkout(
                call.arguments,
                sourceText: source.text,
                sourceDate: source.date,
                sourceSessionID: source.sessionID,
                sourceTurnID: source.turnID,
                mediaKind: source.mediaKind,
                mediaPath: source.mediaPath,
                mediaAttachments: source.mediaAttachments,
                in: context
            )
        case .updateWorkout:
            updateWorkout(
                call.arguments,
                sourceText: source.text,
                occurredAt: source.explicitOccurredAt,
                mediaKind: source.mediaKind,
                mediaPath: source.mediaPath,
                mediaAttachments: source.mediaAttachments,
                in: context
            )
        case .deleteWorkout:
            typedDelete(type: "workout", arguments: call.arguments, sourceText: source.text, in: context)
        default:
            .failure("训练 Tool 路由异常。", code: "internal_error")
        }
    }

    private static func executeMealTool(
        _ call: AgentToolCall,
        source: TypedAgentToolSource,
        in context: ModelContext
    ) -> AgentToolResult {
        switch call.name {
        case .listMeals:
            typedList(scope: "meals", arguments: call.arguments, in: context)
        case .getMeal:
            typedGet(scope: "meals", arguments: call.arguments, in: context)
        case .createMeal:
            recordMeal(
                call.arguments,
                sourceText: source.text,
                sourceDate: source.date,
                sourceSessionID: source.sessionID,
                sourceTurnID: source.turnID,
                mediaKind: source.mediaKind,
                mediaPath: source.mediaPath,
                mediaAttachments: source.mediaAttachments,
                in: context
            )
        case .updateMeal:
            updateMeal(
                call.arguments,
                sourceText: source.text,
                occurredAt: source.explicitOccurredAt,
                mediaKind: source.mediaKind,
                mediaPath: source.mediaPath,
                mediaAttachments: source.mediaAttachments,
                in: context
            )
        case .deleteMeal:
            typedDelete(type: "meal", arguments: call.arguments, sourceText: source.text, in: context)
        default:
            .failure("饮食 Tool 路由异常。", code: "internal_error")
        }
    }

    private static func executeBodyTool(
        _ call: AgentToolCall,
        source: TypedAgentToolSource,
        in context: ModelContext
    ) -> AgentToolResult {
        switch call.name {
        case .listBodyEntries:
            typedList(scope: "body", arguments: call.arguments, in: context)
        case .getBodyEntry:
            typedGet(scope: "body", arguments: call.arguments, in: context)
        case .createBodyEntry:
            recordBody(
                call.arguments,
                sourceText: source.text,
                sourceDate: source.date,
                sourceSessionID: source.sessionID,
                sourceTurnID: source.turnID,
                mediaKind: source.mediaKind,
                mediaPath: source.mediaPath,
                mediaAttachments: source.mediaAttachments,
                in: context
            )
        case .updateBody:
            updateBody(
                call.arguments,
                sourceText: source.text,
                occurredAt: source.explicitOccurredAt,
                mediaKind: source.mediaKind,
                mediaPath: source.mediaPath,
                mediaAttachments: source.mediaAttachments,
                in: context
            )
        case .deleteBodyEntry:
            typedDelete(type: "body", arguments: call.arguments, sourceText: source.text, in: context)
        default:
            .failure("身体 Tool 路由异常。", code: "internal_error")
        }
    }

    private static func executeProgramTool(
        _ call: AgentToolCall,
        in context: ModelContext
    ) -> AgentToolResult {
        switch call.name {
        case .listPrograms: listTrainingPrograms(in: context)
        case .getProgram: getTrainingProgram(call.arguments, in: context)
        case .createProgram: createTrainingProgram(call.arguments, in: context)
        case .createProgramVersion: createWorkoutTemplateVersion(call.arguments, in: context)
        case .archiveProgram: archiveTrainingProgram(call.arguments, in: context)
        case .deleteProgram: deleteTrainingProgram(call.arguments, in: context)
        case .startProgram: startGuidedWorkout(call.arguments, in: context)
        default: .failure("计划 Tool 路由异常。", code: "internal_error")
        }
    }

    private static func createTypedWorkout(
        _ arguments: AgentToolArguments,
        sourceText: String,
        sourceDate: Date,
        sourceSessionID: UUID?,
        sourceTurnID: UUID?,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) -> AgentToolResult {
        guard (arguments.exerciseID ?? 0) > 0 else {
            return .failure(
                "create_workout 必须绑定有效的 exercise_id；动作不存在时先调用 create_exercise。",
                code: "missing_foreign_key",
                field: "exercise_id",
                expected: "existing positive Int64 exercise_id"
            )
        }
        return recordWorkout(
            arguments,
            sourceText: sourceText,
            sourceDate: sourceDate,
            sourceSessionID: sourceSessionID,
            sourceTurnID: sourceTurnID,
            mediaKind: mediaKind,
            mediaPath: mediaPath,
            mediaAttachments: mediaAttachments,
            in: context
        )
    }

    static func typedList(
        scope: String,
        arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        var routed = arguments
        routed.scope = scope
        routed.projection = "summary"
        return queryUserData(routed, preferredGymID: nil, in: context)
    }

    static func typedGet(
        scope: String,
        arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard (arguments.recordID ?? 0) > 0 else {
            return .failure(
                "record_id 必须是正整数。",
                code: "invalid_argument",
                field: "record_id",
                expected: "positive Int64"
            )
        }
        var routed = arguments
        routed.scope = scope
        routed.projection = "detail"
        return queryUserData(routed, preferredGymID: nil, in: context)
    }

    static func typedDelete(
        type: String,
        arguments: AgentToolArguments,
        sourceText: String,
        in context: ModelContext
    ) -> AgentToolResult {
        var routed = arguments
        routed.recordType = type
        return deleteRecord(routed, sourceText: sourceText, in: context)
    }

    static func searchExercises(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let query = arguments.query?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !query.isEmpty else {
            return .failure(
                "query 不能为空。",
                code: "invalid_argument",
                field: "query",
                expected: "non-empty exercise name"
            )
        }
        let limit = min(max(arguments.limit ?? 10, 1), 20)
        let matches = ExerciseLibraryStore.activeDefinitions(in: context)
            .filter {
                $0.canonicalName.localizedCaseInsensitiveContains(query)
                    || query.localizedCaseInsensitiveContains($0.canonicalName)
            }
            .prefix(limit)
        let items: [AgentJSONValue] = matches.map { exercise in
            .object([
                "exercise_id": exercise.businessID.map {
                    .number(Double($0))
                } ?? .null,
                "name": .string(exercise.canonicalName)
            ])
        }
        return .success(
            items.isEmpty ? "没有匹配动作。" : "找到 \(items.count) 个动作。",
            data: .object(["items": .array(items)])
        )
    }

    static func createExercise(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let name = arguments.exerciseName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !name.isEmpty else {
            return .failure(
                "exercise_name 不能为空。",
                code: "invalid_argument",
                field: "exercise_name",
                expected: "canonical exercise name"
            )
        }
        do {
            let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
                canonicalName: name,
                in: context
            )
            return .success(
                "动作已就绪 [exercise_id:\(exercise.businessID ?? 0)]：\(exercise.canonicalName)。"
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func updateExercise(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let id = arguments.exerciseID,
              let name = arguments.exerciseName?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ), !name.isEmpty
        else {
            return .failure("update_exercise 需要 exercise_id 和 exercise_name。")
        }
        do {
            let exercise = try ExerciseLibraryStore.definition(
                businessID: id,
                in: context
            )
            try ExerciseLibraryStore.rename(exercise, to: name, in: context)
            return .success("已更新动作 [exercise_id:\(id)]：\(exercise.canonicalName)。")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func archiveExercise(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let id = arguments.exerciseID else {
            return .failure("archive_exercise 需要 exercise_id。")
        }
        do {
            let exercise = try ExerciseLibraryStore.definition(
                businessID: id,
                in: context
            )
            try ExerciseLibraryStore.archive(exercise, in: context)
            return .success("已归档动作 [exercise_id:\(id)]：\(exercise.canonicalName)。")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func mergeExercises(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let sourceID = arguments.exerciseID,
              let targetID = arguments.targetExerciseID
        else {
            return .failure("merge_exercises 需要来源和目标 exercise_id。")
        }
        do {
            let source = try ExerciseLibraryStore.definition(
                businessID: sourceID,
                in: context
            )
            let target = try ExerciseLibraryStore.definition(
                businessID: targetID,
                in: context
            )
            let merge = try ExerciseLibraryStore.merge(
                source: source,
                into: target,
                in: context
            )
            try BusinessIDAllocator.assign(
                merge,
                namespace: "exercise_merge",
                in: context
            )
            try context.save()
            return .success("已将动作 \(sourceID) 合并到 \(targetID)。")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
