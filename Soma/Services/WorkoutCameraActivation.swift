@preconcurrency import AVFoundation
import Foundation
import OSLog

struct WorkoutCameraSessionOwnerToken: Equatable, Sendable {
    let sessionID: UUID
    let generation: UUID
}

struct WorkoutCameraSessionOwnership: Equatable {
    private(set) var activeOwner: WorkoutCameraSessionOwnerToken?

    mutating func claim(
        sessionID: UUID
    ) -> WorkoutCameraSessionOwnerToken {
        let owner = WorkoutCameraSessionOwnerToken(
            sessionID: sessionID,
            generation: UUID()
        )
        activeOwner = owner
        return owner
    }

    func accepts(_ owner: WorkoutCameraSessionOwnerToken) -> Bool {
        activeOwner == owner
    }

    @discardableResult
    mutating func release(_ owner: WorkoutCameraSessionOwnerToken) -> Bool {
        guard accepts(owner) else { return false }
        activeOwner = nil
        return true
    }
}

enum WorkoutCaptureOrientation: String, Equatable, Sendable {
    case portrait
    case landscapeLeft
    case landscapeRight

    var aspectRatio: CGFloat {
        switch self {
        case .portrait:
            9 / 16
        case .landscapeLeft, .landscapeRight:
            16 / 9
        }
    }
}

struct WorkoutCaptureGeometry: Equatable, Sendable {
    var orientation: WorkoutCaptureOrientation
    var previewRotationAngle: Double
    var captureRotationAngle: Double
    var isMirrored: Bool

    static let portrait = WorkoutCaptureGeometry(
        orientation: .portrait,
        previewRotationAngle: 90,
        captureRotationAngle: 90,
        isMirrored: true
    )
}

enum WorkoutRecordingLifecycleTerminal: Equatable {
    case saved
    case failed
    case cancelled
}

enum WorkoutRecordingDelegateDisposition: Equatable {
    case persist
    case persistPartial(message: String)
    case fail
    case cancel
}

struct WorkoutRecordingAttemptLifecycle: Equatable {
    enum Phase: Equatable {
        case starting
        case recording
        case finishing
        case terminal(WorkoutRecordingLifecycleTerminal)
    }

    private(set) var phase: Phase = .starting
    private(set) var shouldDiscard = false
    private(set) var stopReason: WorkoutRecordingStopReason?

    var isTerminal: Bool {
        if case .terminal = phase {
            return true
        }
        return false
    }

    var isFinishing: Bool {
        phase == .finishing
    }

    mutating func markStarted() {
        guard !isTerminal, !isFinishing else { return }
        phase = .recording
    }

    mutating func requestStop(reason: WorkoutRecordingStopReason) {
        guard !isTerminal else { return }
        if stopReason == nil {
            stopReason = reason
        }
        if reason == .cancelled {
            shouldDiscard = true
        }
        phase = .finishing
    }

    func delegateDisposition(
        finishedSuccessfully: Bool
    ) -> WorkoutRecordingDelegateDisposition {
        if shouldDiscard {
            return .cancel
        }
        guard finishedSuccessfully else { return .fail }
        if let message = stopReason?.partialRecordingMessage {
            return .persistPartial(message: message)
        }
        return .persist
    }

    mutating func finish(_ terminal: WorkoutRecordingLifecycleTerminal) {
        if terminal == .cancelled {
            shouldDiscard = true
        }
        phase = .terminal(terminal)
    }

    mutating func failAfterFinishTimeout() {
        shouldDiscard = true
        phase = .terminal(.failed)
    }
}

enum WorkoutRecordingDiagnostics {
    private static let logger = Logger(
        subsystem: "top.hedon.soma",
        category: "GuidedWorkoutRecording"
    )

    static func failure(
        stage: String,
        attemptID: UUID? = nil,
        error: Error
    ) {
        logger.error("\(metadata(stage: stage, attemptID: attemptID, error: error), privacy: .public)")
    }

    static func breadcrumb(
        stage: String,
        attemptID: UUID? = nil,
        detail: String? = nil
    ) {
        let resolvedAttemptID = attemptID?.uuidString ?? "none"
        let resolvedDetail = detail ?? "none"
        logger.notice(
            "stage=\(stage, privacy: .public) attempt_id=\(resolvedAttemptID, privacy: .public) detail=\(resolvedDetail, privacy: .public)"
        )
    }

    static func metadata(
        stage: String,
        attemptID: UUID?,
        error: Error
    ) -> String {
        let nsError = error as NSError
        let type = String(reflecting: Swift.type(of: error))
        return "stage=\(stage) attempt_id=\(attemptID?.uuidString ?? "none") type=\(type) domain=\(nsError.domain) code=\(nsError.code)"
    }

    static func interruption(reason: String, attemptID: UUID? = nil) {
        logger.error(
            "stage=interruption attempt_id=\(attemptID?.uuidString ?? "none", privacy: .public) reason=\(reason, privacy: .public)"
        )
    }
}

/// Owns the identity of the one capture activation that is allowed to publish
/// results. AVFoundation's `startRunning()` is synchronous and cannot be
/// force-cancelled, so an expired generation must be rejected when it returns
/// late instead of mutating the replacement capture session.
struct WorkoutCameraActivationGenerationGate: Equatable {
    private(set) var activeGeneration: UUID?

    mutating func begin() -> UUID {
        let generation = UUID()
        activeGeneration = generation
        return generation
    }

    mutating func accept(_ generation: UUID) -> Bool {
        guard activeGeneration == generation else { return false }
        activeGeneration = nil
        return true
    }

