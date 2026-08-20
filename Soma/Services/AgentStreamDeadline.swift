import Foundation
import SwiftOpenAI

struct AgentStreamDeadlinePolicy: Equatable, Sendable {
    var textTTFT: TimeInterval = 20
    var imageTTFT: TimeInterval = 40
    var directVideoTTFT: TimeInterval = 60
    var textLoopTotal: TimeInterval = 180
    var imageLoopTotal: TimeInterval = 300
    var videoLoopTotal: TimeInterval = 600

    func ttft(for mode: AgentMediaMode) -> TimeInterval {
        switch mode {
        case .text:
            textTTFT
        case .images, .keyframes:
            imageTTFT
        case .directVideo:
            directVideoTTFT
        }
    }

    func loopTotal(hasImages: Bool, hasVideo: Bool) -> TimeInterval {
        if hasVideo {
            return videoLoopTotal
        }
        if hasImages {
            return imageLoopTotal
        }
        return textLoopTotal
    }
}

enum AgentStreamTimeoutPhase: String, Sendable {
    case firstDelta = "first_delta"
    case loopTotal = "loop_total"
}

struct AgentStreamTimeoutError: LocalizedError, Sendable {
    var phase: AgentStreamTimeoutPhase
    var seconds: TimeInterval

    var errorDescription: String? {
        switch phase {
        case .firstDelta:
            "模型在 \(formattedSeconds) 秒内没有返回文字或工具调用"
        case .loopTotal:
            "整个 ReAct Loop 超过 \(formattedSeconds) 秒"
        }
    }

    private var formattedSeconds: String {
        seconds.formatted(.number.precision(.fractionLength(0 ... 2)))
    }
}

private actor AgentStreamChunkReader {
    private var iterator: AsyncThrowingStream<ChatCompletionChunkObject, Error>.Iterator

    init(stream: AsyncThrowingStream<ChatCompletionChunkObject, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> ChatCompletionChunkObject? {
        var activeIterator = iterator
        let chunk = try await activeIterator.next()
        iterator = activeIterator
        return chunk
    }
}

private enum AgentStreamRaceResult: @unchecked Sendable {
    case chunk(ChatCompletionChunkObject?)
    case timeout
}

enum AgentStreamDeadline {
    /// BUG 0024：`onChunk` 会把增量投影到 SwiftData 与 `@Observable` 状态上，必须在主 actor
    /// 执行。这里显式标注隔离，让每次 `await` 之后的恢复点回到主 actor，而不是停在读取
    /// chunk 的私有 actor 或 URLSession 执行器上。
    @MainActor
    static func consume(
        stream: AsyncThrowingStream<ChatCompletionChunkObject, Error>,
        mode: AgentMediaMode,
        policy: AgentStreamDeadlinePolicy,
        enforceFirstDelta: Bool,
        onChunk: @MainActor (ChatCompletionChunkObject) throws -> Bool
    ) async throws {
        let reader = AgentStreamChunkReader(stream: stream)
        guard enforceFirstDelta else {
            while let chunk = try await reader.next() {
                _ = try onChunk(chunk)
            }
            return
        }
        let startedAt = Date()
        let firstDeltaDeadline = startedAt.addingTimeInterval(policy.ttft(for: mode))
        var receivedFirstDelta = false

        while true {
            if receivedFirstDelta {
                while let chunk = try await reader.next() {
                    _ = try onChunk(chunk)
                }
                return
            }
            let now = Date()
            let timeout = max(0, firstDeltaDeadline.timeIntervalSince(now))
            let result = try await raceNext(reader: reader, timeout: timeout)
            switch result {
            case let .chunk(chunk):
                guard let chunk else { return }
                if try onChunk(chunk) {
                    receivedFirstDelta = true
                }
            case .timeout:
                throw AgentStreamTimeoutError(
                    phase: .firstDelta,
                    seconds: policy.ttft(for: mode)
                )
            }
        }
    }

    private static func raceNext(
        reader: AgentStreamChunkReader,
        timeout: TimeInterval
    ) async throws -> AgentStreamRaceResult {
        try await withThrowingTaskGroup(of: AgentStreamRaceResult.self) { group in
            group.addTask {
                try await .chunk(reader.next())
            }
            group.addTask {
                try await Task.sleep(
                    for: .seconds(timeout),
                    tolerance: .milliseconds(20)
                )
                return .timeout
            }
            guard let first = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return first
        }
    }
}
