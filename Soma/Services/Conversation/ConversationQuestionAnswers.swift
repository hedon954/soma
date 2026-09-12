import Foundation
import SwiftData

extension AgentJob {
    var deterministicQuestionAction: AgentQuestionAction? {
        get { try? JSONDecoder().decode(AgentQuestionAction.self, from: deterministicPayloadData) }
        set { deterministicPayloadData = newValue.flatMap { try? JSONEncoder().encode($0) } ?? Data() }
    }
}

@MainActor
enum ConversationQuestionAnswers {
    static func activeRequest(
        from message: CoachMessage,
        sessionID: UUID,
        in context: ModelContext
    ) throws -> AgentUserQuestionRequest {
        guard message.sessionID == sessionID, message.isFromCoach, message.agentStatus == .succeeded,
              let turnID = message.turnID,
              let request = AgentUserQuestionRequest.from(items: message.agentTurnItems)
        else { throw AgentQuestionError.expired }
        var query = FetchDescriptor<CoachMessage>(
            predicate: #Predicate { $0.sessionID == sessionID && !$0.isFromCoach },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        query.fetchLimit = 1
        guard try context.fetch(query).first?.turnID == turnID else { throw AgentQuestionError.expired }
        return request
    }
}

@MainActor
extension ConversationProcessingService {
    @discardableResult
    func submitQuestionAnswer(
        from message: CoachMessage,
        questionID: String,
        optionID: String? = nil,
        customText: String? = nil,
        context: ConversationProcessingContext,
        locationService: LocationContextService,
        includeLocation: Bool = false
    ) throws -> Bool {
        let request = try ConversationQuestionAnswers.activeRequest(from: message, sessionID: context.session.id, in: context.modelContext)
        guard let question = request.questions.first(where: { $0.id == questionID })
        else { throw AgentQuestionError.expired }
        let text: String
        let action: AgentQuestionAction?
        if let optionID {
            guard let option = question.options.first(where: { $0.id == optionID })
            else { throw AgentQuestionError.expired }
            text = option.text
            action = option.action
            if let action {
                _ = try action.validatedCall(allowedNames: Set(AgentQuestionAction.allowedTools.map(\.rawValue)))
            }
        } else {
            guard question.allowsCustomInput, let value = customText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { throw AgentQuestionError.invalidQuestions }
            text = value
            action = nil
        }
        // 同一 MainActor 内校验并落盘新 Turn；第二次点击会看到新的用户 Turn 并失效。
        return submitPersisted(
            text: text,
            attachments: [],
            context: context,
            includeLocation: action == nil && includeLocation,
            locationService: locationService,
            selectedShortcutID: nil,
            forceLocal: action != nil,
            questionAction: action
        )
    }

    func runDeterministicQuestionAttempt(
        job: AgentJob,
        userMessage: CoachMessage,
        context: ConversationProcessingContext
    ) async {
        let (response, attempt) = ConversationTurnPersistence.bindResponseMessage(
            job: job, turnID: job.turnID, resumable: job.responseMessageID != nil, context: context
        )
        let trace = AgentTrace(
            provider: "Soma 本机规则", model: "deterministic-question-v1", endpoint: "local://conversation-recorder",
            dataSpaceRaw: context.dataSpace.rawValue, userInput: userMessage.text,
            contextSnapshot: "用户点击已绑定确定性工具的选项。", mediaKind: .none,
            imageCount: 0, imageAttachmentCount: 0, videoAttachmentCount: 0,
            turnID: job.turnID, attemptNumber: attempt
        )
        response.agentTraceID = trace.id
        context.modelContext.insert(trace)
        let spanID = UUID()
        let startedAt = Date.now
        let action = job.deterministicQuestionAction
        func emit(_ phase: AgentTurnPhase, status: AgentTraceStatus, result: AgentToolResult? = nil) {
            PersistentAgentEventProjection.persistAndProject(
                .span(AgentTraceSpan(
                    id: spanID, step: 1, kind: .tool,
                    title: action?.toolName.displayTitle ?? "处理你的选择", status: status,
                    operationID: job.id.uuidString, phase: phase, startedAt: startedAt, endedAt: .now,
                    input: action.map(AgentTraceText.json), output: result.map(AgentTraceText.json),
                    metadata: AgentTraceText.jsonObject(["execution_path": "deterministic_question_answer", "llm_invoked": false]),
                    errorMessage: result?.ok == false ? result?.message : nil
                )), job: job, responseMessage: response, trace: trace, in: context.modelContext
            )
        }
        emit(.preparing, status: .running)
        do {
            try Task.checkCancellation()
            guard let action else { throw AgentQuestionError.invalidAction }
            let call = try action.validatedCall(allowedNames: Set(AgentQuestionAction.allowedTools.map(\.rawValue)))
            emit(.running, status: .running)
            let result = try await executeAgentTool(
                call, turnID: job.turnID, userMessage: userMessage, sourceDate: job.stableDefaultOccurredAt,
                mediaAttachments: [], preferredGymID: nil, context: context
            )
            guard result.ok else {
                throw QuestionToolFailure(result: result)
            }
            emit(.completed, status: .succeeded, result: result)
            let endedAt = Date.now
            let itemID = UUID()
            PersistentAgentEventProjection.persistAndProject(
                .assistantTextCompleted(itemID: itemID, at: endedAt),
                job: job, responseMessage: response, trace: trace,
                liveText: LiveAgentTextSnapshot(itemID: itemID, text: result.message), in: context.modelContext
            )
            response.text = result.message
            response.recordType = result.recordType
            response.agentStatus = .succeeded
            trace.apply(.completed(answer: result.message, at: endedAt))
            try job.transition(to: .succeeded, at: endedAt)
            try ConversationTurnPersistence.append(kind: .completed, payload: .init(text: result.message), to: job, in: context.modelContext, at: endedAt)
            response.applyAgentEvent(.completed(answer: result.message, at: endedAt))
            context.session.touch(at: endedAt)
            try context.modelContext.save()
        } catch {
            let result = (error as? QuestionToolFailure)?.result ?? AgentToolResult.failure(error.localizedDescription)
            emit(.failed, status: .failed, result: result)
            response.agentStatus = .failed
            response.applyAgentEvent(.failed(message: result.message, cancelled: error is CancellationError, at: .now))
            trace.apply(.failed(message: result.message, cancelled: error is CancellationError, at: .now))
            try? ConversationTurnPersistence.waitForUser(job, message: result.message, in: context.modelContext)
        }
    }
}

private struct QuestionToolFailure: LocalizedError {
    let result: AgentToolResult
    var errorDescription: String? {
        result.message
    }
}
