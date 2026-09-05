import AVFoundation
@testable import Soma
import SwiftOpenAI
import XCTest

@MainActor
final class FullVideoInputTests: XCTestCase {
    func testVideoPartsStayOnTheirOwnUserMessageWithoutSamplingHints() throws {
        let service = AIService(apiKeyOverride: "test-key")
        let body = try service.openAICompatibleChatRequestBody(
            parameters: ChatCompletionParameters(messages: [
                .init(role: .user, content: .text("先前的虚构视频")),
                .init(role: .assistant, content: .text("收到")),
                .init(role: .user, content: .text("对比本次虚构视频"))
            ], model: .custom("test")),
            videos: [
                AgentVideoInput(data: Data([1, 2, 3]), mimeType: "video/mp4", messageIndex: 0),
                AgentVideoInput(data: Data([4, 5, 6]), mimeType: "video/mp4", messageIndex: 2)
            ],
            baseURL: "https://provider.invalid/v1"
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        for index in [0, 2] {
            let parts = try XCTUnwrap(messages[index]["content"] as? [[String: Any]])
            let video = try XCTUnwrap(parts.last?["video_url"] as? [String: Any])
            XCTAssertNil(video["fps"])
            let expected = index == 0 ? "AQID" : "BAUG"
            XCTAssertEqual(video["url"] as? String, "data:video/mp4;base64,\(expected)")
            XCTAssertFalse(parts.contains { $0["type"] as? String == "image_url" })
        }
    }

    func testUnavailableVideoBlocksInsteadOfPreparingKeyframes() async {
        let service = ConversationProcessingService()
        let media = await service.prepareStoredMedia([
            .init(kind: .video, path: "missing-fictional-video.mp4")
        ], frameLimit: 4)
        XCTAssertEqual(media.failedVideoCount, 1)
        XCTAssertTrue(media.frames.isEmpty)
        XCTAssertTrue(media.videos.isEmpty)
        XCTAssertNotEqual(media.mode, .keyframes)
    }

    func testCompleteVideoDurationAndAutomaticPlayback() async throws {
        let url = try await SyntheticVideoFixture.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let service = ConversationProcessingService()
        let prepared = await service.prepareStoredMedia([.init(kind: .video, path: url.path)], frameLimit: 0)
        XCTAssertEqual(prepared.mode, .directVideo)
        XCTAssertEqual(prepared.videos.count, 1)
        XCTAssertTrue(prepared.frames.isEmpty)
        XCTAssertEqual(prepared.videos.first?.data, try Data(contentsOf: url))
        let duration = try await AVURLAsset(url: url).load(.duration)
        XCTAssertEqual(duration.seconds, 2, accuracy: 0.05)
        let playback = MediaVideoPlayback()
        await playback.open(url: url)
        let player = try XCTUnwrap(playback.player)
        let advanced = expectation(description: "video automatically advances")
        var fulfilled = false
        let observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { time in
            if time.seconds > 0.2, !fulfilled {
                fulfilled = true
                advanced.fulfill()
            }
        }
        await fulfillment(of: [advanced], timeout: 5)
        player.removeTimeObserver(observer)
        player.pause()
        XCTAssertEqual(player.rate, 0)
        player.play()
        XCTAssertEqual(player.rate, 1)
        playback.sceneChanged(.background)
        XCTAssertEqual(player.rate, 0)
        playback.sceneChanged(.active)
        XCTAssertEqual(player.rate, 1)
        playback.close()
        XCTAssertNil(playback.player)
        XCTAssertNil(player.currentItem)
    }

    func testUnavailablePlaybackHasVisibleErrorAndClosesCleanly() async {
        let playback = MediaVideoPlayback()
        await playback.open(url: nil)
        XCTAssertNotNil(playback.errorMessage)
        XCTAssertNil(playback.player)
        playback.close()
        XCTAssertNil(playback.errorMessage)
    }

    func testCorruptMP4DoesNotBecomeSuccessfulVideoInput() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data("not a video".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let video = await DirectVideoPreparer.input(for: url, capability: .standard)
        XCTAssertNil(video)
    }
}
