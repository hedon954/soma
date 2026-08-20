@testable import Soma
import XCTest

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
