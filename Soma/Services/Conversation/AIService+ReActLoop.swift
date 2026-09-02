import Foundation
import SwiftOpenAI

extension AIService {
    func runAgent(
        text: String,
        images: [Data],
        videos: [AgentVideoInput] = [],
        hasVideo: Bool,
        imageAttachmentCount: Int? = nil,
        videoAttachmentCount: Int? = nil,
        history: [AgentConversationExchange] = [],
        context: String,
        route requestedRoute: AIModelRoute? = nil,
        selectedSkillID: String? = nil,
        selectedShortcutID: String? = nil,
        checkpoint: AgentLoopCheckpoint? = nil,
        firstStepDeadlineEnabled: Bool = true,
        onCheckpoint: ((AgentLoopCheckpoint) -> Void)? = nil,
        videoFrameFallback: (() async -> [Data])? = nil,
        trace: ((AgentTraceEvent) -> Void)? = nil,
        execute: (AgentToolCall) async throws -> AgentToolResult
    ) async throws -> AgentOutcome {
        let prepared = try prepareAgentRun(AgentRunPreparationRequest(
            text: text,
            images: images,
            videos: videos,
            hasVideo: hasVideo,
            imageAttachmentCount: imageAttachmentCount,
            videoAttachmentCount: videoAttachmentCount,
            history: history,
            context: context,
            requestedRoute: requestedRoute,
            selectedSkillID: selectedSkillID,
            selectedShortcutID: selectedShortcutID,
            checkpoint: checkpoint
        ))
        let selectedRoute = prepared.selectedRoute
        let provider = selectedRoute.provider
        let model = selectedRoute.model
        let key = prepared.apiKey
        let support = prepared.support
        let historicalImageCount = prepared.historicalImageCount
        let hasVisualInput = prepared.hasVisualInput
        let userPrompt = prepared.userPrompt
        let traceInput = prepared.traceInput
        var currentModelStep = prepared.currentModelStep
        var toolState = prepared.toolState
        var assistantPassages = prepared.assistantPassages
        var checkpointBatches = prepared.checkpointBatches
        var completedOperationCount = prepared.completedOperationCount
        var clearedHistoryFrames = prepared.clearedHistoryFrames
        let maxSteps = prepared.maxSteps

        func persistCheckpoint(nextModelStep: Int) {
            onCheckpoint?(makeAgentCheckpoint(
                completedOperationCount: completedOperationCount,
                assistantPassages: assistantPassages,
                state: toolState,
                nextModelStep: nextModelStep,
                batches: checkpointBatches
            ))
        }

        do {
            if let pendingBatchIndex = checkpointBatches.indices.last,
               !checkpointBatches[pendingBatchIndex].isComplete
            {
                let pendingModelStep = checkpointBatches[pendingBatchIndex].modelStep
                let nextCallIndex = checkpointBatches[pendingBatchIndex].completedResults.count
                for callIndex in nextCallIndex ..< checkpointBatches[pendingBatchIndex].calls.count {
                    try Task.checkCancellation()
                    guard completedOperationCount < maxSteps else {
                        throw ReActAgentError.stepLimit(maxSteps: maxSteps)
                    }
                    let operationStep = completedOperationCount + 1
                    let checkpointCall = checkpointBatches[pendingBatchIndex].calls[callIndex]
                    let result = try await applyResolvedToolCall(
                        native: checkpointCall.native,
                        call: checkpointCall.action,
                        preflightResult: checkpointCall.preflightResult,
                        step: operationStep,
                        state: &toolState,
                        execute: execute,
                        trace: trace
                    )
                    checkpointBatches[pendingBatchIndex].completedResults.append(
                        AgentCheckpointToolResult(
                            step: operationStep,
                            call: checkpointCall,
                            result: result
                        )
                    )
                    completedOperationCount = operationStep
                    let nextStep = checkpointBatches[pendingBatchIndex].isComplete
                        ? pendingModelStep + 1
                        : pendingModelStep
                    persistCheckpoint(nextModelStep: nextStep)
                }
                currentModelStep = pendingModelStep + 1
            }

            guard currentModelStep <= maxSteps,
                  completedOperationCount < maxSteps
            else {
                throw ReActAgentError.stepLimit(maxSteps: maxSteps)
            }
            while currentModelStep <= maxSteps, completedOperationCount < maxSteps {
                try Task.checkCancellation()
                if currentModelStep >= 2, !clearedHistoryFrames {
                    clearHistoricalImageParts(in: &toolState.messages)
                    clearedHistoryFrames = true
                }
                let operationStep = completedOperationCount + 1
                let modelSpanID = UUID()
                let textItemID = UUID()
                let reasoningItemID = UUID()
                let modelStartedAt = Date()
                announceModelStepStart(
                    AgentModelStepStart(
                        spanID: modelSpanID,
                        operationStep: operationStep,
                        modelStep: currentModelStep,
                        startedAt: modelStartedAt,
                        traceInput: traceInput,
                        route: selectedRoute,
                        historyExchangeCount: history.count,
                        historicalImageCount: checkpoint != nil || clearedHistoryFrames
                            ? 0
                            : historicalImageCount,
                        directVideoCount: videos.count,
                        mediaMode: initialMediaMode(
                            images: images,
                            videos: videos,
                            hasVideo: hasVideo
                        ),
                        messageCount: toolState.messages.count,
                        exposedToolNames: toolState.exposedToolNames,
                        selectedSkillID: selectedSkillID,
                        selectedShortcutID: selectedShortcutID
                    ),
                    trace: trace
                )

                var streamed: AgentStreamOutcome
                do {
                    streamed = try await consumeAgentStepWithRetry(
                        messages: &toolState.messages,
                        request: AgentStreamStepRequest(
                            tools: toolState.tools,
                            model: model,
                            provider: provider,
                            images: images,
                            videos: videos,
                            hasVideo: hasVideo,
                            step: currentModelStep,
                            route: selectedRoute,
                            apiKey: key,
                            userPrompt: userPrompt,
                            textItemID: textItemID,
                            reasoningItemID: reasoningItemID,
                            enforceFirstStepDeadline: firstStepDeadlineEnabled
                                && currentModelStep == 1
                        ),
                        maximumRetryCount: AgentStepRetryPolicy.maximumRetryCount,
                        videoFrameFallback: videoFrameFallback,
                        trace: trace
                    )
                } catch let StreamingFailure.interrupted(
                    error,
                    passage,
                    reasoning,
                    _
                ) {
                    let endedAt = Date()
                    let reason = agentErrorDescription(error)
                    if !reasoning.isEmpty {
                        trace?(.reasoningCompleted(
                            itemID: reasoningItemID,
                            text: reasoning,
                            at: endedAt
                        ))
                    }
                    trace?(.span(AgentTraceSpan(
                        id: modelSpanID,
                        step: operationStep,
                        kind: .model,
                        title: "LLM 推理",
                        status: error is CancellationError ? .cancelled : .failed,
                        startedAt: modelStartedAt,
                        endedAt: endedAt,
                        input: currentModelStep == 1
                            ? traceInput
                            : "继续处理上一轮工具结果。",
                        output: passage.nilIfEmpty,
                        errorMessage: reason
                    )))
                    if hasVisualInput, support == .unknown, error is APIError {
                        throw AIServiceError.multimodalRequestFailed(
                            provider: provider.displayName,
                            model: model,
                            reason: reason
                        )
                    }
                    throw error
                }

                let passage = streamed.passage
                let modelEndedAt = Date()
                if !streamed.reasoning.isEmpty {
                    trace?(.reasoningCompleted(
                        itemID: reasoningItemID,
                        text: streamed.reasoning,
                        at: modelEndedAt
                    ))
                }
                if !passage.isEmpty {
                    trace?(.assistantTextCompleted(
                        itemID: textItemID,
                        at: modelEndedAt
                    ))
                }
                let orderedDeltas = streamed.toolCalls
                trace?(.span(AgentTraceSpan(
                    id: modelSpanID,
                    step: operationStep,
                    kind: .model,
                    title: "LLM 推理",
                    status: .succeeded,
                    startedAt: modelStartedAt,
                    endedAt: modelEndedAt,
                    input: currentModelStep == 1
                        ? traceInput
                        : "继续处理上一轮工具结果。",
                    output: passage.nilIfEmpty ?? (
                        orderedDeltas.isEmpty
                            ? nil
                            : "生成 \(orderedDeltas.count) 个原生 tool_call。"
                    ),
                    metadata: modelSpanMetadata(
                        history: history,
                        historicalImageCount: checkpoint != nil || clearedHistoryFrames
                            ? 0
                            : historicalImageCount,
                        directVideoCount: videos.count,
                        route: selectedRoute,
                        streamed: streamed,
                        exposedToolNames: toolState.exposedToolNames,
                        startedAt: modelStartedAt,
                        endedAt: modelEndedAt
                    )
                )))

                if !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    assistantPassages.append(passage)
                }

                guard !orderedDeltas.isEmpty else {
                    return try completeAgentRun(
                        passage: passage,
                        assistantPassages: assistantPassages,
                        observations: toolState.observations,
                        trace: trace
                    )
                }

                let resolvedCalls = try orderedDeltas.enumerated().map { position, accumulator in
                    try accumulator.prepared(
                        fallbackID: "soma_call_\(currentModelStep)_\(position)"
                    )
                }
                toolState.messages.append(ChatCompletionParameters.Message(
                    role: .assistant,
                    content: .text(passage),
                    toolCalls: resolvedCalls.map(\.native)
                ))

                let checkpointCalls = resolvedCalls.map { resolved in
                    AgentCheckpointToolCall(
                        id: resolved.native.id ?? UUID().uuidString,
                        argumentsJSON: resolved.native.function.arguments,
                        action: resolved.local,
                        preflightResult: resolved.preflightResult
                    )
                }
                checkpointBatches.append(AgentCheckpointToolBatch(
                    modelStep: currentModelStep,
                    modelOperationStep: operationStep,
                    passage: passage,
                    calls: checkpointCalls,
                    completedResults: []
                ))
                completedOperationCount = operationStep
                persistCheckpoint(nextModelStep: currentModelStep)

                let batchIndex = checkpointBatches.count - 1
                for callIndex in checkpointCalls.indices {
                    guard completedOperationCount < maxSteps else {
                        throw ReActAgentError.stepLimit(maxSteps: maxSteps)
                    }
                    let checkpointCall = checkpointCalls[callIndex]
                    let toolStep = completedOperationCount + 1
                    let result = try await applyResolvedToolCall(
                        native: checkpointCall.native,
                        call: checkpointCall.action,
                        preflightResult: checkpointCall.preflightResult,
                        step: toolStep,
                        state: &toolState,
                        execute: execute,
                        trace: trace
                    )
                    checkpointBatches[batchIndex].completedResults.append(
                        AgentCheckpointToolResult(
                            step: toolStep,
                            call: checkpointCall,
                            result: result
                        )
                    )
                    completedOperationCount = toolStep
                    let nextStep = checkpointBatches[batchIndex].isComplete
                        ? currentModelStep + 1
                        : currentModelStep
                    persistCheckpoint(nextModelStep: nextStep)
                }
                currentModelStep += 1
            }
            throw ReActAgentError.stepLimit(maxSteps: maxSteps)
        } catch {
            projectAgentRunFailure(error, trace: trace)
            throw error
        }
    }

    private func projectAgentRunFailure(
        _ error: Error,
        trace: ((AgentTraceEvent) -> Void)?
    ) {
        let failedAt = Date()
        let cancelled = error is CancellationError
        let reason = agentErrorDescription(error)
        trace?(.span(AgentTraceSpan(
            kind: .output,
            title: cancelled ? "执行取消" : "执行失败",
            status: cancelled ? .cancelled : .failed,
            startedAt: failedAt,
            endedAt: failedAt,
            errorMessage: reason
        )))
        trace?(.failed(
            message: reason,
            cancelled: cancelled,
            at: failedAt
        ))
    }

    func applyResolvedToolCall(
        native: ToolCall,
        call: AgentToolCall,
        preflightResult: AgentToolResult? = nil,
        step: Int,
        state: inout AgentToolLoopState,
        execute: (AgentToolCall) async throws -> AgentToolResult,
        trace: ((AgentTraceEvent) -> Void)?
    ) async throws -> AgentToolResult {
        try Task.checkCancellation()
        let spanID = UUID()
        let operationID = native.id ?? spanID.uuidString.lowercased()
        let startedAt = Date()
        let skill = call.arguments.skillID.flatMap {
            AgentSkillRegistry.descriptor(id: $0, defaults: defaults)
        }
        let traceInput = preflightResult == nil
            ? AgentTraceText.json(call)
            : native.function.arguments
        trace?(.span(AgentTraceSpan(
            id: spanID,
            step: step,
            kind: call.name == .loadSkill ? .skill : .tool,
            title: skill?.title ?? call.name.displayTitle,
            status: .running,
            operationID: operationID,
            phase: .preparing,
            startedAt: startedAt,
            endedAt: startedAt,
            input: traceInput
        )))

        let runningAt = Date()
        trace?(.span(AgentTraceSpan(
            id: spanID,
            step: step,
            kind: call.name == .loadSkill ? .skill : .tool,
            title: skill?.title ?? call.name.displayTitle,
            status: .running,
            operationID: operationID,
            phase: .running,
            startedAt: startedAt,
            endedAt: runningAt,
            input: traceInput
        )))

        let result: AgentToolResult
        let wasDeduplicated: Bool
        do {
            if let preflightResult {
                result = preflightResult
                wasDeduplicated = false
            } else if call.name.isMutation,
                      !state.executedMutations.insert(call.signature).inserted
            {
                result = .success("相同写入操作已经执行，本次重复调用已忽略。")
                wasDeduplicated = true
            } else if !call.name.isMutation,
                      call.name != .loadSkill,
                      let prior = state.executedReads[call.signature]
            {
                result = .success("已查过相同只读调用，复用结果：\n\(prior.observation)")
                wasDeduplicated = true
            } else if call.name == .loadSkill {
                result = loadSkill(call)
                wasDeduplicated = false
            } else {
                result = try await execute(call)
                wasDeduplicated = false
                if !call.name.isMutation {
                    state.executedReads[call.signature] = result
                }
            }
        } catch {
            let endedAt = Date()
            AgentDiagnostics.toolFinished(
                name: call.name.rawValue,
                step: step,
                status: error is CancellationError ? "cancelled" : "failed",
                startedAt: startedAt,
                endedAt: endedAt,
                deduplicated: false,
                detail: agentErrorDescription(error)
            )
            trace?(.span(AgentTraceSpan(
                id: spanID,
                step: step,
                kind: call.name == .loadSkill ? .skill : .tool,
                title: skill?.title ?? call.name.displayTitle,
                status: error is CancellationError ? .cancelled : .failed,
                operationID: operationID,
                phase: error is CancellationError ? .cancelled : .failed,
                startedAt: startedAt,
                endedAt: endedAt,
                input: traceInput,
                metadata: AgentTraceText.jsonObject([
                    "tool_call_id": native.id ?? ""
                ]),
                errorMessage: agentErrorDescription(error)
            )))
            throw error
        }

        let endedAt = Date()
        AgentDiagnostics.toolFinished(
            name: call.name.rawValue,
            step: step,
            status: result.ok ? "succeeded" : "failed",
            startedAt: startedAt,
            endedAt: endedAt,
            deduplicated: wasDeduplicated,
            detail: result.ok ? nil : result.observation
        )
        let spanKind: AgentTraceSpanKind = call.name == .loadSkill
            ? .skill
            : .tool
        let traceMetadata = AgentTraceText.jsonObject([
            "tool_call_id": native.id ?? "",
            "deduplicated": wasDeduplicated,
            "skill_id": call.arguments.skillID.map { $0 as Any } ?? NSNull(),
            "skill_customized": skill.map { !$0.isBuiltIn as Any } ?? NSNull(),
            "record_type": result.recordType
                .map { $0.rawValue as Any } ?? NSNull()
        ])
        let completedSpan = AgentTraceSpan(
            id: spanID,
            step: step,
            kind: spanKind,
            title: skill?.title ?? call.name.displayTitle,
            status: result.ok ? .succeeded : .failed,
            operationID: operationID,
            phase: result.ok ? .completed : .failed,
            startedAt: startedAt,
            endedAt: endedAt,
            input: traceInput,
            output: AgentTraceText.json(result),
            metadata: traceMetadata,
            errorMessage: result.ok ? nil : result.observation
        )
        trace?(.span(completedSpan))
        state.observations.append(AgentObservation(step: step, action: call, result: result))
        state.messages.append(ChatCompletionParameters.Message(
            role: .tool,
            content: .text(AgentTraceText.json(result)),
            toolCallID: native.id
        ))
        return result
    }

    func restoreCheckpointBatches(
        _ batches: [AgentCheckpointToolBatch],
        state: inout AgentToolLoopState
    ) {
        for batch in batches {
            state.messages.append(ChatCompletionParameters.Message(
                role: .assistant,
                content: .text(batch.passage),
                toolCalls: batch.calls.map(\.native)
            ))
            for completed in batch.completedResults {
                let call = completed.call.action
                let result = completed.result
                state.observations.append(AgentObservation(
                    step: completed.step,
                    action: call,
                    result: result
                ))
                if call.name.isMutation {
                    state.executedMutations.insert(call.signature)
                } else if call.name != .loadSkill {
                    state.executedReads[call.signature] = result
                }
                state.messages.append(ChatCompletionParameters.Message(
                    role: .tool,
                    content: .text(AgentTraceText.json(result)),
                    toolCallID: completed.call.id
                ))
            }
        }
    }

    func agentUserContent(
        prompt: String,
        images: [Data],
        maximumImageCount: Int
    ) -> ChatCompletionParameters.Message.ContentType {
        guard !images.isEmpty else {
            return .text(prompt)
        }
        var parts: [ChatCompletionParameters.Message.ContentType.MessageContent] = [.text(prompt)]
        for image in images.prefix(maximumImageCount) {
            guard let url = URL(string: "data:image/jpeg;base64,\(image.base64EncodedString())") else {
                continue
            }
            parts.append(.imageUrl(.init(url: url, detail: "auto")))
        }
        return .contentArray(parts)
    }

    func compactedCheckpointPrompt(_ checkpoint: AgentLoopCheckpoint) -> String {
        let lines = checkpoint.observations.map { item in
            let status = item.ok ? "成功" : "失败"
            return "- step \(item.step) \(item.toolName)（\(status)）：\(item.observation)"
        }
        return """
        系统续跑摘要（已完成步骤，请勿重复成功写入）：
        \(lines.joined(separator: "\n"))
        """
    }

    /// step ≥ 2 时去掉历史 user 消息中的图片 parts，只保留文字占位，降低重复 prefill。
    func clearHistoricalImageParts(
        in messages: inout [ChatCompletionParameters.Message]
    ) {
        guard messages.count >= 3 else { return }
        // 保留 system(0) 与最后一条当前 user；中间历史 user 去掉图片。
        let lastIndex = messages.count - 1
        for index in messages.indices where index > 0 && index < lastIndex {
            guard messages[index].role == ChatCompletionParameters.Message.Role.user.rawValue
            else { continue }
            if case let .contentArray(parts) = messages[index].content {
                let textParts = parts.compactMap { part -> String? in
                    if case let .text(text) = part {
                        return text
                    }
                    return nil
                }
                let joined = textParts.joined(separator: "\n")
                let note = joined.isEmpty
                    ? "（历史视觉帧已在后续步骤清除，仅保留文字上下文。）"
                    : joined + "\n（历史视觉帧已在后续步骤清除，仅保留文字上下文。）"
                messages[index] = ChatCompletionParameters.Message(
                    role: .user,
                    content: .text(note)
                )
            }
        }
    }

    func loadSkill(_ call: AgentToolCall) -> AgentToolResult {
        guard let skillID = call.arguments.skillID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !skillID.isEmpty
        else {
            return .failure("load_skill 缺少 skill_id。")
        }
        guard let skill = AgentSkillRegistry.descriptor(
            id: skillID,
            defaults: defaults
        ) else {
            let available = AgentSkillRegistry.allDescriptors(defaults: defaults)
                .map(\.id).joined(separator: "、")
            return .failure("未知 Skill：\(skillID)。可用 ID：\(available)。")
        }
        return .success(skill.markdown)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
