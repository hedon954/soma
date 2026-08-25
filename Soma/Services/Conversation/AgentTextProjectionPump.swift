import Foundation

/// 在模型流消费与 MainActor 文本投影之间建立独立节拍。
///
/// 旧实现会等待一次 MainActor 投影后才继续读下一个 SSE chunk。长正文布局一旦超过
/// 200ms，下一枚 token 到达时又已经满足时间阈值，于是合批退化成逐 token 刷新。
/// Pump 在 UI 忙时继续收集文本，只允许一个投影任务排队；恢复后一次提交全部积压。
actor AgentTextProjectionPump {
    typealias Project = @MainActor (String) -> Void

    private let minimumInterval: Duration
    private let project: Project
    private var pending = ""
    private var drainTask: Task<Void, Never>?
    private var isFinishing = false
    private var projectionSeconds: TimeInterval = 0
    private var finishWaiters: [CheckedContinuation<TimeInterval, Never>] = []

    init(
        minimumInterval: Duration = .milliseconds(200),
        project: @escaping Project
    ) {
        self.minimumInterval = minimumInterval
        self.project = project
    }

    func append(_ text: String) {
        guard !text.isEmpty, !isFinishing else { return }
        pending += text
        startDrainIfNeeded()
    }

    /// 等待最后一批真正提交到 MainActor，保证完成事件不会越过尚未显示的正文。
    func finish() async -> TimeInterval {
        isFinishing = true
        if pending.isEmpty, drainTask == nil {
            return projectionSeconds
        }
        startDrainIfNeeded()
        return await withCheckedContinuation { continuation in
            finishWaiters.append(continuation)
        }
    }

    private func startDrainIfNeeded() {
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while true {
            guard !pending.isEmpty else {
                completeDrain()
                return
            }
            let batch = pending
            pending = ""
            let startedAt = Date()
            await project(batch)
            projectionSeconds += Date().timeIntervalSince(startedAt)

            if isFinishing, pending.isEmpty {
                completeDrain()
                return
            }
            try? await Task.sleep(for: minimumInterval)
        }
    }

    private func completeDrain() {
        drainTask = nil
        guard isFinishing else { return }
        let total = projectionSeconds
        let waiters = finishWaiters
        finishWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume(returning: total) }
    }
}
