import UIKit

/// 每次 Scene 激活只允许最新 generation 在首个真实显示帧之后恢复后台工作。
/// 这里不持有 SwiftData 对象；Root 在回调发生时使用当前 MainActor Context 重新读取。
@MainActor
final class ForegroundRecoveryCoordinator {
    private(set) var generation = 0
    private var task: Task<Void, Never>?

    func schedule(
        waitForFrame: @escaping @MainActor () async -> Void = {
            await ForegroundDisplayFrame.wait()
        },
        operation: @escaping @MainActor (Int) async -> Void
    ) {
        generation &+= 1
        let scheduledGeneration = generation
        task?.cancel()
        task = Task { [weak self] in
            await waitForFrame()
            guard !Task.isCancelled,
                  self?.generation == scheduledGeneration
            else {
                return
            }
            await operation(scheduledGeneration)
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    func isCurrent(_ candidate: Int) -> Bool {
        generation == candidate && task?.isCancelled != true
    }
}

@MainActor
private enum ForegroundDisplayFrame {
    static func wait() async {
        await withCheckedContinuation { continuation in
            let waiter = DisplayLinkWaiter(continuation: continuation)
            waiter.start()
        }
    }
}

@MainActor
private final class DisplayLinkWaiter: NSObject {
    private var continuation: CheckedContinuation<Void, Never>?
    private var displayLink: CADisplayLink?

    init(continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func start() {
        let displayLink = CADisplayLink(target: self, selector: #selector(frameDidDisplay))
        self.displayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    @objc private func frameDidDisplay() {
        displayLink?.invalidate()
        displayLink = nil
        continuation?.resume()
        continuation = nil
    }
}