    mutating func expire(_ generation: UUID) -> Bool {
        accept(generation)
    }

    @discardableResult
    mutating func supersede() -> UUID? {
        defer { activeGeneration = nil }
        return activeGeneration
    }

    func isCurrent(_ generation: UUID) -> Bool {
        activeGeneration == generation
    }
}

struct WorkoutCameraRecordingReadiness: Equatable, Sendable {
    var sessionIsRunning: Bool
    var sessionIsInterrupted: Bool
    var hasVideoConnection: Bool
    var videoConnectionIsEnabled: Bool
    var videoConnectionIsActive: Bool
    var outputIsRecording: Bool
}

enum WorkoutCameraRecordingReadinessFailure: String, Equatable, Sendable {
    case sessionNotRunning
    case sessionInterrupted
    case videoConnectionMissing
    case videoConnectionDisabled
    case videoConnectionInactive
    case outputAlreadyRecording

    var userFacingReason: String {
        switch self {
        case .sessionNotRunning:
            "相机会话未启动"
        case .sessionInterrupted:
            "相机正被系统中断"
        case .videoConnectionMissing:
            "录像连接缺失"
        case .videoConnectionDisabled, .videoConnectionInactive:
            "录像连接尚未激活"
        case .outputAlreadyRecording:
            "已有录像正在占用相机"
        }
    }
}

extension WorkoutCameraRecordingReadiness {
    var diagnosticDetail: String {
        [
            "running=\(sessionIsRunning)",
            "interrupted=\(sessionIsInterrupted)",
            "connection=\(hasVideoConnection)",
            "enabled=\(videoConnectionIsEnabled)",
            "active=\(videoConnectionIsActive)",
            "output_recording=\(outputIsRecording)"
        ].joined(separator: " ")
    }

    var failure: WorkoutCameraRecordingReadinessFailure? {
        if !sessionIsRunning {
            return .sessionNotRunning
        }
        if sessionIsInterrupted {
            return .sessionInterrupted
        }
        if !hasVideoConnection {
            return .videoConnectionMissing
        }
        if !videoConnectionIsEnabled {
            return .videoConnectionDisabled
        }
        if !videoConnectionIsActive {
            return .videoConnectionInactive
        }
        if outputIsRecording {
            return .outputAlreadyRecording
        }
        return nil
    }
}

enum WorkoutRecordingStopReason: Equatable, Sendable {
    case expected
    case unexpected(message: String)
    case cancelled

    var partialRecordingMessage: String? {
        guard case let .unexpected(message) = self else { return nil }
        return message
    }
}

@MainActor
final class WorkoutRecordingStopWaiters {
    typealias RegistrationHandler = (_ isFirstWaiter: Bool) -> Void

    private var continuations:
        [UUID: [CheckedContinuation<String?, Error>]] = [:]

    func wait(
        for attemptID: UUID,
        onRegistered: RegistrationHandler
    ) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            let isFirstWaiter = continuations[attemptID, default: []].isEmpty
            continuations[attemptID, default: []].append(continuation)
            onRegistered(isFirstWaiter)
        }
    }

    func resolve(
        attemptID: UUID,
        with result: Result<String?, Error>
    ) {
        let waiters = continuations.removeValue(forKey: attemptID) ?? []
        waiters.forEach { $0.resume(with: result) }
    }

    func waiterCount(for attemptID: UUID) -> Int {
        continuations[attemptID]?.count ?? 0
    }
}

protocol WorkoutRecordingMediaVerifying: Sendable {
    func hasReadableVideoTrack(at url: URL) async -> Bool
}

struct AVAssetWorkoutRecordingMediaVerifier: WorkoutRecordingMediaVerifying {
    func hasReadableVideoTrack(at url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            async let isReadable = asset.load(.isReadable)
            async let videoTracks = asset.loadTracks(withMediaType: .video)
            let resolvedIsReadable = try await isReadable
            let resolvedVideoTracks = try await videoTracks
            return resolvedIsReadable && !resolvedVideoTracks.isEmpty
        } catch {
            return false
        }
    }
}

enum WorkoutRecordingFinishTimeoutDisposition: Equatable {
    case savePartial
    case fail
}

struct WorkoutRecordingFinishTimeoutResolver: Sendable {
    private let verifier: any WorkoutRecordingMediaVerifying
    private let validationDeadline: Duration

    init(
        verifier: any WorkoutRecordingMediaVerifying =
            AVAssetWorkoutRecordingMediaVerifier(),
        validationDeadline: Duration = .seconds(1)
    ) {
        self.verifier = verifier
        self.validationDeadline = validationDeadline
    }

    func resolve(at url: URL) async -> WorkoutRecordingFinishTimeoutDisposition {
        let gate = WorkoutRecordingMediaValidationGate()
        _ = Task {
            await gate.resolve(
                verifier.hasReadableVideoTrack(at: url)
            )
        }
        _ = Task {
            try? await Task.sleep(for: validationDeadline)
            guard !Task.isCancelled else { return }
            await gate.resolve(false)
        }
        return await gate.value()
            ? .savePartial
            : .fail
    }
}

private actor WorkoutRecordingMediaValidationGate {
    private var resolution: Bool?
    private var continuations: [CheckedContinuation<Bool, Never>] = []

    func resolve(_ value: Bool) {
        guard resolution == nil else { return }
        resolution = value
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: value) }
    }

    func value() async -> Bool {
        if let resolution {
            return resolution
        }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

extension WorkoutCameraService {
    static func stateAfterExplicitTeardown(
        _: WorkoutCameraState
    ) -> WorkoutCameraState {
        .idle
    }
}
