import AVFoundation
import Foundation
import HealthKit
import Observation
import Security
import SwiftData
import SwiftOpenAI
import UIKit

typealias AIRequestLoader = (URLRequest) async throws -> (Data, URLResponse)
typealias AgentStreamLoader = (
    ChatCompletionParameters,
    AIProvider,
    String,
    String
) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error>

struct HealthKitImportResult: Equatable {
    let workoutCount: Int
    let bodyCount: Int
    let deletedCount: Int

    var summary: String {
        var parts = [
            "新增 \(workoutCount) 条训练",
            "\(bodyCount) 条体重记录"
        ]
        if deletedCount > 0 {
            parts.append("移除 \(deletedCount) 条来源已删除记录")
        }
        return parts.joined(separator: "、")
    }
}

@MainActor
enum HealthKitImporter {
    private struct ChangeBatch {
        let added: [HKSample]
        let deleted: [HKDeletedObject]
        let anchor: HKQueryAnchor?
    }

    private enum Stream {
        static let workouts = "workouts"
        static let bodyMass = "bodyMass"
    }

    private static let sourceID = "healthkit"
    private static let sourceName = "Apple 健康"
    private static let store = HKHealthStore()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    static func requestAuthorizationAndImport(
        into context: ModelContext
    ) async throws -> HealthKitImportResult {
        guard isAvailable else {
            throw HealthKitImportError.unavailable
        }
        guard
            let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass),
            let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            throw HealthKitImportError.typesUnavailable
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            bodyMass,
            activeEnergy
        ]
        try await store.requestAuthorization(toShare: [], read: readTypes)

        let workoutCursor = syncCursor(for: Stream.workouts, in: context)
        let bodyCursor = syncCursor(for: Stream.bodyMass, in: context)
        async let workoutChanges = changes(
            of: HKObjectType.workoutType(),
            after: decodeAnchor(workoutCursor?.cursorData)
        )
        async let bodyChanges = changes(
            of: bodyMass,
            after: decodeAnchor(bodyCursor?.cursorData)
        )
        let (resolvedWorkoutChanges, resolvedBodyChanges) = try await (
            workoutChanges,
            bodyChanges
        )

        return try importSamples(
            workoutChanges: resolvedWorkoutChanges,
            bodyChanges: resolvedBodyChanges,
            activeEnergyType: activeEnergy,
            workoutCursor: workoutCursor,
            bodyCursor: bodyCursor,
            into: context
        )
    }

    private static var oneYearAgo: Date {
        Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
    }

    private static func changes(
        of type: HKSampleType,
        after anchor: HKQueryAnchor?
    ) async throws -> ChangeBatch {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: oneYearAgo,
                end: .now,
                options: .strictStartDate
            )
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deletedObjects, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ChangeBatch(
                        added: samples ?? [],
                        deleted: deletedObjects ?? [],
                        anchor: newAnchor
                    ))
                }
            }
            store.execute(query)
        }
    }

    private static func importSamples(
        workoutChanges: ChangeBatch,
        bodyChanges: ChangeBatch,
        activeEnergyType: HKQuantityType,
        workoutCursor: ExternalSyncCursor?,
        bodyCursor: ExternalSyncCursor?,
        into context: ModelContext
    ) throws -> HealthKitImportResult {
        let existingWorkouts = try context.fetch(FetchDescriptor<WorkoutEntry>())
        let existingBodyEntries = try context.fetch(FetchDescriptor<BodyEntry>())
        var existingWorkoutIDs = Set(
            existingWorkouts
                .filter { $0.externalSource == sourceName }
                .compactMap(\.externalID)
        )
        var existingBodyIDs = Set(
            existingBodyEntries
                .filter { $0.externalSource == sourceName }
                .compactMap(\.externalID)
        )
        let deletedWorkoutIDs = Set(workoutChanges.deleted.map(\.uuid.uuidString))
        let deletedBodyIDs = Set(bodyChanges.deleted.map(\.uuid.uuidString))
        var workoutCount = 0
        var bodyCount = 0

        for workout in workoutChanges.added.compactMap({ $0 as? HKWorkout }) {
            let externalID = workout.uuid.uuidString
            guard
                !existingWorkoutIDs.contains(externalID),
                !deletedWorkoutIDs.contains(externalID)
            else { continue }
            let energy = workout
                .statistics(for: activeEnergyType)?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())
            context.insert(WorkoutEntry(
                date: workout.startDate,
                exercise: workoutTitle(workout.workoutActivityType),
                durationMinutes: max(Int((workout.duration / 60).rounded()), 1),
                notes: "从 Apple 健康导入",
                estimatedCalories: energy.map { Int($0.rounded()) },
                calorieDurationMinutes: workout.duration / 60,
                calorieDurationEstimated: false,
                externalSource: sourceName,
                externalID: externalID
            ))
            existingWorkoutIDs.insert(externalID)
            workoutCount += 1
        }

        for sample in bodyChanges.added.compactMap({ $0 as? HKQuantitySample }) {
            let externalID = sample.uuid.uuidString
            guard
                !existingBodyIDs.contains(externalID),
                !deletedBodyIDs.contains(externalID)
            else { continue }
            let weight = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            guard weight > 0 else { continue }
            context.insert(BodyEntry(
                date: sample.startDate,
                weight: weight,
                notes: "从 Apple 健康导入",
                analysis: "",
                externalSource: sourceName,
                externalID: externalID
            ))
            existingBodyIDs.insert(externalID)
            bodyCount += 1
        }

        var deletedCount = 0

        for workout in existingWorkouts where
            workout.externalSource == sourceName
            && workout.externalID.map(deletedWorkoutIDs.contains) == true
        {
            context.delete(workout)
            deletedCount += 1
        }
        for bodyEntry in existingBodyEntries where
            bodyEntry.externalSource == sourceName
            && bodyEntry.externalID.map(deletedBodyIDs.contains) == true
        {
            context.delete(bodyEntry)
            deletedCount += 1
        }

        try updateCursor(
            workoutCursor,
            stream: Stream.workouts,
            anchor: workoutChanges.anchor,
            in: context
        )
        try updateCursor(
            bodyCursor,
            stream: Stream.bodyMass,
            anchor: bodyChanges.anchor,
            in: context
        )
        try context.save()
        return HealthKitImportResult(
            workoutCount: workoutCount,
            bodyCount: bodyCount,
            deletedCount: deletedCount
        )
    }

    private static func syncCursor(
        for stream: String,
        in context: ModelContext
    ) -> ExternalSyncCursor? {
        let descriptor = FetchDescriptor<ExternalSyncCursor>(
            predicate: #Predicate {
                $0.source == sourceID && $0.stream == stream
            }
        )
        return try? context.fetch(descriptor).first
    }

    private static func decodeAnchor(_ data: Data?) -> HKQueryAnchor? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: HKQueryAnchor.self,
            from: data
        )
    }

    private static func updateCursor(
        _ existingCursor: ExternalSyncCursor?,
        stream: String,
        anchor: HKQueryAnchor?,
        in context: ModelContext
    ) throws {
        guard let anchor else { return }
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: anchor,
            requiringSecureCoding: true
        )
        if let existingCursor {
            existingCursor.cursorData = data
            existingCursor.updatedAt = .now
        } else {
            context.insert(ExternalSyncCursor(
                source: sourceID,
                stream: stream,
                cursorData: data
            ))
        }
    }

    private static func workoutTitle(_ activity: HKWorkoutActivityType) -> String {
        switch activity {
        case .traditionalStrengthTraining: "力量训练"
        case .functionalStrengthTraining: "功能性力量训练"
        case .highIntensityIntervalTraining: "高强度间歇训练"
        case .running: "跑步"
        case .walking: "步行"
        case .cycling: "骑行"
        case .swimming: "游泳"
        case .hiking: "徒步"
        case .yoga: "瑜伽"
        case .coreTraining: "核心训练"
        case .crossTraining: "交叉训练"
        case .stairClimbing: "爬楼训练"
        default: "Apple 健康训练"
        }
    }
}

