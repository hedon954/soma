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
    case imageGenerationUnsupported(String)
    case imageGenerationBlocked
    case multimodalUnsupported(provider: String, model: String)
    case multimodalRequestFailed(provider: String, model: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "模型服务地址无效"
        case .invalidResponse: "模型返回了无法识别的响应"
        case let .remote(message): message
        case let .missingAPIKey(provider): "请先在设置中保存 \(provider) 的 API Key"
        case let .imageGenerationUnsupported(provider):
            "\(provider) 尚未配置兼容的图片生成模型，请先在 AI 设置中填写图片生成模型 ID。"
        case .imageGenerationBlocked:
            "这次图片生成没有通过安全检查。请调整动作名称或肌群描述后重试。"
        case let .multimodalUnsupported(provider, model):
            "\(provider) 的 \(model) 不支持图片或视频分析。请切换到支持视觉的模型，文字对话仍可继续使用。"
        case let .multimodalRequestFailed(provider, model, reason):
            "\(provider) 的 \(model) 没能处理这次图片或视频：\(reason)"
        }
    }
}

struct AgentStreamOutcome {
    var passage = ""
    var toolCalls: [AgentStreamingToolCall] = []
    var usage: ChatUsage?
    var ignoredReasoning = false
    var firstDeltaAt: Date?
    var projectionSeconds: TimeInterval = 0
    var requestAttempt = 1
    var mediaMode: AgentMediaMode = .text
    var fallbackReason: String?
    var ttftBudgetMilliseconds = 0
}

/// 流式中断时保留已产出的文本，让失败 Span 仍能解释这一步做到哪里。
enum StreamingFailure: Error {
    case interrupted(
        Error,
        passage: String,
        receivedMeaningfulDelta: Bool
    )
}

struct AgentToolLoopState {
    var messages: [ChatCompletionParameters.Message]
    var tools: [ChatCompletionParameters.Tool]
    var exposedGroups: Set<AgentToolGroup>
    var observations: [AgentObservation] = []
    var executedMutations = Set<String>()
    var executedReads: [String: AgentToolResult] = [:]
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
    let agentStreamLoader: AgentStreamLoader?
    @ObservationIgnored
    let streamDeadlinePolicy: AgentStreamDeadlinePolicy

    init(
        defaults: UserDefaults = .standard,
        apiKeyOverride: String? = nil,
        requestLoader: @escaping AIRequestLoader = { request in
            try await URLSession.shared.data(for: request)
        },
        agentStreamLoader: AgentStreamLoader? = nil,
        streamDeadlinePolicy: AgentStreamDeadlinePolicy = .init()
    ) {
        self.defaults = defaults
        self.apiKeyOverride = apiKeyOverride
        self.requestLoader = requestLoader
        self.agentStreamLoader = agentStreamLoader
        self.streamDeadlinePolicy = streamDeadlinePolicy
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
                trace?(.span(AgentTraceSpan(
                    id: modelSpanID,
                    step: operationStep,
                    kind: .model,
                    title: "LLM 推理",
                    status: .running,
                    startedAt: modelStartedAt,
                    endedAt: modelStartedAt,
                    input: currentModelStep == 1
                        ? traceInput
                        : "继续处理上一轮 assistant.tool_calls 与 role=tool 结果。",
                    metadata: AgentTraceText.jsonObject([
                        "history_exchange_count": history.count,
                        "history_image_count": checkpoint != nil || clearedHistoryFrames
                            ? 0
                            : historicalImageCount,
                        "direct_video_count": videos.count,
                        "media_mode": initialMediaMode(
                            images: images,
                            videos: videos,
                            hasVideo: hasVideo
                        ).rawValue,
                        "provider": provider.displayName,
                        "model": model,
                        "model_tier": selectedRoute.tier.title,
                        "routing_reason": selectedRoute.reason,
                        "message_count": toolState.messages.count,
                        "exposed_tool_groups": toolState.exposedGroups.map(\.rawValue).sorted(),
                        "exposed_tool_count": toolState.tools.count,
                        "stream": true,
                        "thinking": false
                    ])
                )))

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
                    title: AgentToolName.listWorkouts.displayTitle,
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
                output: "生成 1 个原生 tool_call：list_workouts",
                metadata: #"{"stream":true,"prompt_tokens":1458,"completion_tokens":55,"total_tokens":1513}"#
            ),
            AgentTraceSpan(
                step: 2,
                kind: .tool,
                title: AgentToolName.listWorkouts.rawValue,
                status: .succeeded,
                startedAt: startedAt.addingTimeInterval(1.13),
                endedAt: startedAt.addingTimeInterval(1.14),
                input: #"{"name":"list_workouts","arguments":{"limit":5}}"#,
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
