import AVFoundation
@testable import Soma
import XCTest

@MainActor
final class SpeechInputSessionTests: XCTestCase {
    private final class Session: LocalSpeechSession {
        var result: ((String, Bool, TimeInterval) -> Void)?
        var started: XCTestExpectation?
        var cancelCount = 0
        var finalText: String?
        func start(onResult: @escaping (String, Bool, TimeInterval) -> Void, onError _: @escaping (Error) -> Void) async throws {
            result = onResult
            started?.fulfill()
        }

        func cancel() {
            cancelCount += 1
        }

        func finish() async {
            if let finalText {
                result?(finalText, true, 0)
            }
        }
    }

    func testEmptyDraftShowsLivePreviewBeforeFinish() async {
        let session = Session()
        let started = expectation(description: "local session started")
        session.started = started
        let state = CoachComposerState()
        let service = SpeechInputService(sessionFactory: { session }, microphonePermission: { true })
        state.startSpeech(service)
        await fulfillment(of: [started], timeout: 2)
        session.result?("你好", false, 0)
        XCTAssertEqual(state.draft, "")
        XCTAssertEqual(state.displayedSpeechDraft, "你好")
        XCTAssertTrue(service.isListening)
        session.result?("你好你好", false, 0)
        XCTAssertEqual(state.draft, "")
        XCTAssertEqual(state.displayedSpeechDraft, "你好你好")
        await service.finish()
        XCTAssertEqual(state.draft, "你好你好")
        XCTAssertEqual(state.displayedSpeechDraft, "你好你好")
        XCTAssertFalse(service.isListening)
    }

    func testFinalSegmentsAppendToLiveDraftAndLateCallbacksAreIgnored() async {
        let session = Session()
        let started = expectation(description: "local session started")
        session.started = started
        let state = CoachComposerState()
        state.draft = "手动输入"
        let service = SpeechInputService(sessionFactory: { session }, microphonePermission: { true })
        state.startSpeech(service)
        await fulfillment(of: [started], timeout: 2)
        session.result?("错误猜测", false, 0)
        XCTAssertEqual(state.draft, "手动输入")
        XCTAssertEqual(state.displayedSpeechDraft, "手动输入错误猜测")
        state.draft = "改过的输入，"
        session.result?("准确结果", true, 0)
        XCTAssertEqual(state.draft, "改过的输入，准确结果")
        session.result?("最后一段", false, 1)
        service.stop()
        XCTAssertEqual(state.draft, "改过的输入，准确结果，最后一段")
        state.draft = "新输入"
        session.result?("迟到结果", true, 2)
        XCTAssertEqual(state.draft, "新输入")
        service.stop()
        XCTAssertEqual(state.draft, "新输入")
        XCTAssertEqual(session.cancelCount, 1)
    }

    func testEditingLivePreviewKeepsUserTextAndRejectsOldRecognition() async {
        let first = Session()
        let firstStarted = expectation(description: "first recognition started")
        first.started = firstStarted
        let next = Session()
        let nextStarted = expectation(description: "recognition restarts after manual correction")
        next.started = nextStarted
        var starts = 0
        let service = SpeechInputService(sessionFactory: {
            starts += 1
            return starts == 1 ? first : next
        }, microphonePermission: { true })
        let state = CoachComposerState()
        state.startSpeech(service)
        await fulfillment(of: [firstStarted], timeout: 2)
        first.result?("深吨五次", false, 0)
        let lateResult = first.result

        state.replaceDraftFromSpeechPreview("深蹲五次")
        XCTAssertEqual(state.draft, "深蹲五次")
        XCTAssertEqual(state.displayedSpeechDraft, "深蹲五次")
        await fulfillment(of: [nextStarted], timeout: 2)
        lateResult?("深吨五次。", true, 0)
        XCTAssertEqual(state.draft, "深蹲五次")
        next.result?("再做一组", false, 0)
        XCTAssertEqual(state.displayedSpeechDraft, "深蹲五次再做一组")
        await service.finish()
        XCTAssertEqual(state.draft, "深蹲五次再做一组")
        XCTAssertFalse(service.isListening)
    }

    func testSessionChangeClearsPendingSpeechAndRejectsOldResults() async throws {
        let session = Session()
        session.started = expectation(description: "started")
        let state = CoachComposerState()
        let service = SpeechInputService(sessionFactory: { session }, microphonePermission: { true })
        state.startSpeech(service)
        try await fulfillment(of: [XCTUnwrap(session.started)], timeout: 2)
        session.result?("旧会话尾句", false, 0)
        state.prepareForSessionChange()
        session.result?("旧会话尾句修订", true, 0)
        XCTAssertEqual(state.draft, "")
        XCTAssertFalse(service.isListening)
    }

    func testAudioConversionPreservesDurationAndProducesRequestedFormat() throws {
        let inputFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false))
        let outputFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4800))
        input.frameLength = 4800
        let samples = try XCTUnwrap(input.floatChannelData?[0])
        for index in 0 ..< 4800 {
            samples[index] = Float(sin(Double(index) * 0.1)) * 0.25
        }
        let converter = try SpeechPCMConverter(from: inputFormat, to: outputFormat)
        var frames = 0
        for _ in 0 ..< 10 {
            let output = try converter.convert(input)
            XCTAssertEqual(output.format, outputFormat)
            frames += Int(output.frameLength)
        }
        try frames += Int(converter.finish().frameLength)
        XCTAssertEqual(Double(frames) / 16000, 1, accuracy: 0.001)
    }

    func testFinishingAppendsFinalCorrectionOnceToCurrentDraft() async throws {
        let session = Session()
        session.started = expectation(description: "started")
        session.finalText = "完成训练。"
        let state = CoachComposerState()
        let service = SpeechInputService(sessionFactory: { session }, microphonePermission: { true })
        state.startSpeech(service)
        try await fulfillment(of: [XCTUnwrap(session.started)], timeout: 2)
        session.result?("完成寻", false, 0)
        state.draft = "今天，"
        await service.finish()
        XCTAssertEqual(state.draft, "今天，完成训练。")
        XCTAssertFalse(service.isListening)
        await service.finish()
        XCTAssertEqual(state.draft, "今天，完成训练。")
        XCTAssertEqual(SpeechDraftAppend.append("Next", to: "Done.", pause: 1), "Done. Next")
    }
}
