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

/// Speech.framework may revise a partial result backwards and starts a new
/// transcription after a pause. Only the current partial is replaceable;
/// finalized segments are immutable user text.
struct SpeechTranscriptAccumulator: Equatable {
    static let pauseBoundary: TimeInterval = 0.85

    private(set) var committedSegments: [String] = []
    private(set) var currentPartial = ""
    private var lastFinalSource: String?
    private var lastPartialAt: Date?
    private var lastSpeechSegmentEnd: TimeInterval?
    private(set) var speechActivityRevision: UInt64 = 0

    mutating func reset() {
        committedSegments = []
        currentPartial = ""
        lastFinalSource = nil
        lastPartialAt = nil
        lastSpeechSegmentEnd = nil
        speechActivityRevision = 0
    }

    @discardableResult
    mutating func receive(
        _ value: String,
        isFinal: Bool,
        at receivedAt: Date = .now,
        speechSegmentStart: TimeInterval? = nil,
        speechSegmentEnd: TimeInterval? = nil
    ) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return transcript }
        if isFinal {
            currentPartial = ""
            guard normalized != lastFinalSource else { return transcript }
            committedSegments.append(Self.withPausePunctuation(normalized))
            lastFinalSource = normalized
            lastPartialAt = nil
            lastSpeechSegmentEnd = nil
        } else {
            // Speech.framework may repeat an unchanged partial while the user
            // is already silent. Treating that callback as fresh speech keeps
            // postponing the pause timer and lets the later suffix replace the
            // earlier phrase. An identical callback is not new evidence.
            let speechAdvanced = speechDidAdvance(
                normalized,
                speechSegmentEnd: speechSegmentEnd
            )
            guard normalized != currentPartial else {
                recordSpeechActivity(
                    at: receivedAt,
                    speechSegmentEnd: speechSegmentEnd,
                    didAdvance: speechAdvanced
                )
                return transcript
            }
            // A recognizer can temporarily retract words while refining the
            // same audio. Keeping that shorter snapshot visible makes already
            // displayed dictation appear to be overwritten, and used to move
            // the silence boundary as well. With no newer acoustic evidence,
            // retain the longer current tail until a real correction/final or
            // the next spoken segment arrives.
            let isBackwardRevision = currentPartial.hasPrefix(normalized)
                && normalized.count < currentPartial.count
                && !speechAdvanced
            guard !isBackwardRevision else { return transcript }
            if startsNewSegment(
                normalized,
                at: receivedAt,
                speechSegmentStart: speechSegmentStart
            ) {
                committedSegments.append(Self.withPausePunctuation(currentPartial))
            }
            currentPartial = normalized
            recordSpeechActivity(
                at: receivedAt,
                speechSegmentEnd: speechSegmentEnd,
                didAdvance: speechAdvanced
            )
            // A new partial marks a new recognition segment; an identical
            // spoken phrase is allowed to be committed again afterward.
            lastFinalSource = nil
        }
        return transcript
    }

    private func speechDidAdvance(
        _ value: String,
        speechSegmentEnd: TimeInterval?
    ) -> Bool {
        if let speechSegmentEnd {
            guard let lastSpeechSegmentEnd else { return true }
            return speechSegmentEnd > lastSpeechSegmentEnd + 0.01
        }
        guard !currentPartial.isEmpty else { return true }
        return value.count > currentPartial.count
    }

    private mutating func recordSpeechActivity(
        at receivedAt: Date,
        speechSegmentEnd: TimeInterval?,
        didAdvance: Bool
    ) {
        guard didAdvance else { return }
        lastPartialAt = receivedAt
        if let speechSegmentEnd {
            lastSpeechSegmentEnd = speechSegmentEnd
        }
        speechActivityRevision &+= 1
    }

    @discardableResult
    mutating func commitCurrent(addsPausePunctuation: Bool = false) -> String {
        let value = currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            committedSegments.append(
                addsPausePunctuation ? Self.withPausePunctuation(value) : value
            )
        }
        currentPartial = ""
        lastFinalSource = nil
        lastPartialAt = nil
        lastSpeechSegmentEnd = nil
        return transcript
    }

    var transcript: String {
        (committedSegments + (currentPartial.isEmpty ? [] : [currentPartial]))
            .joined()
    }

    private static func withPausePunctuation(_ value: String) -> String {
        let punctuation = CharacterSet(charactersIn: "。！？!?；;，,：:")
        guard let scalar = value.unicodeScalars.last,
              !punctuation.contains(scalar)
        else {
            return value
        }
        return value + "，"
    }

    /// Some Speech.framework sessions start the next utterance from an empty
    /// source after a pause without first delivering `isFinal`. Treat only a
    /// time-separated, unrelated partial as a new segment. Normal prefix
    /// growth and recognizer backtracking stay replaceable within the current
    /// segment, so corrections do not duplicate text.
    private func startsNewSegment(
        _ value: String,
        at receivedAt: Date,
        speechSegmentStart: TimeInterval?
    ) -> Bool {
        guard !currentPartial.isEmpty,
              value != currentPartial
        else {
            return false
        }
        let unrelated = !value.hasPrefix(currentPartial)
            && !currentPartial.hasPrefix(value)
        guard unrelated else { return false }
        let callbackPause = lastPartialAt.map {
            receivedAt.timeIntervalSince($0) >= Self.pauseBoundary
        } ?? false
        let acousticPause: Bool = if let speechSegmentStart, let lastSpeechSegmentEnd {
            speechSegmentStart - lastSpeechSegmentEnd
                >= Self.pauseBoundary
        } else {
            false
        }
        return callbackPause || acousticPause
    }
}

