@preconcurrency import AVFoundation
import Speech

@available(iOS 26.0, *)
@MainActor
final class AppleSpeechAnalyzerSession: LocalSpeechSession {
    private let locale: Locale
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var installation: AssetInstallationRequest?
    private var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
    private var tasks: [Task<Void, Never>] = []
    private var converter: SpeechPCMConverter?
    private var hasTap = false
    private var ownsAudioSession = false
    private var cancelled = false

    init(locale: Locale) {
        self.locale = locale
    }

    func start(
        onResult: @escaping (String, Bool, TimeInterval) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: true)
        let modules: [any SpeechModule] = [transcriber, detector]
        do {
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                self.installation = installation
                try await installation.downloadAndInstall()
                self.installation = nil
            }
        } catch {
            throw SpeechInputError.localModelUnavailable
        }
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true)
        ownsAudioSession = true
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules, considering: inputFormat)
        else { throw SpeechInputError.audioInputUnavailable }
        let analyzer = SpeechAnalyzer(modules: modules)
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: format)
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingNewest(128))
        self.continuation = continuation
        let converter = try SpeechPCMConverter(from: inputFormat, to: format)
        self.converter = converter
        tasks.append(Task {
            do {
                var committedEnd = -Double.infinity
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    let start = result.range.start.seconds
                    let end = CMTimeRangeGetEnd(result.range).seconds
                    guard end > committedEnd else { continue }
                    let pause = committedEnd.isFinite ? max(0, start - committedEnd) : 0
                    onResult(String(result.text.characters), result.isFinal, pause)
                    if result.isFinal {
                        committedEnd = end
                    }
                }
            } catch {
                if !Task.isCancelled {
                    onError(error)
                }
            }
        })
        tasks.append(Task {
            do {
                var lastSpeechEnd: TimeInterval?
                var finalizedSpeechEnd: TimeInterval?
                for try await result in detector.results {
                    try Task.checkCancellation()
                    let end = CMTimeRangeGetEnd(result.range).seconds
                    if result.speechDetected {
                        lastSpeechEnd = end
                    } else if let lastSpeechEnd,
                              end - lastSpeechEnd >= 0.9,
                              finalizedSpeechEnd != lastSpeechEnd
                    {
                        try await analyzer.finalize(through: CMTimeRangeGetEnd(result.range))
                        finalizedSpeechEnd = lastSpeechEnd
                    }
                }
            } catch {
                if !Task.isCancelled {
                    onError(error)
                }
            }
        })
        tasks.append(Task {
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                if !Task.isCancelled {
                    onError(error)
                }
            }
        })
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            do {
                let converted = try converter.convert(buffer)
                guard converted.frameLength > 0 else { return }
                if case .dropped = continuation.yield(AnalyzerInput(buffer: converted)) {
                    continuation.finish(throwing: SpeechInputError.audioInputUnavailable)
                }
            } catch { continuation.finish(throwing: error) }
        }
        hasTap = true
        engine.prepare()
        try engine.start()
    }

    func finish() async {
        guard !cancelled else { return }
        engine.stop()
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        if let tail = try? converter?.finish(), tail.frameLength > 0 {
            continuation?.yield(AnalyzerInput(buffer: tail))
        }
        continuation?.finish()
        guard let analyzer else { cancel(); return }
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            await analyzer.cancelAndFinishNow()
        }
        defer { timeout.cancel(); cancel() }
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        for task in tasks {
            await task.value
        }
    }

    func cancel() {
        cancelled = true
        installation?.progress.cancel()
        installation = nil
        engine.stop()
        if hasTap {
            engine.inputNode.removeTap(onBus: 0); hasTap = false
        }
        continuation?.finish()
        continuation = nil
        converter = nil
        tasks.forEach { $0.cancel() }
        tasks = []
        if let analyzer {
            self.analyzer = nil
            Task { await analyzer.cancelAndFinishNow() }
        }
        if ownsAudioSession, AVAudioSession.sharedInstance().category == .record {
            ownsAudioSession = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

/// Converter is confined to the audio tap; the lock also makes test use explicit.
final class SpeechPCMConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let lock = NSLock()

    init(from source: AVAudioFormat, to destination: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: source, to: destination) else {
            throw SpeechInputError.audioInputUnavailable
        }
        self.converter = converter
        outputFormat = destination
        converter.primeMethod = .none
    }

    func finish() throws -> AVAudioPCMBuffer {
        lock.lock()
        defer { lock.unlock() }
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096) else {
            throw SpeechInputError.audioInputUnavailable
        }
        var error: NSError?
        converter.convert(to: output, error: &error) { _, state in
            state.pointee = .endOfStream
            return nil
        }
        if let error {
            throw error
        }
        return output
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        lock.lock()
        defer { lock.unlock() }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw SpeechInputError.audioInputUnavailable
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied {
                state.pointee = .noDataNow; return nil
            }
            supplied = true
            state.pointee = .haveData
            return buffer
        }
        if let error {
            throw error
        }
        guard status != .error else { throw SpeechInputError.audioInputUnavailable }
        return output
    }
}
