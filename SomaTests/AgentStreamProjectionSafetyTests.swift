@testable import Soma
import UIKit
import XCTest

@MainActor
private final class ProjectionBatchRecorder {
    var batches: [String] = []
}

/// BUG 0024：流式期间的投影安全。合批不能丢字，过程卡形态切换不能复用同一个 SwiftUI 身份。
final class AgentStreamProjectionSafetyTests: XCTestCase {
    func testFirstDeltaProjectsImmediately() {
        var coalescer = AgentTextDeltaCoalescer(minimumInterval: 0.1)
        let start = Date(timeIntervalSince1970: 1000)

        XCTAssertEqual(coalescer.append("今", now: start), "今")
        XCTAssertFalse(coalescer.hasPendingText)
    }

    func testDeltasWithinIntervalCoalesceIntoOneProjection() {
        var coalescer = AgentTextDeltaCoalescer(minimumInterval: 0.1)
        let start = Date(timeIntervalSince1970: 1000)

        XCTAssertEqual(coalescer.append("今", now: start), "今")
        XCTAssertNil(coalescer.append("天", now: start.addingTimeInterval(0.01)))
        XCTAssertNil(coalescer.append("的", now: start.addingTimeInterval(0.02)))
        XCTAssertEqual(
            coalescer.append("训", now: start.addingTimeInterval(0.2)),
            "天的训"
        )
    }

    func testFlushEmitsRemainderExactlyOnce() {
        var coalescer = AgentTextDeltaCoalescer(minimumInterval: 0.1)
        let start = Date(timeIntervalSince1970: 1000)

        _ = coalescer.append("已", now: start)
        XCTAssertNil(coalescer.append("记", now: start.addingTimeInterval(0.01)))
        XCTAssertEqual(coalescer.flush(now: start.addingTimeInterval(0.02)), "记")
        XCTAssertNil(coalescer.flush(now: start.addingTimeInterval(0.03)))
    }

    func testCoalescingPreservesEveryCharacterInOrder() {
        var coalescer = AgentTextDeltaCoalescer(minimumInterval: 0.1)
        let start = Date(timeIntervalSince1970: 1000)
        let deltas = ["今", "天", "做", "了", "深", "蹲", "和", "硬", "拉"]
        var projected = ""

        for (index, delta) in deltas.enumerated() {
            let now = start.addingTimeInterval(Double(index) * 0.03)
            if let batched = coalescer.append(delta, now: now) {
                projected += batched
            }
        }
        if let tail = coalescer.flush(now: start.addingTimeInterval(1)) {
            projected += tail
        }

        XCTAssertEqual(projected, deltas.joined())
    }

    func testEmptyDeltaIsIgnored() {
        var coalescer = AgentTextDeltaCoalescer(minimumInterval: 0.1)
        XCTAssertNil(coalescer.append("", now: Date(timeIntervalSince1970: 1000)))
        XCTAssertFalse(coalescer.hasPendingText)
    }

    func testTwoMinuteHighFrequencyStreamStaysWithinBoundedUIProjectionCount() {
        var coalescer = AgentTextDeltaCoalescer()
        let start = Date(timeIntervalSince1970: 1000)
        var projectionCount = 0
        var projected = ""

        for index in 0 ..< 12000 {
            let now = start.addingTimeInterval(Double(index) * 0.01)
            if let batch = coalescer.append("字", now: now) {
                projectionCount += 1
                projected += batch
            }
        }
        if let tail = coalescer.flush(now: start.addingTimeInterval(120)) {
            projectionCount += 1
            projected += tail
        }

        XCTAssertEqual(projected.count, 12000)
        XCTAssertLessThanOrEqual(
            projectionCount,
            610,
            "两分钟碎片流不能制造逐 chunk 或 10Hz 以上的 UI 重排"
        )
    }