enum HealthKitImportError: LocalizedError {
    case unavailable
    case typesUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "当前设备不支持 Apple 健康数据"
        case .typesUnavailable:
            "系统没有提供所需的健康数据类型"
        }
    }
}

enum AIServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case remote(String)
    case missingAPIKey(String)
    case multimodalUnsupported(provider: String, model: String)
    case multimodalRequestFailed(provider: String, model: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "模型服务地址无效"
        case .invalidResponse: "模型返回了无法识别的响应"
        case let .remote(message): message
        case let .missingAPIKey(provider): "请先在设置中保存 \(provider) 的 API Key"
        case let .multimodalUnsupported(provider, model):
            "\(provider) 的 \(model) 不支持图片或视频分析。请切换到支持视觉的模型，文字对话仍可继续使用。"
        case let .multimodalRequestFailed(provider, model, reason):
            "\(provider) 的 \(model) 没能处理这次图片或视频：\(reason)"
        }
    }
}

@MainActor
@Observable
final class AIService {
    @ObservationIgnored
    let defaults: UserDefaults
    @ObservationIgnored
    let apiKeyOverride: String?
    @ObservationIgnored
    private let requestLoader: AIRequestLoader
    @ObservationIgnored
    private let agentStreamLoader: AgentStreamLoader?

    init(
        defaults: UserDefaults = .standard,
        apiKeyOverride: String? = nil,
        requestLoader: @escaping AIRequestLoader = { request in
            try await URLSession.shared.data(for: request)
        },
        agentStreamLoader: AgentStreamLoader? = nil
    ) {
        self.defaults = defaults
        self.apiKeyOverride = apiKeyOverride
        self.requestLoader = requestLoader
        self.agentStreamLoader = agentStreamLoader
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
                    multimodalSupport: ModelCapability.multimodalSupport(provider: provider, model: $0.id)
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
        return availableModels
    }

