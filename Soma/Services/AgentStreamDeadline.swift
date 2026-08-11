import Foundation
import SwiftOpenAI

struct AgentStreamDeadlinePolicy: Equatable, Sendable {
    var textTTFT: TimeInterval = 8
    var imageTTFT: TimeInterval = 10
    var directVideoTTFT: TimeInterval = 20
    var idle: TimeInterval = 30
    var total: TimeInterval = 180

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
}

enum AgentStreamTimeoutPhase: String, Sendable {
    case firstDelta = "first_delta"
    case idle
    case total
}

struct AgentStreamTimeoutError: LocalizedError, Sendable {
    var phase: AgentStreamTimeoutPhase
    var seconds: TimeInterval

    var errorDescription: String? {
        switch phase {
        case .firstDelta:
            "模型在 \(formattedSeconds) 秒内没有返回文字或工具调用"
        case .idle:
            "模型流连续 \(formattedSeconds) 秒没有新数据"
        case .total:
            "单次模型流超过 \(formattedSeconds) 秒"
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
    static func consume(
        stream: AsyncThrowingStream<ChatCompletionChunkObject, Error>,
        mode: AgentMediaMode,
        policy: AgentStreamDeadlinePolicy,
        onChunk: (ChatCompletionChunkObject) throws -> Bool
    ) async throws {
        let reader = AgentStreamChunkReader(stream: stream)
        let startedAt = Date()
        let totalDeadline = startedAt.addingTimeInterval(policy.total)
        let firstDeltaDeadline = startedAt.addingTimeInterval(policy.ttft(for: mode))
        var receivedFirstDelta = false
        var lastActivityAt = startedAt

        while true {
            let now = Date()
            let phase: AgentStreamTimeoutPhase
            let phaseBudget: TimeInterval
            let phaseDeadline: Date
            if now >= totalDeadline {
                throw AgentStreamTimeoutError(phase: .total, seconds: policy.total)
            } else if receivedFirstDelta {
                phase = .idle
                phaseBudget = policy.idle
                phaseDeadline = min(
                    lastActivityAt.addingTimeInterval(policy.idle),
                    totalDeadline
                )
            } else {
                phase = .firstDelta
                phaseBudget = policy.ttft(for: mode)
                phaseDeadline = min(firstDeltaDeadline, totalDeadline)
            }
            let timeout = max(0, phaseDeadline.timeIntervalSince(now))
            let result = try await raceNext(reader: reader, timeout: timeout)
            switch result {
            case let .chunk(chunk):
                guard let chunk else { return }
                lastActivityAt = Date()
                if try onChunk(chunk) {
                    receivedFirstDelta = true
                }
            case .timeout:
                if phaseDeadline == totalDeadline {
                    throw AgentStreamTimeoutError(
                        phase: .total,
                        seconds: policy.total
                    )
                }
                throw AgentStreamTimeoutError(
                    phase: phase,
                    seconds: phaseBudget
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
