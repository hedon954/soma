import Foundation
import Observation
import Security
import SwiftData
import SwiftOpenAI

@MainActor
@Observable
final class AIService {
    @ObservationIgnored
    let defaults: UserDefaults
    @ObservationIgnored
    let apiKeyOverride: String?
    @ObservationIgnored
    var apiKeyCache: [String: String] = [:]
    @ObservationIgnored
    private let requestLoader: AIRequestLoader
    @ObservationIgnored
    let agentStreamLoader: AgentStreamLoader?
    @ObservationIgnored
    let streamDeadlinePolicy: AgentStreamDeadlinePolicy
    @ObservationIgnored
    let agentRetrySleeper: AgentRetrySleeper

    init(
        defaults: UserDefaults = .standard,
        apiKeyOverride: String? = nil,
        requestLoader: @escaping AIRequestLoader = { request in
            try await URLSession.shared.data(for: request)
        },
        agentStreamLoader: AgentStreamLoader? = nil,
        streamDeadlinePolicy: AgentStreamDeadlinePolicy = .init(),
        agentRetrySleeper: @escaping AgentRetrySleeper = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.defaults = defaults
        self.apiKeyOverride = apiKeyOverride
        self.requestLoader = requestLoader
        self.agentStreamLoader = agentStreamLoader
        self.streamDeadlinePolicy = streamDeadlinePolicy
        self.agentRetrySleeper = agentRetrySleeper
    }

    func fetchAvailableModels(
        provider: AIProvider,
        baseURL: String,
        apiKey: String
    ) async throws -> [AIModelInfo] {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            throw AIServiceError.missingAPIKey(provider.displayName)
        }
        guard let url = provider.endpoint(baseURL: baseURL, path: "models") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(normalizedKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await requestLoader(request)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw AIServiceError.remote(serviceErrorMessage(from: data, statusCode: http.statusCode))
        }

