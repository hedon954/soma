import AVFoundation
import Speech

/// Compatibility path for older systems and hardware; never enables cloud recognition.
@MainActor
final class LegacyLocalSpeechSession: LocalSpeechSession {
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var generation = UUID()
    private var hasTap = false
    private var ownsAudioSession = false
    private var cancelled = false
    private var onResult: ((String, Bool, TimeInterval) -> Void)?
    private var onError: ((Error) -> Void)?
    private var pending = ""
    private var lastAudioEnd: TimeInterval = 0
    private var previousPhraseAt: Date?
    private var phrasePause: TimeInterval?

    func start(
        onResult: @escaping (String, Bool, TimeInterval) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        guard status == .authorized else { throw SpeechInputError.speechPermissionDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition
        else { throw SpeechInputError.recognizerUnavailable }
        self.recognizer = recognizer
        self.onResult = onResult
        self.onError = onError
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true)
        ownsAudioSession = true
        try beginPhrase()
    }

    private func beginPhrase() throws {
        endPhrase()
        pending = ""
        lastAudioEnd = 0
        phrasePause = nil
        let token = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.request = request
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechInputError.audioInputUnavailable
        }
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        hasTap = true
        engine.prepare()
        try engine.start()
        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, generation == token, !cancelled else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    let audioEnd = result.bestTranscription.segments.last.map { $0.timestamp + $0.duration } ?? 0
                    if phrasePause == nil {
                        phrasePause = previousPhraseAt.map { max(0, Date.now.timeIntervalSince($0) - audioEnd) } ?? 0
                    }
                    let pause = phrasePause ?? 0
                    pending = text
                    onResult?(text, result.isFinal, pause)
                    if result.isFinal {
                        pending = ""
                        previousPhraseAt = .now
                        restart()
                    } else if audioEnd > lastAudioEnd {
                        lastAudioEnd = audioEnd
                        schedulePause(token: token, pause: pause)
                    }
                } else if error != nil {
                    onError?(SpeechInputError.recognizerUnavailable)
                }
            }
        }
    }

    private func schedulePause(token: UUID, pause: TimeInterval) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.1)) } catch { return }
            guard let self, generation == token, !cancelled else { return }
            onResult?(pending, true, pause)
            pending = ""
            previousPhraseAt = .now
            restart()
        }
    }

    private func restart() {
        do { try beginPhrase() } catch { onError?(error) }
    }

    private func endPhrase() {
        generation = UUID()
        silenceTask?.cancel()
        silenceTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        request?.endAudio()
        request = nil
        engine.stop()
        if hasTap {
            engine.inputNode.removeTap(onBus: 0); hasTap = false
        }
    }

    func cancel() {
        cancelled = true
        endPhrase()
        pending = ""
        onResult = nil
        onError = nil
        if ownsAudioSession, AVAudioSession.sharedInstance().category == .record {
            ownsAudioSession = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
