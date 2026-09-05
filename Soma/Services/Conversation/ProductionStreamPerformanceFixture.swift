import Foundation
import SwiftData
import SwiftOpenAI

/// 虚构原始 chunk 经过真实 Deadline → Worker → Pump → 持久化投影。
/// 不连接模型，且只允许显式性能模式的内存数据空间。
@MainActor
extension ConversationProcessingService {
    func startProductionStreamFixture(
        dataSpace: DataSpace,
        sessionID: UUID,
        responseMessageID: UUID,
        modelContext: ModelContext
    ) {
        guard AppTestRuntime.isRunning,
              PerformanceTestFixture.requestedStreamScenario == .productionCompletion,
              let response = ConversationTurnPersistence.message(id: responseMessageID, in: modelContext)
        else { return }
        performanceFixtureTask?.cancel()
        self.dataSpace = dataSpace
        self.sessionID = sessionID
        isProcessing = true
        performanceFixturePhase = "streaming"
        let job = AgentJob(
            turnID: response.turnID ?? UUID(), sessionID: sessionID,
            userMessageID: UUID(), dataSpace: dataSpace,
            userText: "虚构性能测试", mediaAttachments: [],
            contextSnapshot: .init(structuredContext: "虚构上下文", includeLocation: false)
        )
        job.responseMessageID = response.id
        let trace = AgentTrace(
            provider: "fixture", model: "fixture", endpoint: "",
            dataSpaceRaw: dataSpace.rawValue, userInput: "虚构性能测试",
            contextSnapshot: "", mediaKind: .none, imageCount: 0, turnID: job.turnID
        )
        modelContext.insert(job)
        modelContext.insert(trace)
        let itemID = UUID()
        let interval = PerformanceTestFixture.streamInterval
        performanceFixtureTask = Task { [weak self] in
            guard let self else { return }
            let project: @MainActor (AgentTraceEvent) -> Void = { [weak self] event in
                guard let self, !Task.isCancelled else { return }
                let liveText = pendingLiveTextSnapshot(for: event)
                PersistentAgentEventProjection.persistAndProject(
                    event, job: job, responseMessage: response, trace: trace,
                    liveText: liveText, in: modelContext
                )
                applyLiveAgentEvent(event)
            }
            do {
                try job.transition(to: .running)
                let outcome = try await AgentStreamWorker.consume(
                    stream: ProductionStreamChunks.make(interval: interval),
                    mediaMode: .text, policy: .init(), enforceFirstDelta: true,
                    textItemID: itemID, reasoningItemID: UUID(), project: project
                )
                try Task.checkCancellation()
                project(.assistantTextCompleted(itemID: itemID, at: .now))
                project(.completed(answer: outcome.passage, at: .now))
                try job.transition(to: .succeeded)
                try modelContext.save()
                finishProcessing()
                performanceFixturePhase = "completed"
            } catch {
                guard !Task.isCancelled else { return }
                project(.failed(message: "虚构流式测试失败", cancelled: false, at: .now))
                finishProcessing()
                performanceFixturePhase = "failed"
            }
        }
    }
}

private enum ProductionStreamChunks {
    static func make(interval: Duration) -> AsyncThrowingStream<ChatCompletionChunkObject, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task.detached {
                do {
                    let decoder = JSONDecoder()
                    for index in 0 ..< 240 {
                        try Task.checkCancellation()
                        let text = PerformanceTestFixture.streamDelta(index, scenario: .productionCompletion)
                        let data = try JSONSerialization.data(withJSONObject: [
                            "id": "fictional-production-stream", "object": "chat.completion.chunk",
                            "choices": [["index": 0, "delta": ["content": text]]]
                        ])
                        let chunk = try decoder.decode(
                            ChatCompletionChunkObject.self,
                            from: OpenAICompatibleStreamPayload.normalize(data)
                        )
                        continuation.yield(chunk)
                        try await Task.sleep(for: interval)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
}