@MainActor
@Observable
final class SpeechInputService {
    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceCommitTask: Task<Void, Never>?
    private var hasInstalledTap = false
    private var recognitionGeneration = UUID()
    private var accumulator = SpeechTranscriptAccumulator()

    var transcript = ""
    var isListening = false
    var errorMessage: String?

    func start() async {
        guard !isListening else { return }
        errorMessage = nil
        accumulator.reset()
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
        transcript = accumulator.commitCurrent()
        recognitionGeneration = UUID()
        tearDownRecognitionCycle(cancelTask: true)
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

        tearDownRecognitionCycle(cancelTask: true, deactivateAudioSession: false)

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
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

        let generation = UUID()
        recognitionGeneration = generation

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.recognitionGeneration == generation else { return }
                if let result {
                    let latest = result.bestTranscription.formattedString
                    let segments = result.bestTranscription.segments
                    let activityRevision = self.accumulator.speechActivityRevision
                    let accumulated = self.accumulator.receive(
                        latest,
                        isFinal: result.isFinal,
                        speechSegmentStart: segments.first?.timestamp,
                        speechSegmentEnd: segments.last.map {
                            $0.timestamp + $0.duration
                        }
                    )
                    if self.transcript != accumulated {
                        self.transcript = accumulated
                    }
                    if result.isFinal {
                        self.silenceCommitTask?.cancel()
                        self.silenceCommitTask = nil
                    } else if self.accumulator.speechActivityRevision
                        != activityRevision
                    {
                        self.scheduleSilenceCommit(generation: generation)
                    }
                }
                if result?.isFinal == true, self.isListening {
                    self.restartRecognitionAfterPause(generation: generation)
                } else if error != nil {
                    self.stop()
                    self.errorMessage = SpeechInputError.recognizerUnavailable.localizedDescription
                }
            }
        }
    }

    private func restartRecognitionAfterPause(generation: UUID) {
        guard isListening, recognitionGeneration == generation else { return }
        do {
            try beginRecognition()
        } catch {
            stop()
            errorMessage = error.localizedDescription
        }
    }

    /// Speech.framework does not guarantee an `isFinal` callback before a
    /// post-pause transcription starts over. Commit the current partial after
    /// a real silence window and rotate the request, so the next utterance can
    /// only append to the immutable prefix.
    private func scheduleSilenceCommit(generation: UUID) {
        silenceCommitTask?.cancel()
        silenceCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: .seconds(SpeechTranscriptAccumulator.pauseBoundary)
            )
            guard !Task.isCancelled,
                  let self,
                  isListening,
                  recognitionGeneration == generation
            else {
                return
            }
            let committed = accumulator.commitCurrent(
                addsPausePunctuation: true
            )
            if transcript != committed {
                transcript = committed
            }
            silenceCommitTask = nil
            restartRecognitionAfterPause(generation: generation)
        }
    }

    private func tearDownRecognitionCycle(
        cancelTask: Bool,
        deactivateAudioSession: Bool = false
    ) {
        silenceCommitTask?.cancel()
        silenceCommitTask = nil
        recognitionRequest?.endAudio()
        if cancelTask {
            recognitionTask?.cancel()
        }
        recognitionRequest = nil
        recognitionTask = nil
        if let audioEngine {
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            if hasInstalledTap {
                audioEngine.inputNode.removeTap(onBus: 0)
                hasInstalledTap = false
            }
        }
        if deactivateAudioSession {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }
}
