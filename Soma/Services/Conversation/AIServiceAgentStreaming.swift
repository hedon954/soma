import Foundation
import SwiftOpenAI

/// 一步 LLM 推理开始时需要落到 Trace 与诊断日志的上下文。PRD 033：工具清单是排查
/// "模型说自己没有某个工具" 的关键证据，必须与 Span 一起记录。
struct AgentModelStepStart {
    var spanID: UUID
    var operationStep: Int
    var modelStep: Int
    var startedAt: Date
    var traceInput: String
    var route: AIModelRoute
    var historyExchangeCount: Int
    var historicalImageCount: Int
    var directVideoCount: Int
    var mediaMode: AgentMediaMode
    var messageCount: Int
    var exposedToolNames: [String]
    var selectedSkillID: String?
    var selectedShortcutID: String?
}

struct AgentStreamStepRequest {
    var tools: [ChatCompletionParameters.Tool]
    var model: String
    var provider: AIProvider
    var images: [Data]
    var videos: [AgentVideoInput]
    var hasVideo: Bool
    var step: Int
    var route: AIModelRoute
    var apiKey: String
    var userPrompt: String
    var textItemID: UUID
    var enforceFirstStepDeadline: Bool = false
}


extension AIService {
    func consumeAgentStepWithRetry(
        messages: inout [ChatCompletionParameters.Message],
        request: AgentStreamStepRequest,
        maximumRetryCount: Int = 0,
        videoFrameFallback: (() async -> [Data])?,
        trace: ((AgentTraceEvent) -> Void)?
    ) async throws -> AgentStreamOutcome {
        var requestAttempt = 0
        var activeVideos = request.step == 1 ? request.videos : []
        var mediaMode = initialMediaMode(
            images: request.images,
            videos: activeVideos,
            hasVideo: request.hasVideo
        )
        var fallbackReason: String?
        while true {
            requestAttempt += 1
            do {
                var streamed = try await consumeAgentStream(
                    parameters: ChatCompletionParameters(
                        messages: messages,
                        model: .custom(request.model),
                        store: request.provider == .openAI ? false : nil,
                        toolChoice: .auto,
                        tools: request.tools,
                        parallelToolCalls: true,
                        streamOptions: .init(includeUsage: true)
                    ),
                    videos: activeVideos,
                    mediaMode: mediaMode,
                    route: request.route,
                    apiKey: request.apiKey,
                    textItemID: request.textItemID,
                    enforceFirstDelta: request.enforceFirstStepDeadline,
                    trace: trace
                )
                streamed.requestAttempt = requestAttempt
                streamed.mediaMode = mediaMode
                streamed.fallbackReason = fallbackReason
                return streamed
            } catch let StreamingFailure.interrupted(
                error,
                passage,
                receivedMeaningfulDelta
            ) {
                guard !receivedMeaningfulDelta,
                      requestAttempt <= maximumRetryCount,
                      shouldRetryStream(error)
                else {
                    throw StreamingFailure.interrupted(
                        error,
                        passage: passage,
                        receivedMeaningfulDelta: receivedMeaningfulDelta
                    )
                }
                if !activeVideos.isEmpty,
                   let fallbackFrames = await videoFrameFallback?(),
                   !fallbackFrames.isEmpty
                {
                    activeVideos = []
                    mediaMode = .keyframes
                    fallbackReason = agentErrorDescription(error)
                    replaceCurrentUserImages(
                        in: &messages,
                        prompt: request.userPrompt,
                        images: fallbackFrames
                    )
                    trace?(.assistantTextDelta(
                        itemID: request.textItemID,
                        delta: "完整视频直传未在时限内响应，本次已切换为关键帧分析。\n\n"
                    ))
                }
                let retryNumber = requestAttempt
                let retryAt = Date()
                trace?(.span(AgentTraceSpan(
                    step: request.step,
                    kind: .model,
                    title: "模型步骤暂时失败，正在重试 \(retryNumber)/\(maximumRetryCount)",
                    status: .succeeded,
                    startedAt: retryAt,
                    endedAt: retryAt,
                    metadata: AgentTraceText.jsonObject([
                        "request_attempt": requestAttempt,
                        "next_request_attempt": requestAttempt + 1,
                        "media_mode": mediaMode.rawValue,
                        "fallback_reason": fallbackReason
                            .map { $0 as Any } ?? NSNull()
                    ])
                )))
                try await agentRetrySleeper(
                    AgentStepRetryPolicy.delay(forRetry: retryNumber)
                )
            }
        }
    }

