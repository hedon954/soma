@testable import Soma
import SwiftOpenAI
import UIKit
import XCTest

@MainActor
final class VideoFrameFallbackTests: XCTestCase {
    func testExplicitVideoRejectionKeepsOriginalAndNeverRetriesWithFrames() async throws {
        let url = try await SyntheticVideoFixture.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let original = try Data(contentsOf: url)
        var count = 0
        let service = AIService(apiKeyOverride: "fixture", agentStreamLoader: { _, _, _, _ in
            count += 1
            throw APIError.responseUnsuccessful(description: "unsupported video_url", statusCode: 400)
        })
        var messages = [ChatCompletionParameters.Message(role: .user, content: .text("虚构视频"))]
        do {
            _ = try await service.consumeAgentStepWithRetry(messages: &messages, request: request(videos: [
                .init(data: original, mimeType: "video/mp4")
            ]), trace: nil)
            XCTFail("Unsupported video should require a compatible model")
        } catch let StreamingFailure.interrupted(error, _, _, _) {
            XCTAssertEqual(error as? ConversationMediaPreparationError, .nativeVideoUnsupported)
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testOnlyExplicitVideoTypeRejectionsAreClassifiedAsUnsupported() {
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
            XCTAssertEqual(error as? ConversationMediaPreparationError, .nativeVideoUnsupported)
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

    func testLegacyFrameModeCheckpointStillDecodes() throws {
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

    private static func chunk(_ text: String) throws -> ChatCompletionChunkObject {
        // Controlled test JSON only; no user text or media enters this fixture.
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "fixture", "object": "chat.completion.chunk",
            "choices": [["index": 0, "delta": ["content": text]]]
        ])
        return try JSONDecoder().decode(ChatCompletionChunkObject.self, from: data)
    }
}
