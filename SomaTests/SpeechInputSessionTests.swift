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

    func testFinalSegmentsAppendToLiveDraftAndLateCallbacksAreIgnored() async {
        let session = Session()
        let started = expectation(description: "local session started")
        session.started = started
        let state = CoachComposerState()
        state.draft = "手动输入"
        let service = SpeechInputService(sessionFactory: { session }, microphonePermission: { true })
        state.speechInput = service
        service.start { state.appendSpeechSegment($0, pause: $1) }
        await fulfillment(of: [started], timeout: 2)
        session.result?("错误猜测", false, 0)
        XCTAssertEqual(state.draft, "手动输入")
        XCTAssertEqual(state.displayedSpeechDraft, "手动输入错误猜测")
        state.replaceDraftFromSpeechPreview("手动输入")
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

    func testSessionChangeClearsPendingSpeechAndRejectsOldResults() async throws {
        let session = Session()
        session.started = expectation(description: "started")
        let state = CoachComposerState()
        let service = SpeechInputService(sessionFactory: { session }, microphonePermission: { true })
        state.speechInput = service
        service.start { state.appendSpeechSegment($0, pause: $1) }
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
        state.speechInput = service
        service.start { state.appendSpeechSegment($0, pause: $1) }
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
