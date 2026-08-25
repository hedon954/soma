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
        liveEventRevision += 1
        switch event {
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
        }
    }

    /// 物理设备和 Simulator 共用的长流式性能路径。调用方已由
    /// `PerformanceTestFixture` 双重门控，数据空间也来自 XCTest 内存容器。
    func startLongStreamPerformanceFixture(
        dataSpace: DataSpace,
        sessionID: UUID
    ) {
        guard PerformanceTestFixture.requestedLongStream else { return }
        performanceFixtureTask?.cancel()
        isProcessing = true
        self.dataSpace = dataSpace
        self.sessionID = sessionID
        let itemID = UUID()

        // 先进入足以暴露累计排版问题的长文本状态，再以产品相同的约 5 Hz
        // 节拍继续增长。这里不写 SwiftData，也不触发网络请求。
        for index in 0 ..< 160 {
            applyLiveAgentEvent(.assistantTextDelta(
                itemID: itemID,
                delta: PerformanceTestFixture.streamParagraph(index)
            ))
        }

        performanceFixtureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for index in 160 ..< 1060 {
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                applyLiveAgentEvent(.assistantTextDelta(
                    itemID: itemID,
                    delta: PerformanceTestFixture.streamParagraph(index)
                ))
            }
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
        case .assistantTextDelta, .span:
            return nil
        }
    }
}