    func testProjectionPumpKeepsCollectingWhileMainActorProjectionIsSlow() async {
        let recorder = await MainActor.run { ProjectionBatchRecorder() }
        let pump = AgentTextProjectionPump(minimumInterval: .milliseconds(50)) { batch in
            recorder.batches.append(batch)
            Thread.sleep(forTimeInterval: 0.08)
        }
        let expected = (0 ..< 40).map { "\($0)," }.joined()

        await Task.detached {
            for index in 0 ..< 40 {
                await pump.append("\(index),")
                try? await Task.sleep(for: .milliseconds(5))
            }
        }.value
        _ = await pump.finish()

        let batches = await MainActor.run { recorder.batches }
        XCTAssertEqual(batches.joined(), expected)
        XCTAssertLessThanOrEqual(
            batches.count,
            6,
            "慢 UI 不能把单飞投影重新退化成逐 delta 刷新"
        )
    }

    func testLiveTextBufferPreservesAllCharactersAcrossStableChunks() {
        var buffer = LiveAgentTextBuffer()
        let deltas = (0 ..< 200).map { index in
            "第\(index)段虚构训练建议：保持动作稳定，不追求极限重量。\n"
        }

        for delta in deltas {
            buffer.append(delta)
        }

        XCTAssertEqual(buffer.text, deltas.joined())
        XCTAssertEqual(buffer.chunks.map(\.text).joined(), buffer.text)
        XCTAssertEqual(Set(buffer.chunks.map(\.id)).count, buffer.chunks.count)
        XCTAssertGreaterThan(buffer.chunks.count, 1)
    }

    func testParagraphStreamKeepsTheMutableTailSmall() {
        var buffer = LiveAgentTextBuffer()
        for index in 0 ..< 200 {
            buffer.append("第\(index)段虚构训练建议：只测量当前流式尾块。\n")
        }

        XCTAssertGreaterThan(buffer.chunks.count, 10)
        XCTAssertLessThanOrEqual(
            buffer.chunks.last?.text.count ?? .max,
            LiveAgentTextBuffer.defaultTargetCharacterCount,
            "带换行的长流式必须及时冻结前文，不能让可变尾块持续放大 CoreText 重排"
        )
    }

    func testLongStreamFixtureRequiresExplicitUITestSentinelAndFixtureName() {
        XCTAssertFalse(PerformanceTestFixture.requestsLongStream(in: [
            PerformanceTestFixture.environmentKey: PerformanceTestFixture.longStream
        ]))
        XCTAssertFalse(PerformanceTestFixture.requestsLongStream(in: [
            AppTestRuntime.uiTestEnvironmentKey: "1"
        ]))
        XCTAssertTrue(PerformanceTestFixture.requestsLongStream(in: [
            AppTestRuntime.uiTestEnvironmentKey: "1",
            PerformanceTestFixture.environmentKey: PerformanceTestFixture.longStream
        ]))
        XCTAssertTrue(PerformanceTestFixture.requestsLongStream(in: [
            AppTestRuntime.uiTestEnvironmentKey: "1",
            PerformanceTestFixture.environmentKey: PerformanceTestFixture.longStreamNoNewline
        ]))
    }

    func testDeviceHarnessOnlyWaitsForExplicitFixtureCompletionSignal() {
        XCTAssertFalse(DevicePerformanceHarness.waitsForFixtureCompletion(in: [:]))
        XCTAssertFalse(DevicePerformanceHarness.waitsForFixtureCompletion(in: [
            DevicePerformanceHarness.waitForFixtureCompletionEnvironmentKey: "0"
        ]))
        XCTAssertTrue(DevicePerformanceHarness.waitsForFixtureCompletion(in: [
            DevicePerformanceHarness.waitForFixtureCompletionEnvironmentKey: "1"
        ]))
    }

    func testLiveTextBufferOnlyMutatesItsTailChunk() {
        var buffer = LiveAgentTextBuffer(targetCharacterCount: 96)
        for index in 0 ..< 40 {
            buffer.append("第\(index)段虚构内容，用于稳定流式分块。\n")
        }
        XCTAssertGreaterThan(buffer.chunks.count, 2)
        let frozenPrefix = Array(buffer.chunks.dropLast())

        for index in 40 ..< 80 {
            buffer.append("第\(index)段继续追加，不得改写已经完成的分块。\n")
        }

        XCTAssertEqual(
            Array(buffer.chunks.prefix(frozenPrefix.count)),
            frozenPrefix,
            "长流式只能继续追加新块或修改尾块，不能让前文重新布局"
        )
    }