    /// 建立流以后立即交给非 MainActor worker；主 actor 只接收已经合批的可见事件。
    func consumeAgentStream(
        parameters: ChatCompletionParameters,
        videos: [AgentVideoInput],
        mediaMode: AgentMediaMode,
        route: AIModelRoute,
        apiKey: String,
        textItemID: UUID,
        enforceFirstDelta: Bool,
        trace: ((AgentTraceEvent) -> Void)?
    ) async throws -> AgentStreamOutcome {
        let stream = try await agentStream(
            parameters: parameters,
            videos: videos,
            provider: route.provider,
            baseURL: route.baseURL,
            apiKey: apiKey
        )
        return try await AgentStreamWorker.consume(
            stream: stream,
            mediaMode: mediaMode,
            policy: ReActAgentPreference.deadlinePolicy(
                streamDeadlinePolicy,
                defaults: defaults
            ),
            enforceFirstDelta: enforceFirstDelta,
            textItemID: textItemID,
            project: { event in trace?(event) }
        )
    }

    /// 开始一步推理：写 running Span，并把绑定工具列表写进诊断日志。
    func announceModelStepStart(
        _ start: AgentModelStepStart,
        trace: ((AgentTraceEvent) -> Void)?
    ) {
        trace?(.span(AgentTraceSpan(
            id: start.spanID,
            step: start.operationStep,
            kind: .model,
            title: "LLM 推理",
            status: .running,
            startedAt: start.startedAt,
            endedAt: start.startedAt,
            input: start.modelStep == 1
                ? start.traceInput
                : "继续处理上一轮 assistant.tool_calls 与 role=tool 结果。",
            metadata: AgentTraceText.jsonObject([
                "history_exchange_count": start.historyExchangeCount,
                "history_image_count": start.historicalImageCount,
                "direct_video_count": start.directVideoCount,
                "media_mode": start.mediaMode.rawValue,
                "provider": start.route.provider.displayName,
                "model": start.route.model,
                "model_tier": start.route.tier.title,
                "routing_reason": start.route.reason,
                "message_count": start.messageCount,
                "exposed_tool_count": start.exposedToolNames.count,
                "exposed_tool_names": start.exposedToolNames,
                "selected_skill_id": start.selectedSkillID
                    .map { $0 as Any } ?? NSNull(),
                "selected_shortcut_id": start.selectedShortcutID
                    .map { $0 as Any } ?? NSNull(),
                "stream": true,
                "thinking": false
            ])
        )))
        AgentDiagnostics.modelRequest(
            step: start.operationStep,
            provider: start.route.provider.displayName,
            model: start.route.model,
            tier: start.route.tier.title,
            skillID: start.selectedSkillID,
            toolNames: start.exposedToolNames,
            messageCount: start.messageCount
        )
    }

    func modelSpanMetadata(
        history: [AgentConversationExchange],
        historicalImageCount: Int,
        directVideoCount: Int,
        route: AIModelRoute,
        streamed: AgentStreamOutcome,
        exposedToolNames: [String],
        startedAt: Date,
        endedAt: Date
    ) -> String {
        let usage = streamed.usage
        return AgentTraceText.jsonObject([
            "history_exchange_count": history.count,
            "history_image_count": historicalImageCount,
            // PRD 033：完成态 Span 也带上工具清单，回看历史 Trace 时不必再猜。
            "exposed_tool_names": exposedToolNames,
            "exposed_tool_count": exposedToolNames.count,
            "direct_video_count": directVideoCount,
            "media_mode": streamed.mediaMode.rawValue,
            "request_attempt": streamed.requestAttempt,
            "ttft_budget_ms": streamed.ttftBudgetMilliseconds,
            "fallback_reason": streamed.fallbackReason.map { $0 as Any } ?? NSNull(),
            "provider": route.provider.displayName,
            "model": route.model,
            "model_tier": route.tier.title,
            "stream": true,
            "thinking_ignored": streamed.ignoredReasoning,
            "prompt_tokens": usage?.promptTokens.map { $0 as Any } ?? NSNull(),
            "completion_tokens": usage?.completionTokens.map { $0 as Any } ?? NSNull(),
            "total_tokens": usage?.totalTokens.map { $0 as Any } ?? NSNull(),
            "cached_prompt_tokens": usage?.promptTokensDetails?
                .cachedTokens
                .map { $0 as Any } ?? NSNull(),
            "time_to_first_delta_ms": streamed.firstDeltaAt.map {
                milliseconds(from: startedAt, to: $0) as Any
            } ?? NSNull(),
            "stream_ms": milliseconds(from: startedAt, to: endedAt),
            "projection_ms": milliseconds(streamed.projectionSeconds),
            "tool_call_count": streamed.toolCalls.count
        ])
    }

