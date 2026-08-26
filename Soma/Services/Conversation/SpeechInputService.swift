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
    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
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
        guard let audioEngine else {
            isListening = false
            return
        }
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
        let recognizer: SFSpeechRecognizer
        if let existingRecognizer = self.recognizer {
            recognizer = existingRecognizer
        } else if let newRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) {
            self.recognizer = newRecognizer
            recognizer = newRecognizer
        } else {
            throw SpeechInputError.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw SpeechInputError.recognizerUnavailable
        }

        let audioEngine: AVAudioEngine
        if let existingAudioEngine = self.audioEngine {
            audioEngine = existingAudioEngine
        } else {
            let newAudioEngine = AVAudioEngine()
            self.audioEngine = newAudioEngine
            audioEngine = newAudioEngine
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
                    let latest = result.bestTranscription.formattedString
                    // 系统会重复投递相同 partial；等值不写，避免无内容变化的
                    // Observation 失效传导到输入区。
                    if self.transcript != latest {
                        self.transcript = latest
                    }
                }
                if error != nil || result?.isFinal == true {
                    self.stop()
                }
            }
        }
    }
}
