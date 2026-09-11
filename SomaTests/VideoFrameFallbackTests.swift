@testable import Soma
import SwiftOpenAI
import UIKit
import XCTest

@MainActor
final class VideoFrameFallbackTests: XCTestCase {
    func testExplicitVideoRejectionRetriesOnceWithFramesOnOriginalMessage() async throws {
        let url = try await SyntheticVideoFixture.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let answer = try Self.chunk("根据提供的画面，可以观察静态姿态。")
        var requests: [ChatCompletionParameters] = []
        let service = AIService(apiKeyOverride: "fixture", agentStreamLoader: { parameters, _, _, _ in
            requests.append(parameters)
            let attempt = requests.count
            return AsyncThrowingStream { continuation in
                if attempt == 1 {
                    continuation.finish(throwing: APIError.responseUnsuccessful(
                        description: "unknown variant `video_url`, expected `text`, `image_url`, `file`",
                        statusCode: 400
                    ))
                } else {
                    continuation.yield(answer)
                    continuation.finish()
                }
            }
        })
        var messages = [
            ChatCompletionParameters.Message(role: .user, content: .text("先前虚构视频")),
            .init(role: .assistant, content: .text("已收到")),
            .init(role: .user, content: service.agentUserContent(prompt: "对比姿态", images: [Data([1, 2])], maximumImageCount: 12))
        ]
        let outcome = try await service.consumeAgentStepWithRetry(
            messages: &messages,
            request: request(videos: [.init(data: data, mimeType: "video/mp4", messageIndex: 0)]),
            trace: nil
        )
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(outcome.mediaMode, .keyframes)
        let body = try json(requests[1])
        let encodedMessages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let oldParts = try XCTUnwrap(encodedMessages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(oldParts.filter { $0["type"] as? String == "image_url" }.count, 8)
        let currentParts = try XCTUnwrap(encodedMessages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(currentParts.filter { $0["type"] as? String == "image_url" }.count, 1)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testOnlyExplicitVideoTypeRejectionsAllowFallback() {
        let unsupported = "unknown variant `video_url`, expected `text`, `image_url`"
        for status in [400, 415, 422] {
            XCTAssertTrue(VideoInputRejection.isExplicit(APIError.responseUnsuccessful(description: unsupported, statusCode: status)))
        }
        for status in [401, 403, 408, 429, 500, 503] {
            XCTAssertFalse(VideoInputRejection.isExplicit(APIError.responseUnsuccessful(description: unsupported, statusCode: status)))
        }
        for message in ["invalid request", "video_url exceeds size limit", "image_url not supported", "video_url must be a valid URL"] {
            XCTAssertFalse(VideoInputRejection.isExplicit(APIError.responseUnsuccessful(description: message, statusCode: 400)))
        }
        XCTAssertFalse(VideoInputRejection.isExplicit(URLError(.timedOut)))
        XCTAssertFalse(VideoInputRejection.isExplicit(CancellationError()))
        let raw = Data("{\"error\":{\"message\":\"unknown variant video_url\"}}".utf8)
        let failure = ModelRequestFailure(statusCode: 400, data: raw)
        XCTAssertTrue(VideoInputRejection.isExplicit(failure))
        XCTAssertFalse(failure.localizedDescription.contains("video_url"))
        XCTAssertEqual(LLMOutageClassifier.signal(for: failure).httpStatusCode, 400)
    }

    func testFrameBudgetAndCoverageAreBoundedAcrossWholeVideos() throws {
        XCTAssertEqual(try VideoFrameFallbackPolicy.frameCounts(durations: [2]), [8])
        XCTAssertEqual(try VideoFrameFallbackPolicy.frameCounts(durations: [600]), [24])
        XCTAssertEqual(try VideoFrameFallbackPolicy.frameCounts(durations: [2, 600]), [8, 16])
        XCTAssertEqual(try VideoFrameFallbackPolicy.frameCounts(durations: Array(repeating: 30, count: 3)), Array(repeating: 8, count: 3))
        XCTAssertThrowsError(try VideoFrameFallbackPolicy.frameCounts(durations: Array(repeating: 30, count: 4)))
        for invalid in [0, -1, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try VideoFrameFallbackPolicy.frameCounts(durations: [invalid]))
        }
        let times = VideoFrameFallbackPolicy.timestamps(duration: 600, count: 24)
        XCTAssertEqual(times.first, 0)
        XCTAssertGreaterThan(try XCTUnwrap(times.last), 599)
        XCTAssertLessThan(try XCTUnwrap(times.last), 600)
        XCTAssertEqual(times, times.sorted())
    }

    func testSyntheticDecodeCoversTimelineAndPreservesOriginalWithinSizeBudget() async throws {
        let url = try await SyntheticVideoFixture.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let original = try Data(contentsOf: url)
        let sets = try await VideoFrameFallbackPreparer.prepare([.init(data: original, mimeType: "video/mp4")])
        let frames = try XCTUnwrap(sets.first)
        XCTAssertEqual(frames.frames.count, 8)
        XCTAssertEqual(frames.durationSeconds, 2, accuracy: 0.05)
        XCTAssertLessThan(try XCTUnwrap(frames.timestampsSeconds.first), 0.1)
        XCTAssertGreaterThan(try XCTUnwrap(frames.timestampsSeconds.last), 1.8)
        for frame in frames.frames {
            let image = try XCTUnwrap(UIImage(data: frame))
            XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 768)
        }
        XCTAssertLessThan(frames.frames.reduce(0) { $0 + $1.count }, 8 * 1024 * 1024)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testAnyOutputPreventsCapabilityRetryAndKeepsPartialText() async throws {
        let chunk = try Self.chunk("已看到第一张画面的姿态。")
        var count = 0
        let service = AIService(apiKeyOverride: "fixture", agentStreamLoader: { _, _, _, _ in
            count += 1
            return AsyncThrowingStream { continuation in
                continuation.yield(chunk)
                continuation.finish(throwing: APIError.responseUnsuccessful(description: "unsupported video_url", statusCode: 400))
            }
        })
        var messages = [ChatCompletionParameters.Message(role: .user, content: .text("虚构视频"))]
        do {
            _ = try await service.consumeAgentStepWithRetry(messages: &messages,
                                                            request: request(videos: [.init(data: Data([1]), mimeType: "video/mp4")]), trace: nil)
            XCTFail("A partially emitted model step must not restart")
        } catch let StreamingFailure.interrupted(_, passage, _, received) {
            XCTAssertTrue(received)
            XCTAssertEqual(passage, "已看到第一张画面的姿态。")
        }
        XCTAssertEqual(count, 1)
    }

    func testCorruptVideoNeverRetriesAsTextAndCancellationRemainsCancellation() async throws {
        var count = 0
        let service = AIService(apiKeyOverride: "fixture", agentStreamLoader: { _, _, _, _ in
            count += 1
            throw APIError.responseUnsuccessful(description: "unsupported video_url", statusCode: 400)
        })
        var messages = [ChatCompletionParameters.Message(role: .user, content: .text("虚构视频"))]
        do {
            _ = try await service.consumeAgentStepWithRetry(messages: &messages,
                                                            request: request(videos: [.init(data: Data([1]), mimeType: "video/mp4")]), trace: nil)
            XCTFail("Invalid video must fail explicitly")
        } catch let StreamingFailure.interrupted(error, _, _, _) {
            XCTAssertTrue(error is VideoFrameFallbackError)
        }
        XCTAssertEqual(count, 1)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VideoFrameFallbackPreparer.prepare([.init(data: Data([1]), mimeType: "video/mp4")])
        }
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled decode must not continue")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testFallbackCheckpointAndRepeatedStepsDoNotDuplicateImages() async throws {
        let answer = try Self.chunk("虚构画面结果")
        var requests: [ChatCompletionParameters] = []
        let service = AIService(apiKeyOverride: "fixture", agentStreamLoader: { parameters, _, _, _ in
            requests.append(parameters)
            return AsyncThrowingStream { continuation in continuation.yield(answer); continuation.finish() }
        })
        let state = AgentVideoFallbackState(isActive: true)
        state.frames = [.init(frames: (0 ..< 8).map { Data([UInt8($0 + 1)]) }, timestampsSeconds: (0 ..< 8).map { Double($0) * 1.96 / 7 }, durationSeconds: 2)]
        var streamRequest = request(videos: [.init(data: Data([3]), mimeType: "video/mp4")])
        streamRequest.videoFallbackState = state
        var activations = 0
        streamRequest.onVideoFallback = { activations += 1 }
        var messages = [ChatCompletionParameters.Message(role: .user, content: .text("虚构视频"))]
        for _ in 0 ..< 2 {
            let result = try await service.consumeAgentStepWithRetry(messages: &messages, request: streamRequest, trace: nil)
            XCTAssertEqual(result.mediaMode, .keyframes)
        }
        XCTAssertEqual(activations, 1)
        for parameters in requests {
            let body = try json(parameters)
            let items = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let parts = try XCTUnwrap(items[0]["content"] as? [[String: Any]])
            XCTAssertEqual(parts.filter { $0["type"] as? String == "image_url" }.count, 8)
        }
        var checkpoint = AgentLoopCheckpoint.empty
        checkpoint.videoInputMode = .keyframes
        let restored = try JSONDecoder().decode(AgentLoopCheckpoint.self, from: JSONEncoder().encode(checkpoint))
        XCTAssertEqual(restored.videoInputMode, .keyframes)
    }

    private func request(videos: [AgentVideoInput]) -> AgentStreamStepRequest {
        AgentStreamStepRequest(
            tools: [], model: "fixture", provider: .openAI, images: [], videos: videos,
            hasVideo: true, step: 1,
            route: .init(tier: .standard, provider: .openAI,
                         baseURL: "https://fixture.invalid/v1", model: "fixture", reason: "test"),
            apiKey: "fixture", userPrompt: "分析虚构视频", textItemID: UUID()
        )
    }

    private func json(_ parameters: ChatCompletionParameters) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any])
    }

    private static func chunk(_ text: String) throws -> ChatCompletionChunkObject {
        // Controlled test JSON only; no user text or media enters this fixture.
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "fixture", "object": "chat.completion.chunk",
            "choices": [["index": 0, "delta": ["content": text]]]
        ])
        return try JSONDecoder().decode(ChatCompletionChunkObject.self, from: data)
    }
}