    func agentStream(
        parameters: ChatCompletionParameters,
        videos: [AgentVideoInput],
        provider: AIProvider,
        baseURL: String,
        apiKey: String
    ) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error> {
        if let agentStreamLoader {
            return try await agentStreamLoader(parameters, provider, baseURL, apiKey)
        }
        let configuration = openAICompatibleConfiguration(baseURL: baseURL)
        let service = OpenAIServiceFactory.service(
            apiKey: apiKey,
            overrideBaseURL: configuration.origin,
            proxyPath: configuration.proxyPath,
            overrideVersion: configuration.version
        )
        if !videos.isEmpty {
            return try await directVideoStream(
                parameters: parameters,
                videos: videos,
                provider: provider,
                baseURL: baseURL,
                apiKey: apiKey
            )
        }
        return try await service.startStreamedChat(parameters: parameters)
    }

    func initialMediaMode(
        images: [Data],
        videos: [AgentVideoInput],
        hasVideo: Bool
    ) -> AgentMediaMode {
        if !videos.isEmpty {
            return .directVideo
        }
        if hasVideo {
            return .keyframes
        }
        return images.isEmpty ? .text : .images
    }

    func shouldRetryStream(_ error: Error) -> Bool {
        LLMOutageClassifier.isLoopRetryable(error)
    }

    func replaceCurrentUserImages(
        in messages: inout [ChatCompletionParameters.Message],
        prompt: String,
        images: [Data]
    ) {
        guard let index = messages.lastIndex(where: {
            $0.role == ChatCompletionParameters.Message.Role.user.rawValue
        }) else {
            return
        }
        messages[index] = ChatCompletionParameters.Message(
            role: .user,
            content: agentUserContent(
                prompt: prompt,
                images: images,
                maximumImageCount: 12
            )
        )
    }

    private func openAICompatibleConfiguration(
        baseURL: String
    ) -> (origin: String, proxyPath: String?, version: String) {
        var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        for suffix in ["/chat/completions", "/responses", "/models"]
            where normalized.hasSuffix(suffix)
        {
            normalized.removeLast(suffix.count)
            break
        }
        guard var components = URLComponents(string: normalized),
              components.scheme != nil,
              components.host != nil
        else {
            return (normalized, nil, "")
        }
        let pathComponents = components.path.split(separator: "/").map(String.init)
        let last = pathComponents.last ?? ""
        let version: String
        let proxyComponents: ArraySlice<String>
        if last.range(of: #"^v\d+(?:beta\d*)?$"#, options: .regularExpression) != nil {
            version = last
            proxyComponents = pathComponents.dropLast()
        } else {
            version = ""
            proxyComponents = pathComponents[...]
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        let origin = components.url?.absoluteString.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        ) ?? normalized
        let proxyPath = proxyComponents.isEmpty
            ? nil
            : proxyComponents.joined(separator: "/")
        return (origin, proxyPath, version)
    }

    private func milliseconds(from start: Date, to end: Date) -> Int {
        milliseconds(end.timeIntervalSince(start))
    }

    private func milliseconds(_ seconds: TimeInterval) -> Int {
        Int((max(0, seconds) * 1000).rounded())
    }
}
