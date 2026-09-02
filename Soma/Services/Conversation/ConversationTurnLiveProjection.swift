import Foundation
import Observation
import SwiftData

@MainActor
extension ConversationProcessingService {
    func applyLiveAgentEvent(_ event: AgentTraceEvent) {
        #if DEBUG
            // BUG 0024：这里改的是驱动聊天界面的 `@Observable` 状态。
            MainActor.assertIsolated("Agent 实时状态必须在主 actor 更新")
        #endif
        let interval = AppPerformance.begin(
            .agentProjection,
            detail: "phase=stream-project"
        )
        defer {
            AppPerformance.end(interval, detail: "phase=stream-project")
        }
        liveEventRevision += 1
        switch event {
        case let .reasoningDelta(itemID, delta):
            if liveReasoningItemID != itemID {
                liveReasoningItemID = itemID
                liveReasoningTextBuffer.reset()
            }
            liveReasoningTextBuffer.append(delta)
        case let .reasoningCompleted(itemID, _, _):
            if liveReasoningItemID == itemID {
                liveReasoningItemID = nil
                liveReasoningTextBuffer.reset()
            }
        case let .assistantTextDelta(itemID, delta):
            if liveAssistantItemID != itemID {
                liveAssistantItemID = itemID
                liveAssistantTextBuffer.reset()
            }
            liveAssistantTextBuffer.append(delta)
        case let .assistantTextCompleted(itemID, _):
            if liveAssistantItemID == itemID {
                liveAssistantItemID = nil
                liveAssistantTextBuffer.reset()
            }
        case .span:
            break
        case .completed, .failed:
            liveAssistantItemID = nil
            liveAssistantTextBuffer.reset()
            liveReasoningItemID = nil
            liveReasoningTextBuffer.reset()
        }
    }