        let identifiers = modelIdentifiers(from: data)
        guard !identifiers.isEmpty else { throw AIServiceError.invalidResponse }
        let availableModels = identifiers
            .map {
                AIModelInfo(
                    id: $0.id,
                    status: $0.status,
                    multimodalAssessment: $0.multimodalAssessment
                )
            }
            .filter { model in
                guard let status = model.status?.lowercased() else { return true }
                return !["inactive", "disabled", "unavailable", "offline", "failed"]
                    .contains(where: status.contains)
            }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        guard !availableModels.isEmpty else {
            throw AIServiceError.remote("\(provider.displayName) 当前没有返回可用模型")
        }
        cacheMultimodalAssessments(
            availableModels,
            provider: provider,
            baseURL: baseURL
        )
        return availableModels
    }

    func generateImage(prompt: String) async throws -> Data {
        let provider = provider(for: .standard)
        let model = imageModel(for: provider)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw AIServiceError.imageGenerationUnsupported(provider.displayName)
        }
        let apiKey = apiKey(for: provider, tier: .standard)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(provider.displayName)
        }
        guard let url = provider.endpoint(
            baseURL: baseURL(for: provider, tier: .standard),
            path: "images/generations"
        ) else {
            throw AIServiceError.invalidURL
        }
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
            "quality": "medium",
            "output_format": "jpeg",
            "output_compression": 82
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        let (data, response) = try await requestLoader(request)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            if imageGenerationErrorCode(from: data) == "moderation_blocked" {
                throw AIServiceError.imageGenerationBlocked
            }
            throw AIServiceError.remote(
                serviceErrorMessage(from: data, statusCode: http.statusCode)
            )
        }
        guard let root = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let values = root["data"] as? [[String: Any]],
            let base64 = values.first?["b64_json"] as? String,
            let image = Data(base64Encoded: base64),
            !image.isEmpty
        else {
            throw AIServiceError.invalidResponse
        }
        return image
    }

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
                    _
                ) {
                    let endedAt = Date()
                    let reason = agentErrorDescription(error)
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
                    try accumulator.resolved(
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
                        action: resolved.local
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
            throw error
        }
    }

    private func applyResolvedToolCall(
        native: ToolCall,
        call: AgentToolCall,
        step: Int,
        state: inout AgentToolLoopState,
        execute: (AgentToolCall) async throws -> AgentToolResult,
        trace: ((AgentTraceEvent) -> Void)?
    ) async throws -> AgentToolResult {
        try Task.checkCancellation()
        let spanID = UUID()
        let startedAt = Date()
        let skill = call.arguments.skillID.flatMap {
            AgentSkillRegistry.descriptor(id: $0, defaults: defaults)
        }
        trace?(.span(AgentTraceSpan(
            id: spanID,
            step: step,
            kind: call.name == .loadSkill ? .skill : .tool,
            title: skill?.title ?? call.name.displayTitle,
            status: .running,
            startedAt: startedAt,
            endedAt: startedAt,
            input: AgentTraceText.json(call)
        )))

        let result: AgentToolResult
        let wasDeduplicated: Bool
        do {
            if call.name.isMutation,
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
                startedAt: startedAt,
                endedAt: endedAt,
                input: AgentTraceText.json(call),
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
            startedAt: startedAt,
            endedAt: endedAt,
            input: AgentTraceText.json(call),
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
    private func clearHistoricalImageParts(
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

    private func loadSkill(_ call: AgentToolCall) -> AgentToolResult {
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

    func agentErrorDescription(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.displayDescription
        }
        return error.localizedDescription
    }

    private func modelIdentifiers(
        from data: Data
    ) -> [(
        id: String,
        status: String?,
        multimodalAssessment: MultimodalCapabilityAssessment
    )] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var candidates = root["data"] as? [[String: Any]] ?? []
        if candidates.isEmpty {
            candidates = root["models"] as? [[String: Any]] ?? []
        }
        if candidates.isEmpty,
           let output = root["output"] as? [String: Any]
        {
            candidates = output["models"] as? [[String: Any]] ?? []
        }

        var seen = Set<String>()
        return candidates.compactMap { item in
            let identifier = (item["id"] as? String)
                ?? (item["model_name"] as? String)
                ?? (item["name"] as? String)
            guard let identifier, !identifier.isEmpty, seen.insert(identifier).inserted else {
                return nil
            }
            return (
                identifier,
                item["status"] as? String,
                catalogMultimodalAssessment(from: item)
            )
        }
    }

    /// 只接受模型目录响应中的显式能力字段。模型 ID、供应商和营销名称都不是证据。
    private func catalogMultimodalAssessment(
        from item: [String: Any]
    ) -> MultimodalCapabilityAssessment {
        let modalityPaths = [
            ["input_modalities"],
            ["inputModalities"],
            ["architecture", "input_modalities"],
            ["architecture", "inputModalities"],
            ["capabilities", "input_modalities"],
            ["capabilities", "inputModalities"]
        ]
        for path in modalityPaths {
            guard let modalities = stringList(value(at: path, in: item)) else { continue }
            return ModelCapability.assessment(
                inputModalities: modalities,
                source: path.joined(separator: ".")
            )
        }

        let booleanPaths = [
            ["supports_vision"],
            ["supportsVision"],
            ["capabilities", "vision"],
            ["capabilities", "multimodal"],
            ["capabilities", "supports_vision"],
            ["capabilities", "supportsVision"]
        ]
        for path in booleanPaths {
            guard let supported = value(at: path, in: item) as? Bool else { continue }
            return ModelCapability.assessment(
                explicitVisionSupport: supported,
                source: path.joined(separator: ".")
            )
        }
        return .unknown
    }

    private func value(
        at path: [String],
        in item: [String: Any]
    ) -> Any? {
        var current: Any = item
        for component in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[component]
            else {
                return nil
            }
            current = next
        }
        return current
    }

    private func stringList(_ value: Any?) -> [String]? {
        if let values = value as? [String] {
            return values
        }
        guard let value = value as? String else { return nil }
        return value.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func serviceErrorMessage(from data: Data, statusCode: Int) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = root["error"] as? [String: Any],
               let message = error["message"] as? String
            {
                return message
            }
            if let message = root["message"] as? String {
                return message
            }
        }
        if let text = String(data: data, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return String(text.prefix(240))
        }
        return "模型服务错误（\(statusCode)）"
    }

    private func imageGenerationErrorCode(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let error = root["error"] as? [String: Any]
        else {
            return nil
        }
        return error["code"] as? String
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
