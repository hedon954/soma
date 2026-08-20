import Foundation

/// BUG 0024：流式文字增量原来逐 token 写 SwiftData 与聊天视图，一次回复要做上千次
/// `agentTurnItems` 全量 JSON 解码-编码和 `UITextView` 重排。这里按固定节拍合批，
/// 首个增量立即出，后续增量攒够间隔再出，既保留"边说边显示"，又把投影次数降到十几次。
struct AgentTextDeltaCoalescer {
    /// 两次投影之间的最小间隔。约 10Hz，低于人眼察觉阅读卡顿的阈值。
    let minimumInterval: TimeInterval
    private var pending = ""
    private var lastEmittedAt: Date?

    init(minimumInterval: TimeInterval = 0.1) {
        self.minimumInterval = max(0, minimumInterval)
    }

    var hasPendingText: Bool {
        !pending.isEmpty
    }

    /// 追加一个增量，返回本次应当投影的文字；返回 `nil` 表示继续攒。
    mutating func append(_ delta: String, now: Date) -> String? {
        guard !delta.isEmpty else { return nil }
        pending += delta
        guard let lastEmittedAt else {
            return emit(at: now)
        }
        guard now.timeIntervalSince(lastEmittedAt) >= minimumInterval else {
            return nil
        }
        return emit(at: now)
    }

    /// 流结束、失败或即插入非文字事件前，把攒下的文字一次投影出去。
    mutating func flush(now: Date = .now) -> String? {
        guard !pending.isEmpty else { return nil }
        return emit(at: now)
    }

    private mutating func emit(at now: Date) -> String? {
        guard !pending.isEmpty else { return nil }
        let text = pending
        pending = ""
        lastEmittedAt = now
        return text
    }
}