    /// 物理设备和 Simulator 共用的长流式性能路径。调用方已由
    /// `PerformanceTestFixture` 双重门控，数据空间也来自 XCTest 内存容器。
    func startLongStreamPerformanceFixture(
        dataSpace: DataSpace,
        sessionID: UUID,
        responseMessageID: UUID,
        modelContext: ModelContext
    ) {
        guard let scenario = PerformanceTestFixture.requestedStreamScenario else { return }
        guard !scenario.usesStaticAgentStage else { return }
        performanceFixtureTask?.cancel()
        performanceFixturePhase = "streaming"
        isProcessing = true
        self.dataSpace = dataSpace
        self.sessionID = sessionID
        let itemID = UUID()

        let streamRange = scenario.streamRange
        for index in 0 ..< streamRange.lowerBound {
            applyLiveAgentEvent(.assistantTextDelta(
                itemID: itemID,
                delta: PerformanceTestFixture.streamDelta(index, scenario: scenario)
            ))
        }

        performanceFixtureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await PerformanceTestFixture.projectStreamDeltas(
                from: streamRange.lowerBound,
                to: streamRange.upperBound,
                scenario: scenario
            ) { [weak self] batch in
                self?.applyLiveAgentEvent(.assistantTextDelta(
                    itemID: itemID,
                    delta: batch
                ))
            }
            guard !Task.isCancelled else { return }
            performanceFixturePhase = "stream-drained"
            guard scenario.completes,
                  let liveText = liveAssistantTextSnapshot
            else { return }
            performanceFixturePhase = "snapshot-ready"
            let completedInterval = AppPerformance.begin(
                .agentProjection,
                detail: "phase=stream-to-completed,bytes=\(liveText.text.utf8.count)"
            )
            var descriptor = FetchDescriptor<CoachMessage>(
                predicate: #Predicate { $0.id == responseMessageID }
            )
            descriptor.fetchLimit = 1
            guard let responseMessage = try? modelContext.fetch(descriptor).first else {
                performanceFixturePhase = "message-missing"
                AppPerformance.end(
                    completedInterval,
                    detail: "phase=stream-to-completed,result=missing"
                )
                return
            }
            performanceFixturePhase = "message-fetched"
            // 在同一个 MainActor 事务中先撤下实时 TextKit，再发布完成态模型。
            // 不能在二者之间 yield，否则超长回复会短暂同时布局两份全文，完成清理
            // 反而排在这次昂贵布局之后，形成明显的 stream-to-completed cliff。
            applyLiveAgentEvent(.assistantTextCompleted(itemID: itemID, at: .now))
            responseMessage.text = liveText.text
            responseMessage.agentStatus = .succeeded
            responseMessage.replaceAgentTurnItems([
                AgentTurnItem(
                    id: itemID,
                    sequence: 1,
                    kind: .text,
                    status: .succeeded,
                    text: liveText.text,
                    startedAt: responseMessage.date,
                    endedAt: .now
                )
            ])
            finishProcessing()
            performanceFixturePhase = "model-transitioned"
            do {
                try modelContext.save()
            } catch {
                performanceFixturePhase = "save-failed"
                AppPerformance.end(
                    completedInterval,
                    detail: "phase=stream-to-completed,result=save-failed"
                )
                return
            }
            performanceFixturePhase = "completed"
            AppPerformance.end(
                completedInterval,
                detail: "phase=stream-to-completed,result=visible"
            )
        }
    }

    func projectRemoteTextDelta(
        _ event: AgentTraceEvent,
        at date: Date
    ) {
        guard case let .assistantTextDelta(itemID, delta) = event else { return }
        if remoteTextItemID != itemID {
            if let previousID = remoteTextItemID,
               let tail = remoteTextCoalescer.flush(now: date)
            {
                applyLiveAgentEvent(.assistantTextDelta(
                    itemID: previousID,
                    delta: tail
                ))
            }
            remoteTextCoalescer = AgentTextDeltaCoalescer()
            remoteTextItemID = itemID
        }
        if let batch = remoteTextCoalescer.append(delta, now: date) {
            applyLiveAgentEvent(.assistantTextDelta(itemID: itemID, delta: batch))
        }
    }

    func flushRemoteTextDelta(itemID: UUID, at date: Date) {
        guard remoteTextItemID == itemID,
              let tail = remoteTextCoalescer.flush(now: date)
        else {
            return
        }
        applyLiveAgentEvent(.assistantTextDelta(itemID: itemID, delta: tail))
    }

    var liveAssistantRenderSnapshot: LiveAgentTextRenderSnapshot? {
        guard let liveAssistantItemID,
              !liveAssistantTextBuffer.chunks.isEmpty
        else {
            return nil
        }
        return LiveAgentTextRenderSnapshot(
            itemID: liveAssistantItemID,
            chunks: liveAssistantTextBuffer.chunks
        )
    }

    var liveReasoningRenderSnapshot: LiveAgentTextRenderSnapshot? {
        guard let liveReasoningItemID,
              !liveReasoningTextBuffer.chunks.isEmpty
        else { return nil }
        return LiveAgentTextRenderSnapshot(
            itemID: liveReasoningItemID,
            chunks: liveReasoningTextBuffer.chunks
        )
    }

    /// 完整正文只在持久化边界合并一次，不参与 5Hz UI 投影。
    var liveAssistantTextSnapshot: LiveAgentTextSnapshot? {
        guard let renderSnapshot = liveAssistantRenderSnapshot else { return nil }
        let text = liveAssistantTextBuffer.text
        guard !text.isEmpty else { return nil }
        return LiveAgentTextSnapshot(
            itemID: renderSnapshot.itemID,
            text: text,
            chunks: renderSnapshot.chunks
        )
    }

    func pendingLiveTextSnapshot(
        for event: AgentTraceEvent
    ) -> LiveAgentTextSnapshot? {
        guard let snapshot = liveAssistantTextSnapshot else { return nil }
        switch event {
        case let .assistantTextCompleted(itemID, _):
            return itemID == snapshot.itemID ? snapshot : nil
        case .completed, .failed:
            return snapshot
        case .assistantTextDelta, .reasoningDelta, .reasoningCompleted, .span:
            return nil
        }
    }
}
