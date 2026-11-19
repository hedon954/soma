import AVFoundation
@testable import Soma
import SwiftData
import SwiftOpenAI
import UIKit
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

    func testUnverifiedModelNeverReceivesCurrentOrHistoricalVideo() async throws {
        let url = try await SyntheticVideoFixture.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = try Data(contentsOf: url)
        let clip = AgentVideoInput(data: bytes, mimeType: "video/mp4")
        let suite = "FullVideoInputTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var catalogRequests = 0
        var modelRequests = 0
        let service = AIService(defaults: defaults, apiKeyOverride: "test-key", requestLoader: { request in
            catalogRequests += 1
            XCTAssertEqual(request.url?.path, "/v1/models")
            XCTAssertNil(request.httpBody)
            let catalog = Data(#"{"data":[{"id":"fixture-native-video","supports_vision":true}]}"#.utf8)
            return try (catalog, XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)))
        }, agentStreamLoader: { _, _, _, _ in
            modelRequests += 1
            return AsyncThrowingStream { $0.finish() }
        })
        let route = AIModelRoute(tier: .standard, provider: .openAI, baseURL: "https://video-fixture.invalid/v1", model: "fixture-native-video", reason: "test")
        let historical = AgentConversationExchange(userText: "原视频", assistantText: "收到", images: [],
                                                   videos: [clip], imageAttachmentCount: 0, videoAttachmentCount: 1)
        for refersToHistory in [false, true] {
            do {
                _ = try await service.runAgent(text: "分析测试视频", images: [], videos: refersToHistory ? [] : [clip],
                                               hasVideo: !refersToHistory, history: refersToHistory ? [historical] : [],
                                               context: "", route: route, execute: { _ in throw AIServiceError.invalidResponse })
                XCTFail("Unverified capability must stop before the model request")
            } catch let error as ConversationMediaPreparationError {
                XCTAssertTrue(error.localizedDescription.contains("完整视频"))
            }
        }
        XCTAssertEqual(catalogRequests, 2)
        XCTAssertEqual(modelRequests, 0)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testVideoCatalogConfirmationIsCachedAndPreservesWholeCurrentAndHistoricalVideo() async throws {
        let url = try await SyntheticVideoFixture.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let clip = AgentVideoInput(data: data, mimeType: "video/mp4")
        let suite = "FullVideoInputTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var catalogRequests = 0
        let service = AIService(defaults: defaults, apiKeyOverride: "test-key", requestLoader: { request in
            catalogRequests += 1
            let catalog = Data(#"{"data":[{"id":"fixture-video","input_modalities":["text","video"]}]}"#.utf8)
            let url = try XCTUnwrap(request.url)
            return try (catalog, XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        })
        let route = AIModelRoute(tier: .standard, provider: .openAI, baseURL: "https://video-fixture.invalid/v1", model: "fixture-video", reason: "test")
        let historic = AgentConversationExchange(userText: "原视频", assistantText: "收到", images: [],
                                                 videos: [clip], imageAttachmentCount: 0, videoAttachmentCount: 1)
        let request = AgentRunPreparationRequest(text: "比较前后两个视频", images: [], videos: [clip], hasVideo: true,
                                                 history: [historic], context: "", requestedRoute: route)

        let prepared = try await service.prepareAgentRun(request)
        XCTAssertEqual(prepared.videos.map(\.data), [data, data])
        let indices = try prepared.videos.map { try XCTUnwrap($0.messageIndex) }
        XCTAssertLessThan(try XCTUnwrap(indices.first), try XCTUnwrap(indices.last))
        _ = try await service.prepareAgentRun(request)
        XCTAssertEqual(catalogRequests, 1)
    }

    func testInitialVideoRejectionAllowsSelectingAnotherModelButKeepsCompletedWorkBound() throws {
        let spaces = DataSpaceController(isStoredInMemoryOnly: true)
        let modelContext = try XCTUnwrap(spaces.personalContainer).mainContext
        let session = ConversationSession()
        modelContext.insert(session)
        let ai = AIService(apiKeyOverride: "test-key")
        let context = ConversationProcessingContext(structuredContext: "", session: session, dataSpace: .personal,
                                                    gyms: [], equipment: [], ai: ai, modelContext: modelContext)
        let processor = ConversationProcessingService()
        let route = AIModelRoute(tier: .standard, provider: .openAI, baseURL: "https://video-fixture.invalid/v1", model: "rejected-video", reason: "test")
        let media = PreparedConversationMedia(attachments: [], frames: [], videos: [], imageCount: 0, videoCount: 0, mode: .text)
        let rejection = StreamingFailure.interrupted(ConversationMediaPreparationError.nativeVideoUnsupported,
                                                     passage: "", reasoning: "", receivedMeaningfulDelta: false)
        for completedSteps in [0, 1] {
            let job = AgentJob(turnID: UUID(), sessionID: session.id, userMessageID: UUID(), dataSpace: .personal,
                               state: .running, userText: "合成视频", mediaAttachments: [],
                               contextSnapshot: .init(structuredContext: "", includeLocation: false))
            var checkpoint = AgentLoopCheckpoint.empty
            checkpoint.route = route
            checkpoint.extraConfigJSON = "{}"
            checkpoint.lastCompletedStep = completedSteps
            job.loopCheckpoint = checkpoint
            let reply = CoachMessage(sessionID: session.id, isFromCoach: true, text: "", turnID: job.turnID)
            modelContext.insert(job)
            modelContext.insert(reply)
            processor.handleAttemptFailure(rejection, job: job, responseMessage: reply, activeTrace: nil,
                                           performedRecordType: nil, media: media, context: context)
            XCTAssertEqual(job.state, .waitingForUser)
            let saved = try XCTUnwrap(job.loopCheckpoint)
            XCTAssertEqual(saved.route, completedSteps == 0 ? nil : route)
            XCTAssertEqual(saved.extraConfigJSON, completedSteps == 0 ? nil : "{}")
            XCTAssertEqual(saved.lastCompletedStep, completedSteps)
        }
    }

    func testUnavailableVideoBlocksInsteadOfPreparingKeyframes() async {
        let service = ConversationProcessingService()
        let media = await service.prepareStoredMedia([
            .init(kind: .video, path: "missing-fictional-video.mp4")
        ], frameLimit: 4)
        XCTAssertEqual(media.preparationFailure, .attachmentUnavailable)
        XCTAssertTrue(media.frames.isEmpty)
        XCTAssertTrue(media.videos.isEmpty)
        XCTAssertNotEqual(media.mode, .keyframes)
    }

    func testMissingCurrentImageCannotSilentlyShiftOtherImages() async throws {
        let (photo, bytes) = try temporaryPhoto()
        defer { try? FileManager.default.removeItem(at: photo) }
        let media = await ConversationProcessingService().prepareStoredMedia([
            .init(kind: .image, path: "nonexistent-\(UUID()).jpg"), .init(kind: .image, path: photo.path)
        ], frameLimit: 4)
        XCTAssertEqual(media.frames, [bytes])
        XCTAssertEqual(media.preparationFailure, .attachmentUnavailable)
    }

    func testHistoricalPhotoReferenceIgnoresAnUnrequestedVideoAndPreservesPhotoNumber() async throws {
        let (photo, bytes) = try temporaryPhoto()
        defer { try? FileManager.default.removeItem(at: photo) }
        let old = ConversationContextProjection.Exchange(turnID: UUID(), userText: "多件附件", mediaAttachments: [
            .init(kind: .image, path: "nonexistent-\(UUID()).jpg"),
            .init(kind: .video, path: "nonexistent-\(UUID()).mp4"),
            .init(kind: .image, path: photo.path)
        ])
        let service = ConversationProcessingService()
        let second = await service.prepareAgentHistory([old], selectedTurnIDs: [old.turnID], frameLimit: 4, currentText: "之前的第二张图片")
        let context = try XCTUnwrap(second.first)
        XCTAssertEqual(context.images, [bytes])
        XCTAssertTrue(context.userText.contains("第 2 张"))
        XCTAssertNil(context.mediaPreparationFailure)
        let first = await service.prepareAgentHistory([old], selectedTurnIDs: [old.turnID], frameLimit: 4, currentText: "之前的第一张图片")
        XCTAssertEqual(first.first?.mediaPreparationFailure, .historicalAttachmentUnavailable)
        XCTAssertEqual(first.first?.images.count, 0)
    }

    func testEvictedPhotoCanBeRecoveredFromTheSameSessionAndReportsWhenDeleted() async throws {
        let (photo, bytes) = try temporaryPhoto()
        defer { try? FileManager.default.removeItem(at: photo) }
        let (unrelatedPhoto, _) = try temporaryPhoto(color: .blue)
        defer { try? FileManager.default.removeItem(at: unrelatedPhoto) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.soma.media-recovery.\(UUID())"))
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        let modelContext = spaces.personalContainer.mainContext
        let date = Date(timeIntervalSince1970: 100_000)
        let session = ConversationSession(startedAt: date)
        let otherSession = ConversationSession(startedAt: date)
        modelContext.insert(session)
        modelContext.insert(otherSession)
        let originalID = UUID()
        let original = CoachMessage(date: date, sessionID: session.id, isFromCoach: false, text: "虚构旧媒体", turnID: originalID)
        original.mediaAttachments = [.init(kind: .image, path: unrelatedPhoto.path), .init(kind: .image, path: photo.path)]
        modelContext.insert(original)
        let other = CoachMessage(date: date, sessionID: otherSession.id, isFromCoach: false, text: "另一会话的虚构媒体", turnID: UUID())
        other.mediaAttachments = [.init(kind: .image, path: unrelatedPhoto.path)]
        modelContext.insert(other)
        for offset in 1 ... 31 {
            modelContext.insert(CoachMessage(date: date.addingTimeInterval(Double(offset)), sessionID: session.id,
                                             isFromCoach: false, text: "第 \(offset) 轮", turnID: UUID()))
        }
        let processing = ConversationProcessingContext(structuredContext: "", session: session, dataSpace: .personal, gyms: [], equipment: [],
                                                       ai: AIService(apiKeyOverride: "test-key"), modelContext: modelContext)
        try modelContext.save()
        let service = ConversationProcessingService()
        let current = UUID()
        let text = "看前面发的第二张图片"
        let history = await service.prepareHistory(excludingTurnID: current, currentFrameCount: 0, currentText: text,
                                                   hasCurrentMedia: false, selectedHistoricalTurnIDs: nil, context: processing)
        XCTAssertTrue(history.projection.evictedExchanges.contains { $0.turnID == originalID })
        XCTAssertEqual(history.history.first?.turnID, originalID)
        XCTAssertEqual(history.history.first?.images, [bytes])
        XCTAssertNil(history.mediaPreparationFailure)
        XCTAssertFalse(history.history.contains { $0.turnID == other.turnID })

        try FileManager.default.removeItem(at: photo)
        let missing = await service.prepareHistory(excludingTurnID: current, currentFrameCount: 0, currentText: text,
                                                   hasCurrentMedia: false, selectedHistoricalTurnIDs: [originalID], context: processing)
        XCTAssertEqual(missing.mediaPreparationFailure, .historicalAttachmentUnavailable)
        XCTAssertTrue(missing.history.allSatisfy(\.images.isEmpty))
        XCTAssertTrue(try AppErrorMessage.message(for: XCTUnwrap(missing.mediaPreparationFailure), operation: .model).contains("重新选择原件"))
    }

    private func temporaryPhoto(color: UIColor = .orange) throws -> (URL, Data) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).pngData { output in
            color.setFill()
            output.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        try bytes.write(to: url)
        return (url, bytes)
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

    func testQuickTimeVideoConversionPreservesTimelineAndOriginal() async throws {
        let source = try await SyntheticVideoFixture.make(quickTime: true)
        let mp4 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: mp4)
        }
        let original = try Data(contentsOf: source)
        let preparedVideo = await DirectVideoPreparer.input(for: source, capability: .standard)
        let converted = try XCTUnwrap(preparedVideo)
        XCTAssertEqual(converted.mimeType, "video/mp4")
        try converted.data.write(to: mp4)
        let originalDuration = try await AVURLAsset(url: source).load(.duration)
        let convertedDuration = try await AVURLAsset(url: mp4).load(.duration)
        XCTAssertEqual(convertedDuration.seconds, originalDuration.seconds, accuracy: 1.0 / 30)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testCorruptMP4DoesNotBecomeSuccessfulVideoInput() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data("not a video".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let video = await DirectVideoPreparer.input(for: url, capability: .standard)
        XCTAssertNil(video)
    }
}