    func interpretConversation(
        text: String,
        images: [Data],
        hasVideo: Bool,
        context _: String,
        allowDemoFallback: Bool = true
    ) async throws -> ConversationResult {
        try await simulate()
        return allowDemoFallback
            ? localConversationResult(text: text, hasMedia: !images.isEmpty, hasVideo: hasVideo)
            : strictLocalConversationResult(text: text, hasMedia: !images.isEmpty, hasVideo: hasVideo)
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
        trace: ((AgentTraceEvent) -> Void)? = nil,
        execute: (AgentToolCall) -> AgentToolResult
    ) async throws -> AgentOutcome {
        let routing = try resolvedRoute(
            requested: requestedRoute,
            text: text,
            hasMedia: !images.isEmpty,
            hasVideo: hasVideo
        )
        let selectedRoute = routing.route
        let provider = selectedRoute.provider
        let model = selectedRoute.model
        let baseURL = selectedRoute.baseURL
        let key = routing.apiKey
        let support = ModelCapability.multimodalSupport(provider: provider, model: model)
        let historicalImageCount = history.reduce(0) { $0 + $1.images.count }
        let hasVisualInput = !images.isEmpty
            || !videos.isEmpty
            || historicalImageCount > 0
        if hasVisualInput, support == .unsupported {
            throw AIServiceError.multimodalUnsupported(provider: provider.displayName, model: model)
        }

        let systemPrompt = ReActAgentPrompt.system(defaults: defaults)
        let userPrompt = ReActAgentPrompt.user(
            text: text,
            context: context,
            imageCount: images.count,
            hasVideo: hasVideo,
            imageAttachmentCount: imageAttachmentCount,
            videoAttachmentCount: videoAttachmentCount
        )
        var messages = agentInitialMessages(
            systemPrompt: systemPrompt,
            history: history,
            userPrompt: userPrompt,
            currentImages: images
        )
        let traceInput = AgentTraceText.modelInput(
            systemPrompt: systemPrompt,
            history: history,
            userPrompt: userPrompt
        )
        let tools = AgentToolName.allCases.map(\.chatTool)
        var observations: [AgentObservation] = []
        var executedMutations = Set<String>()
        var assistantPassages: [String] = []

        do {
            for step in 1 ... 8 {
                try Task.checkCancellation()
                let modelSpanID = UUID()
                let textItemID = UUID()
                let modelStartedAt = Date()
                trace?(.span(AgentTraceSpan(
                    id: modelSpanID,
                    step: step,
                    kind: .model,
                    title: "LLM 推理",
                    status: .running,
                    startedAt: modelStartedAt,
                    endedAt: modelStartedAt,
                    input: step == 1
                        ? traceInput
                        : "继续处理上一轮 assistant.tool_calls 与 role=tool 结果。",
                    metadata: AgentTraceText.jsonObject([
                        "history_exchange_count": history.count,
                        "history_image_count": historicalImageCount,
                        "direct_video_count": videos.count,
                        "provider": provider.displayName,
                        "model": model,
                        "model_tier": selectedRoute.tier.title,
                        "routing_reason": selectedRoute.reason,
                        "message_count": messages.count,
                        "stream": true,
                        "thinking": false
                    ])
                )))

                var passage = ""
                var toolCallDeltas: [Int: AgentStreamingToolCall] = [:]
                var usage: ChatUsage?
                var ignoredReasoning = false

                do {
                    let parameters = ChatCompletionParameters(
                        messages: messages,
                        model: .custom(model),
                        store: provider == .openAI ? false : nil,
                        toolChoice: .auto,
                        tools: tools,
                        parallelToolCalls: false,
                        streamOptions: .init(includeUsage: true)
                    )
                    let stream = try await agentStream(
                        parameters: parameters,
                        videos: videos,
                        provider: provider,
                        baseURL: baseURL,
                        apiKey: key
                    )
                    for try await chunk in stream {
                        try Task.checkCancellation()
                        if let chunkUsage = chunk.usage {
                            usage = chunkUsage
                        }
                        for choice in chunk.choices ?? [] where (choice.index ?? 0) == 0 {
                            guard let delta = choice.delta else { continue }
                            if let content = delta.content, !content.isEmpty {
                                passage += content
                                trace?(.assistantTextDelta(
                                    itemID: textItemID,
                                    delta: content
                                ))
                            }
                            if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
                                ignoredReasoning = true
                            }
                            for (position, toolDelta) in (delta.toolCalls ?? []).enumerated() {
                                let index = toolDelta.index ?? position
                                var accumulator = toolCallDeltas[index] ?? AgentStreamingToolCall()
                                accumulator.append(toolDelta)
                                toolCallDeltas[index] = accumulator
                            }
                        }
                    }
                } catch {
                    let endedAt = Date()
                    let reason = agentErrorDescription(error)
                    trace?(.span(AgentTraceSpan(
                        id: modelSpanID,
                        step: step,
                        kind: .model,
                        title: "LLM 推理",
                        status: error is CancellationError ? .cancelled : .failed,
                        startedAt: modelStartedAt,
                        endedAt: endedAt,
                        input: step == 1
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

                let modelEndedAt = Date()
                if !passage.isEmpty {
                    trace?(.assistantTextCompleted(
                        itemID: textItemID,
                        at: modelEndedAt
                    ))
                }
                let orderedDeltas = toolCallDeltas.keys.sorted().compactMap { toolCallDeltas[$0] }
                trace?(.span(AgentTraceSpan(
                    id: modelSpanID,
                    step: step,
                    kind: .model,
                    title: "LLM 推理",
                    status: .succeeded,
                    startedAt: modelStartedAt,
                    endedAt: modelEndedAt,
                    input: step == 1
                        ? traceInput
                        : "继续处理上一轮工具结果。",
                    output: passage.nilIfEmpty ?? (
                        orderedDeltas.isEmpty
                            ? nil
                            : "生成 \(orderedDeltas.count) 个原生 tool_call。"
                    ),
                    metadata: AgentTraceText.jsonObject([
                        "history_exchange_count": history.count,
                        "history_image_count": historicalImageCount,
                        "direct_video_count": videos.count,
                        "provider": provider.displayName,
                        "model": model,
                        "model_tier": selectedRoute.tier.title,
                        "stream": true,
                        "thinking_ignored": ignoredReasoning,
                        "prompt_tokens": usage?.promptTokens.map { $0 as Any } ?? NSNull(),
                        "completion_tokens": usage?.completionTokens.map { $0 as Any } ?? NSNull(),
                        "total_tokens": usage?.totalTokens.map { $0 as Any } ?? NSNull(),
                        "tool_call_count": orderedDeltas.count
                    ])
                )))

                if !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    assistantPassages.append(passage)
                }

                guard !orderedDeltas.isEmpty else {
                    let finalAnswer = passage
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .nilIfEmpty
                        ?? assistantPassages.last?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? ""
                    guard !finalAnswer.isEmpty else {
                        throw ReActAgentError.emptyResponse
                    }
                    let completedAt = Date()
                    trace?(.span(AgentTraceSpan(
                        kind: .output,
                        title: "最终回复",
                        status: .succeeded,
                        startedAt: completedAt,
                        endedAt: completedAt,
                        output: finalAnswer
                    )))
                    trace?(.completed(answer: finalAnswer, at: completedAt))
                    return AgentOutcome(finalAnswer: finalAnswer, observations: observations)
                }

                let resolvedCalls = try orderedDeltas.enumerated().map { position, accumulator in
                    try accumulator.resolved(fallbackID: "soma_call_\(step)_\(position)")
                }
                messages.append(ChatCompletionParameters.Message(
                    role: .assistant,
                    content: .text(passage),
                    toolCalls: resolvedCalls.map(\.native)
                ))

                for resolved in resolvedCalls {
                    try Task.checkCancellation()
                    let call = resolved.local
                    let spanID = UUID()
                    let startedAt = Date()
                    let skill = call.arguments.skillID.flatMap(AgentSkill.init(rawValue:))
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
                    if call.name.isMutation,
                       !executedMutations.insert(call.signature).inserted
                    {
                        result = .success("相同写入操作已经执行，本次重复调用已忽略。")
                        wasDeduplicated = true
                    } else if call.name == .loadSkill {
                        result = loadSkill(call)
                        wasDeduplicated = false
                    } else {
                        result = execute(call)
                        wasDeduplicated = false
                    }
                    let endedAt = Date()
                    trace?(.span(AgentTraceSpan(
                        id: spanID,
                        step: step,
                        kind: call.name == .loadSkill ? .skill : .tool,
                        title: skill?.title ?? call.name.displayTitle,
                        status: result.ok ? .succeeded : .failed,
                        startedAt: startedAt,
                        endedAt: endedAt,
                        input: AgentTraceText.json(call),
                        output: AgentTraceText.json(result),
                        metadata: AgentTraceText.jsonObject([
                            "tool_call_id": resolved.native.id ?? "",
                            "deduplicated": wasDeduplicated,
                            "skill_id": call.arguments.skillID.map { $0 as Any } ?? NSNull(),
                            "skill_customized": skill
                                .map { $0.isCustomized(in: defaults) as Any } ?? NSNull(),
                            "record_type": result.recordType
                                .map { $0.rawValue as Any } ?? NSNull()
                        ]),
                        errorMessage: result.ok ? nil : result.observation
                    )))
                    observations.append(AgentObservation(step: step, action: call, result: result))
                    messages.append(ChatCompletionParameters.Message(
                        role: .tool,
                        content: .text(AgentTraceText.json(result)),
                        toolCallID: resolved.native.id
                    ))
                }
            }
            throw ReActAgentError.stepLimit
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

    private func agentUserContent(
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

    private func agentInitialMessages(
        systemPrompt: String,
        history: [AgentConversationExchange],
        userPrompt: String,
        currentImages: [Data]
    ) -> [ChatCompletionParameters.Message] {
        var messages = [
            ChatCompletionParameters.Message(role: .system, content: .text(systemPrompt))
        ]
        for exchange in history {
            let historicalPrompt = ReActAgentPrompt.historicalUser(
                text: exchange.userText,
                imageCount: exchange.images.count,
                imageAttachmentCount: exchange.imageAttachmentCount,
                videoAttachmentCount: exchange.videoAttachmentCount
            )
            messages.append(ChatCompletionParameters.Message(
                role: .user,
                content: agentUserContent(
                    prompt: historicalPrompt,
                    images: exchange.images,
                    maximumImageCount: exchange.images.count
                )
            ))
            guard let assistantText = exchange.assistantText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            else {
                continue
            }
            messages.append(ChatCompletionParameters.Message(
                role: .assistant,
                content: .text(assistantText)
            ))
        }
        messages.append(ChatCompletionParameters.Message(
            role: .user,
            content: agentUserContent(
                prompt: userPrompt,
                images: currentImages,
                maximumImageCount: 12
            )
        ))
        return messages
    }

    private func agentStream(
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
            let direct = try await directVideoStream(
                parameters: parameters,
                videos: videos,
                provider: provider,
                baseURL: baseURL,
                apiKey: apiKey
            )
            return AsyncThrowingStream { continuation in
                Task {
                    var emittedChunk = false
                    do {
                        for try await chunk in direct {
                            emittedChunk = true
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    } catch {
                        guard !emittedChunk else {
                            continuation.finish(throwing: error)
                            return
                        }
                        do {
                            let fallback = try await service.startStreamedChat(
                                parameters: parameters
                            )
                            for try await chunk in fallback {
                                continuation.yield(chunk)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }
            }
        }
        return try await service.startStreamedChat(parameters: parameters)
    }

    private func openAICompatibleConfiguration(
        baseURL: String
    ) -> (origin: String, proxyPath: String?, version: String) {
        var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        for suffix in ["/chat/completions", "/responses", "/models"] where normalized.hasSuffix(suffix) {
            normalized.removeLast(suffix.count)
            break
        }

        guard var components = URLComponents(string: normalized),
              components.scheme != nil,
              components.host != nil
        else {
            return (normalized, nil, "")
        }
        let pathComponents = components.path
            .split(separator: "/")
            .map(String.init)
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
        let origin = components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            ?? normalized
        let proxyPath = proxyComponents.isEmpty ? nil : proxyComponents.joined(separator: "/")
        return (origin, proxyPath, version)
    }

    private func loadSkill(_ call: AgentToolCall) -> AgentToolResult {
        guard let skillID = call.arguments.skillID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !skillID.isEmpty
        else {
            return .failure("load_skill 缺少 skill_id。")
        }
        guard let skill = AgentSkill(rawValue: skillID) else {
            let available = AgentSkill.allCases.map(\.rawValue).joined(separator: "、")
            return .failure("未知 Skill：\(skillID)。可用 ID：\(available)。")
        }
        return .success(skill.text(in: defaults))
    }

    private func agentErrorDescription(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.displayDescription
        }
        return error.localizedDescription
    }

    private func localConversationResult(
        text: String,
        hasMedia: Bool,
        hasVideo: Bool
    ) -> ConversationResult {
        let normalized = text.lowercased()

        if normalized.contains("切换") || normalized.contains("现在在") {
            let name = normalized.contains("公司") ? "公司健身房" : "我的健身房"
            return ConversationResult(
                intent: .switchGym,
                reply: "好的，接下来的器械和训练建议都会基于\(name)。",
                gymName: name
            )
        }

        if hasVideo
            || compactSetAndRep(in: normalized) != nil
            || containsAny(normalized, ["俯卧撑", "深蹲", "卧推", "硬拉", "下拉", "训练", "组", "次"])
        {
            let exercise = firstMatch(
                in: text,
                candidates: ["杠铃深蹲", "俯卧撑", "深蹲", "卧推", "硬拉", "高位下拉", "哑铃推举"]
            ) ?? "训练"
            let compact = compactSetAndRep(in: normalized)
            let sets = integer(before: "组", in: text) ?? compact?.sets
            let reps = integer(before: "次", in: text) ?? compact?.reps
            let statedWeight = number(beforeAny: ["kg", "公斤"], in: normalized)
            let weight = statedWeight ?? (normalized.contains("自重") ? 0 : nil)
            let explicitSetEntries = LocalWorkoutParser.setEntries(in: normalized)
            let setEntries = explicitSetEntries ?? sets.map { count in
                (0 ..< count).map { _ in
                    WorkoutSetEvidence(reps: reps, externalWeightKG: weight)
                }
            }
            let restSeconds = containsAny(normalized, ["间歇", "休息"])
                ? integer(before: "秒", in: normalized)
                : nil
            let workout = ConversationWorkout(
                exercise: exercise,
                setEntries: setEntries,
                sets: sets,
                reps: reps,
                weight: weight,
                restSeconds: restSeconds,
                durationMinutes: nil,
                formScore: nil,
                intensity: nil,
                feedback: nil
            )
            let prescription = LocalWorkoutParser.description(workout)
            return ConversationResult(
                intent: .workout,
                reply: "已记录：\(prescription)。没有提供的训练数据保持为空。",
                workout: workout
            )
        }

        if containsAny(normalized, ["体重", "体脂", "腰围", "体型", "秤"]) {
            let weight = number(beforeAny: ["kg", "公斤"], in: normalized)
            let body = BodyAnalysis(
                estimatedWeight: weight,
                estimatedBodyFat: nil,
                postureNote: "已把这次数据加入长期趋势。",
                safetyNote: "照片估算只用于趋势参考，不替代专业检测。"
            )
            let reply = weight.map {
                "已记录体重 \(String(format: "%.1f", $0))kg。"
            } ?? "已记录这次身体资料；未提供体重，因此体重保持为空。"
            return ConversationResult(
                intent: .body,
                reply: reply,
                body: body
            )
        }

        if containsAny(normalized, ["健身房", "器械", "哑铃", "跑步机", "深蹲架"]) {
            let name = normalized.contains("公司") ? "公司健身房" : "我的健身房"
            let analysis = GymAnalysis(
                summary: "已从照片中更新可用器械。",
                equipment: [
                    EquipmentSuggestion(name: "深蹲架", category: "力量", capabilities: "深蹲、卧推、肩推", confidence: 0.93),
                    EquipmentSuggestion(name: "可调哑铃", category: "自由重量", capabilities: "全身自由重量训练", confidence: 0.9)
                ]
            )
            return ConversationResult(
                intent: .gym,
                reply: "已更新\(name)：识别到 \(analysis.equipment.map(\.name).joined(separator: "、"))。之后的动作推荐会自动使用这些器械。",
                gymName: name,
                gym: analysis
            )
        }

        if hasMedia || containsAny(normalized, ["吃", "饭", "早餐", "午餐", "晚餐", "大卡", "蛋白"]) {
            let meal = MealAnalysis(
                title: "鸡胸肉杂粮饭",
                calories: 568,
                protein: 46,
                carbs: 61,
                fat: 15,
                confidence: 0.84,
                note: "按照片中的常见份量估算"
            )
            return ConversationResult(
                intent: .meal,
                reply: "已记录这餐：约 568 kcal，蛋白质 46g。份量存在视觉误差，我会用长期趋势而不是单次数字评价饮食。",
                meal: meal
            )
        }

        return ConversationResult(
            intent: .coach,
            reply: "按你最近的记录，今天主动作保留 2–3 次余力即可。你也可以直接发一张食物、器械、体重秤照片或训练视频，我会自动识别并记录。"
        )
    }

    private func strictLocalConversationResult(
        text: String,
        hasMedia: Bool,
        hasVideo: Bool
    ) -> ConversationResult {
        guard !hasMedia, !hasVideo else {
            return ConversationResult(
                intent: .coach,
                reply: "个人数据空间不会使用演示识别结果。请在设置中启用远程 ReAct Agent 后再解析照片或视频；原始附件不会被写成格式化记录。"
            )
        }

        let parsed = localConversationResult(
            text: text,
            hasMedia: false,
            hasVideo: false
        )
        switch parsed.intent {
        case .workout:
            guard let workout = parsed.workout,
                  workout.exercise != "训练"
                  || workout.setEntries?.isEmpty == false
                  || workout.sets != nil
                  || workout.reps != nil
                  || workout.weight != nil
            else {
                return unconfiguredPersonalAIReply
            }
            return parsed
        case .body:
            return parsed.body?.estimatedWeight == nil
                ? unconfiguredPersonalAIReply
                : parsed
        case .switchGym, .coach:
            return parsed
        case .gym, .meal:
            return unconfiguredPersonalAIReply
        }
    }

    private var unconfiguredPersonalAIReply: ConversationResult {
        ConversationResult(
            intent: .coach,
            reply: "个人数据空间不会写入演示估算。请在设置中配置并启用远程 ReAct Agent，或直接提供可明确提取的训练、体重数字。"
        )
    }

    private func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains { text.contains($0) }
    }

    private func firstMatch(in text: String, candidates: [String]) -> String? {
        candidates.first { text.contains($0) }
    }

    private func integer(before suffix: String, in text: String) -> Int? {
        guard let range = text.range(of: #"(\d+)\s*\#(suffix)"#, options: .regularExpression) else { return nil }
        return Int(text[range].filter(\.isNumber))
    }

    private func number(beforeAny suffixes: [String], in text: String) -> Double? {
        for suffix in suffixes {
            guard let range = text.range(
                of: #"(\d+(?:\.\d+)?)\s*\#(suffix)"#,
                options: .regularExpression
            ) else { continue }
            let value = text[range].replacingOccurrences(of: suffix, with: "")
                .trimmingCharacters(in: .whitespaces)
            if let number = Double(value) {
                return number
            }
        }
        return nil
    }

    private func compactSetAndRep(in text: String) -> (sets: Int, reps: Int)? {
        guard let range = text.range(
            of: #"(\d+)\s*[x×*]\s*(\d+)"#,
            options: .regularExpression
        ) else { return nil }
        let values = text[range]
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        guard values.count == 2 else { return nil }
        return (sets: values[1], reps: values[0])
    }

    private func simulate() async throws {
        try await Task.sleep(for: .milliseconds(650))
    }

    private func modelIdentifiers(from data: Data) -> [(id: String, status: String?)] {
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
            return (identifier, item["status"] as? String)
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
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum KeychainStore {
    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Soma",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Soma",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveData(_ data: Data, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Soma",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func readData(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Soma",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Soma",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum MediaStore {
    static func saveImage(_ data: Data) throws -> String {
        try save(data: normalizedJPEG(data), extension: "jpg")
    }

    static func saveVideo(from source: URL) throws -> String {
        let destination = try mediaDirectory()
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension.isEmpty ? "mov" : source.pathExtension)
        try FileManager.default.copyItem(at: source, to: destination)
        return storedPath(for: destination)
    }

    static func image(at path: String?) -> UIImage? {
        guard let url = url(at: path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func url(at path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let original = URL(fileURLWithPath: path)
        if path.hasPrefix("/"), FileManager.default.fileExists(atPath: original.path) {
            return original
        }

        guard let media = try? mediaDirectory() else { return nil }
        let filename = original.lastPathComponent
        let relocated = media.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: relocated.path) ? relocated : nil
    }

    static func saveRestoredMedia(
        _ data: Data,
        fileExtension: String
    ) throws -> String {
        let sanitized = fileExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return try save(
            data: data,
            extension: String((sanitized.isEmpty ? "bin" : sanitized).prefix(10))
        )
    }

    @discardableResult
    static func removeStoredFile(at path: String) -> Bool {
        guard let media = try? mediaDirectory() else { return false }
        let filename = URL(fileURLWithPath: path).lastPathComponent
        guard !filename.isEmpty else { return false }
        let target = media.appending(path: filename)
        guard target.deletingLastPathComponent().standardizedFileURL
            == media.standardizedFileURL,
            FileManager.default.fileExists(atPath: target.path)
        else {
            return false
        }
        do {
            try FileManager.default.removeItem(at: target)
            return true
        } catch {
            return false
        }
    }

    static func allStoredPaths() -> Set<String> {
        guard let media = try? mediaDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: media,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              )
        else {
            return []
        }
        return Set(urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true ? storedPath(for: url) : nil
        })
    }

    private static func save(data: Data, extension ext: String) throws -> String {
        let url = try mediaDirectory()
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return storedPath(for: url)
    }

    private static func mediaDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let media = root.appendingPathComponent("PrivateMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        return media
    }

    private static func storedPath(for url: URL) -> String {
        "PrivateMedia/\(url.lastPathComponent)"
    }

    private static func normalizedJPEG(_ data: Data) -> Data {
        guard let image = UIImage(data: data),
              let resized = image.preparingThumbnail(of: CGSize(width: 1600, height: 1600)),
              let jpeg = resized.jpegData(compressionQuality: 0.82) else { return data }
        return jpeg
    }
}

enum VideoFrameExtractor {
    static func frames(from url: URL, count: Int = 4) async -> [Data] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              duration.seconds.isFinite,
              duration.seconds > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        var frames: [Data] = []
        for index in 1 ... count {
            let second = duration.seconds * Double(index) / Double(count + 1)
            let time = CMTime(seconds: second, preferredTimescale: 600)
            if let image = try? await generator.image(at: time).image,
               let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.72)
            {
                frames.append(data)
            }
        }
        return frames
    }
}

@MainActor
enum DemoSeeder {
    static func seedIfNeeded(_ context: ModelContext) {
        seedTraceLogsIfNeeded(in: context)
        backfillDemoProfileAndCaloriesIfNeeded(in: context)
        backfillDemoAgentTurnIfNeeded(in: context)
        let descriptor = FetchDescriptor<GymProfile>()
        let existingGyms = (try? context.fetch(descriptor)) ?? []
        guard existingGyms.isEmpty else {
            backfillBundledMediaIfNeeded(in: context, gyms: existingGyms)
            return
        }

        let media = installBundledMedia()

        let gym = GymProfile(
            name: "我的健身房",
            notes: "家附近 · 步行 8 分钟",
            coverImagePath: media.gymWide,
            isCurrent: true
        )
        let officeGym = GymProfile(name: "公司健身房", notes: "办公楼 B1 · 工作日", isCurrent: false)
        context.insert(gym)
        context.insert(officeGym)

        if let path = media.gymWide {
            context.insert(GymMedia(gymID: gym.id, path: path))
        }
        if let path = media.gymEquipment {
            context.insert(GymMedia(gymID: gym.id, path: path))
        }

        [
            ("深蹲架", "力量", "深蹲、卧推、肩推", media.gymWide),
            ("可调哑铃", "自由重量", "全身自由重量训练", media.gymEquipment),
            ("高位下拉机", "力量", "背部与手臂拉力训练", media.gymEquipment),
            ("跑步机", "有氧", "热身、慢跑与间歇", media.gymWide)
        ].forEach {
            context.insert(GymEquipment(
                gymID: gym.id,
                name: $0.0,
                category: $0.1,
                capabilities: $0.2,
                imagePath: $0.3
            ))
        }
        [
            ("史密斯机", "力量", "深蹲、卧推、提踵"),
            ("划船机", "有氧", "全身有氧与拉力训练")
        ].forEach {
            context.insert(GymEquipment(gymID: officeGym.id, name: $0.0, category: $0.1, capabilities: $0.2))
        }

        let calendar = Calendar.current
        for offset in 0 ..< 35 where offset % 3 != 1 {
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            context.insert(WorkoutEntry(
                date: date,
                exercise: offset % 2 == 0 ? "杠铃深蹲" : "高位下拉",
                sets: 4,
                reps: offset % 2 == 0 ? 8 : 10,
                weight: offset % 2 == 0 ? 60 + Double((35 - offset) / 7) * 2.5 : 45,
                restSeconds: 90,
                durationMinutes: 48,
                notes: offset == 0 ? "今天状态不错，最后两次略吃力。" : "",
                mediaKind: offset == 0 && media.workout != nil ? .image : .none,
                mediaPath: offset == 0 ? media.workout : nil,
                formScore: 82 + offset % 10,
                intensity: "适中",
                feedback: "节奏稳定，保持核心张力后再小幅加重。",
                estimatedCalories: offset % 2 == 0 ? 296 : 207,
                calorieMET: offset % 2 == 0 ? 5.0 : 3.5,
                calorieDurationMinutes: 48,
                calorieDurationEstimated: false
            ))
        }
        for offset in 0 ..< 14 {
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            context.insert(MealEntry(
                date: date,
                mealType: .lunch,
                title: offset % 2 == 0 ? "鸡胸肉杂粮饭" : "牛肉蔬菜面",
                calories: offset % 2 == 0 ? 568 : 625,
                protein: offset % 2 == 0 ? 46 : 38,
                carbs: 61,
                fat: 16,
                notes: offset == 0 ? "演示餐食照片 · AI 按可见份量估算" : "",
                imagePath: offset == 0 ? media.meal : nil
            ))
        }
        for offset in stride(from: 28, through: 0, by: -7) {
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            context.insert(BodyEntry(
                date: date,
                weight: 74.8 - Double(28 - offset) * 0.035,
                bodyFat: 19.2 - Double(28 - offset) * 0.02,
                notes: offset == 0 ? "保持相同距离和光线记录。" : "",
                imagePath: offset == 0 ? media.body : nil,
                analysis: offset == 0 ? "站姿整体自然；照片仅用于长期变化对照，不做外貌评价。" : ""
            ))
        }
        context.insert(CoachMessage(
            isFromCoach: true,
            text: "早上好。你本周已经训练 3 次，今天建议做轻强度恢复或完整休息。"
        ))
        try? context.save()
        UserDefaults.standard.set(true, forKey: "demo.bundledMedia.v1")
    }

    private static func backfillDemoProfileAndCaloriesIfNeeded(in context: ModelContext) {
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        if profiles.isEmpty {
            context.insert(UserProfile(
                displayName: "Hedon",
                biologicalSex: .unspecified,
                birthDate: Calendar.current.date(
                    from: DateComponents(year: 1998, month: 5, day: 18)
                ),
                height: 178,
                referenceWeight: 74,
                fitnessGoal: "稳定提升力量与体能",
                healthNotes: ""
            ))
        }
        for profile in profiles where profile.birthDate == nil {
            if let age = profile.age {
                profile.birthDate = Calendar.current.date(
                    byAdding: .year,
                    value: -age,
                    to: .now
                )
                profile.age = nil
            }
        }

        let workouts = (try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? []
        for workout in workouts where workout.estimatedCalories == nil {
            let estimate = WorkoutCalorieCalculator.estimate(
                exercise: workout.exercise,
                intensity: workout.intensity,
                durationMinutes: workout.durationMinutes,
                sets: workout.setCount,
                reps: workout.representativeReps,
                restSeconds: workout.restSeconds,
                weightKG: 74
            )
            workout.estimatedCalories = estimate?.calories
            workout.calorieMET = estimate?.met
            workout.calorieDurationMinutes = estimate?.durationMinutes
            workout.calorieDurationEstimated = estimate?.durationWasEstimated ?? false
        }
        try? context.save()
    }

    private static func backfillDemoAgentTurnIfNeeded(in context: ModelContext) {
        let messages = (try? context.fetch(FetchDescriptor<CoachMessage>())) ?? []
        guard !messages.contains(where: { !$0.agentTurnItems.isEmpty }) else { return }

        let startedAt = Date().addingTimeInterval(-120)
        let firstTextID = UUID()
        let skillID = UUID()
        let toolID = UUID()
        let finalTextID = UUID()
        context.insert(CoachMessage(
            date: startedAt,
            isFromCoach: false,
            text: "帮我看看这周的训练情况"
        ))
        context.insert(CoachMessage(
            date: startedAt.addingTimeInterval(1),
            isFromCoach: true,
            text: "我先读取本周训练记录。本周已经训练 3 次，训练容量保持稳定，今天适合轻强度恢复。",
            agentStatus: .succeeded,
            agentTurnItems: [
                AgentTurnItem(
                    id: firstTextID,
                    sequence: 1,
                    kind: .text,
                    status: .succeeded,
                    text: "我先读取本周训练记录。",
                    startedAt: startedAt,
                    endedAt: startedAt.addingTimeInterval(0.3)
                ),
                AgentTurnItem(
                    id: skillID,
                    sequence: 2,
                    kind: .skill,
                    status: .succeeded,
                    title: AgentSkill.trendAnalysis.title,
                    startedAt: startedAt.addingTimeInterval(0.3),
                    endedAt: startedAt.addingTimeInterval(0.5),
                    output: AgentSkill.trendAnalysis.defaultText
                ),
                AgentTurnItem(
                    id: toolID,
                    sequence: 3,
                    kind: .tool,
                    status: .succeeded,
                    title: AgentToolName.queryUserData.displayTitle,
                    startedAt: startedAt.addingTimeInterval(0.5),
                    endedAt: startedAt.addingTimeInterval(0.8),
                    output: AgentTraceText.json(AgentToolResult.success(
                        "最近 7 天训练 3 次，训练容量保持稳定。"
                    ))
                ),
                AgentTurnItem(
                    id: finalTextID,
                    sequence: 4,
                    kind: .text,
                    status: .succeeded,
                    text: "本周已经训练 3 次，训练容量保持稳定，今天适合轻强度恢复。",
                    startedAt: startedAt.addingTimeInterval(0.8),
                    endedAt: startedAt.addingTimeInterval(1)
                )
            ]
        ))
        try? context.save()
    }

    private static func seedTraceLogsIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AgentTrace>())) ?? []
        if !existing.isEmpty {
            if let sample = existing.first(where: {
                $0.dataSpaceRaw == DataSpace.demo.rawValue
                    && $0.userInput == "我今天该怎么练？"
                    && !$0.spans.contains(where: { $0.kind == .skill })
            }) {
                sample.replaceSpans(demoSuccessSpans(startedAt: sample.startedAt))
                sample.apply(.completed(
                    answer: "今天建议做轻强度恢复或完整休息。",
                    at: sample.startedAt.addingTimeInterval(1.92)
                ))
                try? context.save()
            }
            return
        }

        let calendar = Calendar.current
        let successStart = calendar.date(byAdding: .minute, value: -18, to: .now) ?? .now
        let success = AgentTrace(
            startedAt: successStart,
            provider: "OpenAI",
            model: "gpt-4.1-mini",
            endpoint: "https://api.openai.com/v1/chat/completions",
            dataSpaceRaw: DataSpace.demo.rawValue,
            userInput: "我今天该怎么练？",
            contextSnapshot: "当前健身房：我的健身房；本周训练 3 次。",
            mediaKind: .none,
            imageCount: 0
        )
        success.replaceSpans(demoSuccessSpans(startedAt: successStart))
        let successEnd = successStart.addingTimeInterval(1.92)
        success.apply(.completed(
            answer: "今天建议做轻强度恢复或完整休息。",
            at: successEnd
        ))

        let failureStart = calendar.date(byAdding: .minute, value: -7, to: .now) ?? .now
        let failure = AgentTrace(
            startedAt: failureStart,
            provider: "DeepSeek",
            model: "deepseek-chat",
            endpoint: "https://api.deepseek.com/chat/completions",
            dataSpaceRaw: DataSpace.demo.rawValue,
            userInput: "分析这段训练视频",
            contextSnapshot: "当前健身房：我的健身房。",
            mediaKind: .video,
            imageCount: 4
        )
        let failureEnd = failureStart.addingTimeInterval(0.03)
        let failureMessage = "DeepSeek 的 deepseek-chat 不支持图片或视频分析。"
        failure.apply(.span(AgentTraceSpan(
            step: 1,
            kind: .model,
            title: "LLM 决策",
            status: .failed,
            startedAt: failureStart,
            endedAt: failureEnd,
            input: "图片或视频关键帧 4 张；原始输入是视频：是。",
            errorMessage: failureMessage
        )))
        failure.apply(.span(AgentTraceSpan(
            kind: .output,
            title: "执行失败",
            status: .failed,
            startedAt: failureEnd,
            endedAt: failureEnd,
            errorMessage: failureMessage
        )))
        failure.apply(.failed(message: failureMessage, cancelled: false, at: failureEnd))

        context.insert(success)
        context.insert(failure)
        try? context.save()
    }

    private static func demoSuccessSpans(startedAt: Date) -> [AgentTraceSpan] {
        [
            AgentTraceSpan(
                step: 1,
                kind: .model,
                title: "LLM 推理",
                status: .succeeded,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(0.46),
                input: "[SYSTEM]\n\(ReActAgentPrompt.system)\n\n[USER]\n我今天该怎么练？",
                output: "生成 1 个原生 tool_call：load_skill",
                metadata: #"{"stream":true,"prompt_tokens":986,"completion_tokens":51,"total_tokens":1037}"#
            ),
            AgentTraceSpan(
                step: 1,
                kind: .skill,
                title: AgentSkill.trainingPlan.title,
                status: .succeeded,
                startedAt: startedAt.addingTimeInterval(0.47),
                endedAt: startedAt.addingTimeInterval(0.48),
                input: #"{"name":"load_skill","arguments":{"skill_id":"training_plan"}}"#,
                output: AgentSkill.trainingPlan.defaultText,
                metadata: #"{"deduplicated":false,"skill_customized":false,"skill_id":"training_plan"}"#
            ),
            AgentTraceSpan(
                step: 2,
                kind: .model,
                title: "LLM 推理",
                status: .succeeded,
                startedAt: startedAt.addingTimeInterval(0.49),
                endedAt: startedAt.addingTimeInterval(1.12),
                input: "继续处理上一轮 assistant.tool_calls 与 role=tool 结果。",
                output: "生成 1 个原生 tool_call：query_user_data",
                metadata: #"{"stream":true,"prompt_tokens":1458,"completion_tokens":55,"total_tokens":1513}"#
            ),
            AgentTraceSpan(
                step: 2,
                kind: .tool,
                title: AgentToolName.queryUserData.rawValue,
                status: .succeeded,
                startedAt: startedAt.addingTimeInterval(1.13),
                endedAt: startedAt.addingTimeInterval(1.14),
                input: #"{"name":"query_user_data","arguments":{"scope":"workouts","limit":5}}"#,
                output: #"{"ok":true,"observation":"最近 7 天训练 3 次，最近一次为杠铃深蹲 4×8。"}"#
            ),
            AgentTraceSpan(
                step: 3,
                kind: .model,
                title: "LLM 推理",
                status: .succeeded,
                startedAt: startedAt.addingTimeInterval(1.15),
                endedAt: startedAt.addingTimeInterval(1.91),
                input: "继续处理上一轮 assistant.tool_calls 与 role=tool 结果。",
                output: "今天建议做轻强度恢复或完整休息。",
                metadata: #"{"stream":true,"prompt_tokens":1612,"completion_tokens":38,"total_tokens":1650}"#
            ),
            AgentTraceSpan(
                kind: .output,
                title: "最终回复",
                status: .succeeded,
                startedAt: startedAt.addingTimeInterval(1.92),
                endedAt: startedAt.addingTimeInterval(1.92),
                output: "今天建议做轻强度恢复或完整休息。"
            )
        ]
    }

    private static func backfillBundledMediaIfNeeded(
        in context: ModelContext,
        gyms: [GymProfile]
    ) {
        guard !UserDefaults.standard.bool(forKey: "demo.bundledMedia.v1"),
              let gym = gyms.first(where: {
                  $0.name == "我的健身房" && $0.notes == "家附近 · 步行 8 分钟"
              }) else { return }

        let media = installBundledMedia()
        guard media.hasAnyValue else { return }

        if gym.coverImagePath == nil {
            gym.coverImagePath = media.gymWide
            if let path = media.gymWide {
                context.insert(GymMedia(gymID: gym.id, path: path))
            }
            if let path = media.gymEquipment {
                context.insert(GymMedia(gymID: gym.id, path: path))
            }
        }

        let equipment = (try? context.fetch(FetchDescriptor<GymEquipment>())) ?? []
        for item in equipment where item.gymID == gym.id && item.imagePath == nil {
            item.imagePath = ["可调哑铃", "高位下拉机"].contains(item.name)
                ? media.gymEquipment
                : media.gymWide
        }

        var workoutDescriptor = FetchDescriptor<WorkoutEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = 1
        if let workout = try? context.fetch(workoutDescriptor).first,
           workout.mediaPath == nil,
           let path = media.workout
        {
            workout.mediaKind = .image
            workout.mediaPath = path
            workout.notes = "今天状态不错，最后两次略吃力。"
        }

        var mealDescriptor = FetchDescriptor<MealEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        mealDescriptor.fetchLimit = 1
        if let meal = try? context.fetch(mealDescriptor).first,
           meal.imagePath == nil
        {
            meal.imagePath = media.meal
            meal.notes = "演示餐食照片 · AI 按可见份量估算"
        }

        var bodyDescriptor = FetchDescriptor<BodyEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        bodyDescriptor.fetchLimit = 1
        if let body = try? context.fetch(bodyDescriptor).first,
           body.imagePath == nil
        {
            body.imagePath = media.body
            body.notes = "保持相同距离和光线记录。"
            body.analysis = "站姿整体自然；照片仅用于长期变化对照，不做外貌评价。"
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: "demo.bundledMedia.v1")
    }

    private static func installBundledMedia() -> DemoMediaPaths {
        DemoMediaPaths(
            gymWide: installImage(named: "gym-wide"),
            gymEquipment: installImage(named: "gym-equipment"),
            meal: installImage(named: "meal-chicken-bowl"),
            workout: installImage(named: "workout-squat"),
            body: installImage(named: "body-progress")
        )
    }

    private static func installImage(named name: String) -> String? {
        let url = Bundle.main.url(
            forResource: name,
            withExtension: "jpg",
            subdirectory: "DemoMedia"
        ) ?? Bundle.main.url(forResource: name, withExtension: "jpg")
        guard let url,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? MediaStore.saveImage(data)
    }
}

private struct DemoMediaPaths {
    let gymWide: String?
    let gymEquipment: String?
    let meal: String?
    let workout: String?
    let body: String?

    var hasAnyValue: Bool {
        [gymWide, gymEquipment, meal, workout, body].contains { $0 != nil }
    }
}
