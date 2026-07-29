import AVFoundation
import Observation
import Speech

enum SpeechInputError: LocalizedError {
    case recognizerUnavailable
    case speechPermissionDenied
    case microphonePermissionDenied
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            "系统语音识别暂不可用，请稍后重试。"
        case .speechPermissionDenied:
            "需要在系统设置中允许语音识别。"
        case .microphonePermissionDenied:
            "需要在系统设置中允许麦克风访问。"
        case .audioInputUnavailable:
            "当前没有可用的音频输入。"
        }
    }
}

@MainActor
@Observable
final class SpeechInputService {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledTap = false

    var transcript = ""
    var isListening = false
    var errorMessage: String?

    func start() async {
        guard !isListening else { return }
        errorMessage = nil
        transcript = ""

        do {
            try await authorize()
            try beginRecognition()
        } catch {
            stop()
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func authorize() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            throw SpeechInputError.speechPermissionDenied
        }

        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard microphoneGranted else {
            throw SpeechInputError.microphonePermissionDenied
        }
    }

    private func beginRecognition() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechInputError.recognizerUnavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechInputError.audioInputUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        hasInstalledTap = true

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.stop()
                }
            }
        }
    }
}
