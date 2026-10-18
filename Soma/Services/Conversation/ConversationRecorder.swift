import Foundation
import SwiftData

@MainActor
enum ConversationRecorder {
    static func executeAgentTool(
        _ call: AgentToolCall,
        sourceText: String,
        sourceDate: Date = .now,
        sourceSessionID: UUID? = nil,
        sourceTurnID: UUID? = nil,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference] = [],
        preferredGymID _: UUID? = nil,
        in context: ModelContext
    ) -> AgentToolResult {
        try? BusinessIDAllocator.assignMissingIDs(in: context)
        let occurredAt: Date?
        if let raw = call.arguments.occurredAt {
            guard let parsed = parsedOccurredAt(raw) else {
                return .failure(
                    "occurred_at 必须是带时区的 ISO-8601 时间。",
                    code: "invalid_argument",
                    field: "occurred_at",
                    expected: "ISO-8601 timestamp with timezone"
                )
            }
            occurredAt = parsed
        } else {
            occurredAt = nil
        }
        let resolvedSourceDate = occurredAt ?? sourceDate
        if call.name.isTypedTool {
            return executeTypedAgentTool(
                call,
                source: TypedAgentToolSource(
                    text: sourceText,
                    date: resolvedSourceDate,
                    explicitOccurredAt: occurredAt,
                    sessionID: sourceSessionID,
                    turnID: sourceTurnID,
                    mediaKind: mediaKind,
                    mediaPath: mediaPath,
                    mediaAttachments: mediaAttachments
                ),
                in: context
            )
        }
        return switch call.name {
        case .searchExercises, .createExercise, .updateExercise,
             .archiveExercise, .mergeExercises, .listWorkouts,
             .getWorkout, .createWorkout, .updateWorkout, .deleteWorkout, .listMeals,
             .getMeal, .createMeal, .updateMeal, .deleteMeal, .listBodyEntries,
             .getBodyEntry, .createBodyEntry, .deleteBodyEntry,
             .updateBody,
             .listPrograms, .getProgram, .createProgram,
             .updateProgram, .archiveProgram, .deleteProgram,
             .startProgram:
            .failure("v3 Tool 路由异常。", code: "internal_error")
        case .askUserQuestions:
            AgentUserQuestionsTool.result(
                questions: call.arguments.questions,
                requiresSelection: ScheduleDraftAnswerText.requiresSelection(userText: sourceText)
            )
        case .proposeTrainingSchedule:
            TrainingScheduleDraftTool.propose(
                name: call.arguments.scheduleName,
                anchorDate: call.arguments.scheduleAnchorDate,
                slots: call.arguments.scheduleSlots,
                in: context
            )
        case .loadSkill:
            .failure("load_skill 应由 Agent 运行时处理。")
        case .submitFeedback:
            .failure("submit_feedback 应由 Agent 运行时异步处理。")
        case .updateGym:
            updateGym(
                call.arguments,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .switchGym:
            switchGym(call.arguments, in: context)
        case .recordPerformanceAnalysis:
            recordPerformanceAnalysis(
                call.arguments,
                sourceTurnID: sourceTurnID,
                in: context
            )
        }
    }

    static func parsedOccurredAt(_ value: String) -> Date? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.contains("T"),
              normalized.hasSuffix("Z")
              || normalized.dropFirst(10).contains("+")
              || normalized.dropFirst(10).contains("-")
        else {
            return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: normalized)
            ?? ISO8601DateFormatter().date(from: normalized)
    }
}
