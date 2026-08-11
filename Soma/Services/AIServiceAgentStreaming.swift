import Foundation
import SwiftOpenAI

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
}

extension AIService {
    func consumeAgentStepWithRetry(
        messages: inout [ChatCompletionParameters.Message],
        request: AgentStreamStepRequest,
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
                guard requestAttempt == 1,
                      !receivedMeaningfulDelta,
                      shouldRetryStream(error)
                else {
                    throw StreamingFailure.interrupted(
                        error,
                        passage: passage,
                        receivedMeaningfulDelta: receivedMeaningfulDelta
                    )
                }
                if !activeVideos.isEmpty {
                    guard let fallbackFrames = await videoFrameFallback?(),
                          !fallbackFrames.isEmpty
                    else {
                        throw StreamingFailure.interrupted(
                            error,
                            passage: passage,
                            receivedMeaningfulDelta: false
                        )
                    }
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
                let retryAt = Date()
                trace?(.span(AgentTraceSpan(
                    step: request.step,
                    kind: .model,
                    title: "首响应超时，正在重试 1/1",
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
            }
        }
    }

    /// 消费一步推理的流式响应。首个增量之前是请求与供应商排队，之后本机投影与流式读取
    /// 共用同一个 actor；deadline 在底层 stream 之上统一执行。
    func consumeAgentStream(
        parameters: ChatCompletionParameters,
        videos: [AgentVideoInput],
        mediaMode: AgentMediaMode,
        route: AIModelRoute,
        apiKey: String,
        textItemID: UUID,
        trace: ((AgentTraceEvent) -> Void)?
    ) async throws -> AgentStreamOutcome {
        var outcome = AgentStreamOutcome()
        var toolCallDeltas: [Int: AgentStreamingToolCall] = [:]
        do {
            let stream = try await agentStream(
                parameters: parameters,
                videos: videos,
                provider: route.provider,
                baseURL: route.baseURL,
                apiKey: apiKey
            )
            try await AgentStreamDeadline.consume(
                stream: stream,
                mode: mediaMode,
                policy: streamDeadlinePolicy
            ) { chunk in
                if let chunkUsage = chunk.usage {
                    outcome.usage = chunkUsage
                }
                var meaningful = false
                for choice in chunk.choices ?? [] where (choice.index ?? 0) == 0 {
                    guard let delta = choice.delta else { continue }
                    if outcome.firstDeltaAt == nil,
                       delta.content?.isEmpty == false || delta.toolCalls?.isEmpty == false
                    {
                        outcome.firstDeltaAt = Date()
                        meaningful = true
                    }
                    if let content = delta.content, !content.isEmpty {
                        outcome.passage += content
                        let projectionStartedAt = Date()
                        trace?(.assistantTextDelta(
                            itemID: textItemID,
                            delta: content
                        ))
                        outcome.projectionSeconds += Date()
                            .timeIntervalSince(projectionStartedAt)
                    }
                    if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
                        outcome.ignoredReasoning = true
                    }
                    for (position, toolDelta) in (delta.toolCalls ?? []).enumerated() {
                        let index = toolDelta.index ?? position
                        var accumulator = toolCallDeltas[index] ?? AgentStreamingToolCall()
                        accumulator.append(toolDelta)
                        toolCallDeltas[index] = accumulator
                    }
                }
                return meaningful
            }
        } catch {
            throw StreamingFailure.interrupted(
                error,
                passage: outcome.passage,
                receivedMeaningfulDelta: outcome.firstDeltaAt != nil
            )
        }
        outcome.toolCalls = toolCallDeltas.keys.sorted().compactMap { toolCallDeltas[$0] }
        outcome.ttftBudgetMilliseconds = milliseconds(
            streamDeadlinePolicy.ttft(for: mediaMode)
        )
        return outcome
    }

    func modelSpanMetadata(
        history: [AgentConversationExchange],
        historicalImageCount: Int,
        directVideoCount: Int,
        route: AIModelRoute,
        streamed: AgentStreamOutcome,
        startedAt: Date,
        endedAt: Date
    ) -> String {
        let usage = streamed.usage
        return AgentTraceText.jsonObject([
            "history_exchange_count": history.count,
            "history_image_count": historicalImageCount,
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
        error is AgentStreamTimeoutError || error is URLError
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
