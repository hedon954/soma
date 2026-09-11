import AVFoundation
import Observation
import Speech

/// Session implementations never receive the composer's draft.
@MainActor
protocol LocalSpeechSession: AnyObject {
    func start(
        onResult: @escaping (String, Bool, TimeInterval) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws
    func cancel()
    func finish() async
}

extension LocalSpeechSession {
    func finish() async {
        cancel()
    }
}

enum SpeechInputError: LocalizedError {
    case recognizerUnavailable
    case speechPermissionDenied
    case microphonePermissionDenied
    case audioInputUnavailable
    case localModelUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: "系统本地语音识别暂不可用，请稍后重试。"
        case .speechPermissionDenied: "需要在系统设置中允许语音识别。"
        case .microphonePermissionDenied: "需要在系统设置中允许麦克风访问。"
        case .audioInputUnavailable: "当前没有可用的音频输入。"
        case .localModelUnavailable: "本地中文语音模型尚不可用，请联网完成系统模型下载后重试。"
        }
    }
}

/// Only the current unconfirmed phrase is retained. Committed text belongs to the editor.
@MainActor
@Observable
final class SpeechInputService {
    private let sessionFactory: () async -> any LocalSpeechSession
    private let microphonePermission: () async -> Bool

    init(
        sessionFactory: (() async -> any LocalSpeechSession)? = nil,
        microphonePermission: (() async -> Bool)? = nil
    ) {
        self.sessionFactory = sessionFactory ?? Self.defaultSession
        self.microphonePermission = microphonePermission ?? {
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
    }

    private static func defaultSession() async -> any LocalSpeechSession {
        if #available(iOS 26.0, *) {
            let localeHint = Locale(identifier: "zh-CN")
            if let locale = await DictationTranscriber.supportedLocale(equivalentTo: localeHint) {
                return AppleSpeechAnalyzerSession(locale: locale, module: .dictation)
            }
            if SpeechTranscriber.isAvailable,
               let locale = await SpeechTranscriber.supportedLocale(equivalentTo: localeHint)
            {
                return AppleSpeechAnalyzerSession(locale: locale, module: .transcription)
            }
        }
        return LegacyLocalSpeechSession()
    }

    private var session: (any LocalSpeechSession)?
    private var startTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var generation = UUID()
    private var isReady = false
    private var onCommit: ((String, TimeInterval) -> Void)?
    private var onPreview: ((String) -> Void)?
    private var pendingPause: TimeInterval = 0
    private(set) var pendingText = ""
    private(set) var isListening = false
    private(set) var statusMessage = ""
    var errorMessage: String?

    func start(
        onPreview: @escaping (String) -> Void = { _ in },
        onCommit: @escaping (String, TimeInterval) -> Void
    ) {
        guard !isListening else { return }
        stop()
        self.onPreview = onPreview
        self.onCommit = onCommit
        errorMessage = nil
        isListening = true
        statusMessage = ""
        let token = generation
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                let allowed = await microphonePermission()
                try Task.checkCancellation()
                guard allowed else { throw SpeechInputError.microphonePermissionDenied }
                let selected = await sessionFactory()
                try Task.checkCancellation()
                guard generation == token else { return }
                session = selected
                try await selected.start { [weak self] text, isFinal, pause in
                    guard let self, generation == token, isListening else { return }
                    pendingText = text
                    pendingPause = pause
                    onPreview(text)
                    if isFinal {
                        commitPending()
                    }
                } onError: { [weak self] error in
                    guard let self, generation == token else { return }
                    stop()
                    errorMessage = AppErrorMessage.message(for: error, operation: .speech)
                }
                try Task.checkCancellation()
                guard generation == token else { return }
                isReady = true
                statusMessage = ""
            } catch is CancellationError {
                return
            } catch {
                guard generation == token else { return }
                stop()
                errorMessage = AppErrorMessage.message(for: error, operation: .speech)
            }
        }
    }

    func finish() async {
        if let finishTask {
            await finishTask.value; return
        }
        guard isListening else { return }
        guard isReady else { stop(); return }
        let token = generation
        statusMessage = ""
        let task = Task { [weak self] in
            guard let self else { return }
            if let startTask {
                await startTask.value
            }
            guard generation == token, !Task.isCancelled else { return }
            await session?.finish()
            guard generation == token, !Task.isCancelled else { return }
            finishTask = nil
            stop()
        }
        finishTask = task
        await task.value
    }

    func stop() {
        commitPending()
        generation = UUID()
        finishTask?.cancel()
        finishTask = nil
        startTask?.cancel()
        startTask = nil
        session?.cancel()
        session = nil
        onCommit = nil
        onPreview = nil
        isListening = false
        isReady = false
        statusMessage = ""
    }

    func discardPending() {
        pendingText = ""
        pendingPause = 0
    }

    /// A manual edit makes the displayed phrase authoritative. Retire its recognition
    /// generation so a late partial/final can never restore the pre-edit phrase.
    func continueAfterManualEdit() {
        guard isListening, let onCommit, let onPreview else {
            discardPending()
            return
        }
        discardPending()
        onPreview("")
        stop()
        start(onPreview: onPreview, onCommit: onCommit)
    }

    private func commitPending() {
        let text = pendingText
        pendingText = ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onCommit?(text, pendingPause)
        pendingPause = 0
    }
}

/// Applies only to today's editor contents; there is no baseline or transcript cache.
enum SpeechDraftAppend {
    static func append(_ segment: String, to current: String, pause: TimeInterval) -> String {
        var segment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else { return current }
        guard let last = current.last else { return segment }
        let punctuation = "。！？!?；;，,：:、."
        if punctuation.contains(last) {
            while let first = segment.first, punctuation.contains(first) {
                segment.removeFirst()
            }
        }
        guard let first = segment.first else { return current }
        let separator: String = if ".!?;,:".contains(last), isASCIIWord(first) {
            " "
        } else if last.isWhitespace || punctuation.contains(last) || punctuation.contains(first) {
            ""
        } else if pause >= 1.6 {
            isASCIIWord(last) && isASCIIWord(first) ? ". " : "。"
        } else if pause >= 0.55 {
            isASCIIWord(last) && isASCIIWord(first) ? ", " : "，"
        } else if isASCIIWord(last), isASCIIWord(first) {
            " "
        } else {
            ""
        }
        return current + separator + segment
    }

    private static func isASCIIWord(_ value: Character) -> Bool {
        value.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    }
}