    func testLongSingleParagraphUsesBoundedStorageChunksWithoutChangingText() {
        var buffer = LiveAgentTextBuffer(targetCharacterCount: 32)
        let paragraph = String(repeating: "连续文字", count: 100)

        buffer.append(paragraph)

        XCTAssertGreaterThan(buffer.chunks.count, 1)
        XCTAssertTrue(buffer.chunks.allSatisfy { $0.text.count <= 32 })
        XCTAssertEqual(buffer.chunks.map(\.text).joined(), paragraph)
        XCTAssertFalse(buffer.chunks.map(\.text).joined().contains("\n"))
    }

    @MainActor
    func testIncrementalTextKitProjectionAppendsEveryChunkExactlyOnce() {
        var buffer = LiveAgentTextBuffer(targetCharacterCount: 32)
        let view = UITextView()
        let coordinator = IncrementalChatTextView.Coordinator()

        buffer.append(String(repeating: "甲", count: 20))
        coordinator.replaceText(in: view, with: buffer.chunks)
        buffer.append(String(repeating: "乙", count: 30))
        coordinator.update(view, with: buffer.chunks)
        buffer.append("结尾")
        coordinator.update(view, with: buffer.chunks)

        XCTAssertEqual(
            view.text,
            String(repeating: "甲", count: 20)
                + String(repeating: "乙", count: 30)
                + "结尾"
        )
    }

    func testLiveTextProjectionAddsOnlyOneTransientItem() {
        let completed = AgentTurnItem(
            kind: .tool,
            status: .succeeded,
            title: "保存饮食"
        )
        let itemID = UUID()
        let snapshot = LiveAgentTextSnapshot(itemID: itemID, text: "正在整理")

        let projected = AgentTurnLiveProjection.make(
            persisted: [completed],
            liveText: snapshot
        )
        let alreadyCommitted = AgentTurnLiveProjection.make(
            persisted: projected,
            liveText: snapshot
        )

        XCTAssertEqual(projected.count, 2)
        XCTAssertEqual(projected.last?.id, itemID)
        XCTAssertEqual(projected.last?.status, .running)
        XCTAssertEqual(alreadyCommitted.count, 2)
        XCTAssertEqual(snapshot.chunks.map(\.text).joined(), snapshot.text)
    }

    func testSingleAndGroupedProcessSegmentsUseDistinctIdentities() {
        let first = AgentTurnItem(
            kind: .tool,
            status: .succeeded,
            title: "搜索动作"
        )
        let second = AgentTurnItem(
            kind: .tool,
            status: .succeeded,
            title: "创建训练记录"
        )

        let single = AgentTurnTranscriptSegments.make(from: [first])
        let grouped = AgentTurnTranscriptSegments.make(from: [first, second])

        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(grouped.count, 1)
        XCTAssertNotEqual(
            single[0].id,
            grouped[0].id,
            "单条与多条过程卡渲染不同视图，身份必须不同"
        )
    }

    func testSegmentIdentitiesStayUniqueAcrossMixedTranscript() {
        let search = AgentTurnItem(kind: .tool, status: .succeeded, title: "搜索动作")
        let create = AgentTurnItem(kind: .tool, status: .succeeded, title: "创建训练记录")
        let failed = AgentTurnItem(
            kind: .tool,
            status: .failed,
            title: "搜索动作",
            errorMessage: "未找到动作"
        )
        let text = AgentTurnItem(kind: .text, status: .succeeded, text: "已记下。")

        let segments = AgentTurnTranscriptSegments.make(
            from: [search, create, failed, search, text]
        )
        let identities = segments.map(\.id)

        XCTAssertEqual(Set(identities).count, identities.count)
    }

    func testProcessSegmentIdentityIsStableWhileGroupGrows() {
        let first = AgentTurnItem(kind: .tool, status: .succeeded, title: "搜索动作")
        let second = AgentTurnItem(kind: .tool, status: .succeeded, title: "创建训练记录")
        let third = AgentTurnItem(kind: .tool, status: .succeeded, title: "读取饮食记录")

        let two = AgentTurnTranscriptSegments.make(from: [first, second])
        let three = AgentTurnTranscriptSegments.make(from: [first, second, third])

        XCTAssertEqual(
            two[0].id,
            three[0].id,
            "已经是分组形态后继续追加步骤不应重建卡片"
        )
    }
}
