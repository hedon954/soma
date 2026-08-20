@preconcurrency import AVFoundation
import Observation
import UIKit

private enum WorkoutRecordingTerminalResult {
    case saved(String)
    case savedPartial(String, message: String)
    case failed(Error)
    case cancelled

    func value() throws -> String? {
        switch self {
        case let .saved(path):
            path
        case let .savedPartial(path, _):
            path
        case let .failed(error):
            throw error
        case .cancelled:
            nil
        }
    }
}

private final class WorkoutCameraCaptureResources: @unchecked Sendable {
    let session = AVCaptureSession()
    let movieOutput = AVCaptureMovieFileOutput()
    let queue: DispatchQueue
    var captureDevice: AVCaptureDevice?
    var isConfigured = false

    init() {
        queue = DispatchQueue(
            label: "top.hedon.soma.workout-camera.\(UUID().uuidString)"
        )
    }
}

@MainActor
@Observable
final class WorkoutCameraService: NSObject, WorkoutRecordingControlling {
    @ObservationIgnored var recordingEventHandler:
        ((WorkoutRecordingAttemptEvent) -> Void)?
    private(set) var state: WorkoutCameraState = .idle
    private(set) var lastSavedPath: String?
    private(set) var captureGeometry = WorkoutCaptureGeometry.portrait
    private(set) var isCaptureGeometryLocked = false
    private(set) var isPreviewReady = false
    private(set) var previewIssueMessage: String?
    @ObservationIgnored let sharedPreviewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    @ObservationIgnored private var captureResources =
        WorkoutCameraCaptureResources()
    @ObservationIgnored private var rotationCoordinator:
        AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var previewRotationObservation:
        NSKeyValueObservation?
    @ObservationIgnored private var captureRotationObservation:
        NSKeyValueObservation?
    @ObservationIgnored private var previewReadinessObservation:
        NSKeyValueObservation?
    @ObservationIgnored private let recordingDelegate = MovieRecordingDelegate()
    @ObservationIgnored private var temporaryURL: URL?
    @ObservationIgnored private let stopWaiters =
        WorkoutRecordingStopWaiters()
    @ObservationIgnored private let finishTimeoutResolver:
        WorkoutRecordingFinishTimeoutResolver
    @ObservationIgnored private var startContinuation:
        CheckedContinuation<Void, Error>?
    @ObservationIgnored private var discardCurrentRecording = false
    @ObservationIgnored private var activeRecordingAttempt:
        WorkoutRecordingAttempt?
    @ObservationIgnored private var terminalRecordingResults:
        [UUID: WorkoutRecordingTerminalResult] = [:]
    @ObservationIgnored private var terminalRecordingOrder: [UUID] = []
    @ObservationIgnored private var recordingAttemptsByURL:
        [URL: WorkoutRecordingAttempt] = [:]
    @ObservationIgnored private var recordingResourcesByURL:
        [URL: WorkoutCameraCaptureResources] = [:]
    @ObservationIgnored private var recordingAttemptLifecycles:
        [UUID: WorkoutRecordingAttemptLifecycle] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var preparationTask: Task<Void, Error>?
    @ObservationIgnored private var preparationTaskID: UUID?
    @ObservationIgnored private var activationGenerationGate =
        WorkoutCameraActivationGenerationGate()
    @ObservationIgnored private var machineActivationContinuation:
        CheckedContinuation<WorkoutCameraRecordingReadiness, Error>?
    @ObservationIgnored private var machineActivationGeneration: UUID?
    @ObservationIgnored private var machineActivationTimeoutTask:
        Task<Void, Never>?
    @ObservationIgnored private var pendingRecordingAttemptID: UUID?
    @ObservationIgnored private var previewStartupTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var recordingStartupTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var recordingFinishTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var activePreviewHostID: UUID?
    @ObservationIgnored private var shouldRecoverCapture = false
    @ObservationIgnored private var requiresCaptureResourceRebuild = false
    @ObservationIgnored private var ownedCaptureSessionIDs: Set<ObjectIdentifier> = []
    @ObservationIgnored private var sessionOwnership =
        WorkoutCameraSessionOwnership()

    private var captureSession: AVCaptureSession {
        captureResources.session
    }

    private var captureDevice: AVCaptureDevice? {
        captureResources.captureDevice
    }

    override convenience init() {
        self.init(
            finishTimeoutResolver: WorkoutRecordingFinishTimeoutResolver()
        )
    }

    init(finishTimeoutResolver: WorkoutRecordingFinishTimeoutResolver) {
        self.finishTimeoutResolver = finishTimeoutResolver
        super.init()
        ownedCaptureSessionIDs.insert(ObjectIdentifier(captureSession))
        let didStart: (URL) -> Void = { [weak self] url in
            Task { @MainActor in
                self?.recordingDidStart(at: url)
            }
        }
        let didFinish: (URL, Error?) -> Void = { [weak self] url, error in
            Task { @MainActor in
                await self?.finishRecording(at: url, error: error)
            }
        }
        recordingDelegate.started = didStart
        recordingDelegate.completion = didFinish
        installObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func claimWorkoutSession(
        sessionID: UUID
    ) -> WorkoutCameraSessionOwnerToken {
        let owner = sessionOwnership.claim(sessionID: sessionID)
        supersedeCaptureIntentForNewWorkoutSession()
        WorkoutRecordingDiagnostics.breadcrumb(
            stage: "session-owner-claimed",
            detail: "generation=created"
        )
        return owner
    }

    func endWorkoutSession(
        owner: WorkoutCameraSessionOwnerToken
    ) async {
        guard sessionOwnership.accepts(owner) else {
            WorkoutRecordingDiagnostics.breadcrumb(
                stage: "session-owner-end-ignored",
                detail: "generation=stale"
            )
            return
        }
        await cancelRecording(attemptID: nil)
        guard sessionOwnership.accepts(owner) else {
            WorkoutRecordingDiagnostics.breadcrumb(
                stage: "session-owner-end-ignored",
                detail: "generation=superseded-during-teardown"
            )
            return
        }
        commitWorkoutSessionEnd(owner: owner)
    }

    func prepare() async throws {
        if Self.shouldRebuildCaptureResources(
            requiresRebuild: requiresCaptureResourceRebuild,
            hasActiveAttempt: activeRecordingAttempt != nil
        ) {
            replaceCaptureResourcesIfCurrent(captureResources)
        }
        if state == .previewing || state == .recording {
            return
        }
        if let preparationTask {
            try await preparationTask.value
            return
        }
        let requestID = UUID()
        let generation = activationGenerationGate.begin()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try await performPreparation(generation: generation)
        }
        preparationTaskID = requestID
        preparationTask = task
        do {
            try await task.value
            if preparationTaskID == requestID {
                preparationTask = nil
                preparationTaskID = nil
            }
        } catch {
            if preparationTaskID == requestID {
                preparationTask = nil
                preparationTaskID = nil
            }
            throw error
        }
    }

    private func performPreparation(generation: UUID) async throws {
        state = .requestingPermission
        WorkoutRecordingDiagnostics.breadcrumb(
            stage: "permission-request",
            attemptID: pendingRecordingAttemptID
        )
        guard await cameraPermissionGranted() else {
            let error = WorkoutCameraError.permissionDenied
            _ = activationGenerationGate.expire(generation)
            WorkoutRecordingDiagnostics.failure(
                stage: "permission",
                attemptID: pendingRecordingAttemptID,
                error: error
            )
            state = .unavailable(error.localizedDescription)
            throw error
        }
        guard activationGenerationGate.isCurrent(generation) else {
            throw WorkoutCameraError.activationSuperseded
        }
        WorkoutRecordingDiagnostics.breadcrumb(
            stage: "permission-granted",
            attemptID: pendingRecordingAttemptID
        )
        do {
            let resources = captureResources
            let readiness = try await activateCaptureResources(
                resources,
                generation: generation
            )
            guard readiness.failure == nil else {
                throw WorkoutCameraError.recordingConnectionUnavailable(
                    readiness.failure?.userFacingReason ?? "状态未知"
                )
            }
            guard resources === captureResources else {
                throw WorkoutCameraError.activationSuperseded
            }
            sharedPreviewLayer.session = captureSession
            configureRotationCoordinatorIfPossible()
            state = .previewing
            shouldRecoverCapture = false
            WorkoutRecordingDiagnostics.breadcrumb(
                stage: "preview-ready",
                attemptID: pendingRecordingAttemptID,
                detail: readiness.diagnosticDetail
            )
            refreshPreviewConnectionState()
            armPreviewStartupTimeout()
        } catch {
            WorkoutRecordingDiagnostics.failure(
                stage: "prepare",
                attemptID: pendingRecordingAttemptID,
                error: error
            )
            if let cameraError = error as? WorkoutCameraError,
               case .activationSuperseded = cameraError
            {
                // A timed-out generation must not overwrite the newer retry.
            } else {
                state = .unavailable(error.localizedDescription)
            }
            throw error
        }
    }

    func startRecording(attempt: WorkoutRecordingAttempt) async throws {
        if activeRecordingAttempt?.id == attempt.id,
           state == .recording
        {
            return
        }
        if let activeRecordingAttempt,
           activeRecordingAttempt.id != attempt.id
        {
            await cancelRecording(attemptID: activeRecordingAttempt.id)
        }
        if let terminal = terminalRecordingResults[attempt.id] {
            _ = try terminal.value()
            return
        }
        activeRecordingAttempt = attempt
        recordingAttemptLifecycles[attempt.id] = WorkoutRecordingAttemptLifecycle()
        discardCurrentRecording = false
        pendingRecordingAttemptID = attempt.id
        WorkoutRecordingDiagnostics.breadcrumb(
            stage: "attempt-request",
            attemptID: attempt.id
        )
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startContinuation = continuation
                Task { @MainActor [weak self] in
                    await self?.continueRecordingStart(attempt: attempt)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                await self?.cancelRecording(attemptID: attempt.id)
            }
        }
    }

    private func continueRecordingStart(
        attempt: WorkoutRecordingAttempt
    ) async {
        do {
            if state != .previewing {
                try await prepare()
            }
            guard activeRecordingAttempt?.id == attempt.id,
                  terminalRecordingResults[attempt.id] == nil
            else { return }
            guard hasRecordingCapacity else {
                throw WorkoutCameraError.insufficientStorage
            }
            let resources = captureResources
            let recordingTargetID = attempt.effortID ?? attempt.setID
            let url = FileManager.default.temporaryDirectory
                .appending(path: "soma-set-\(attempt.performanceID.uuidString)-\(recordingTargetID.uuidString)-\(UUID().uuidString)")
                .appendingPathExtension("mov")
            recordingAttemptsByURL[url] = attempt
            recordingResourcesByURL[url] = resources
            temporaryURL = url
            lockCaptureGeometry()
            state = .startingRecording
            armRecordingStartupTimeout()
            WorkoutRecordingDiagnostics.breadcrumb(
                stage: "movie-command",
                attemptID: attempt.id
            )
            resources.queue.async { [recordingDelegate] in
                let connection = resources.movieOutput.connection(with: .video)
                let readiness = WorkoutCameraRecordingReadiness(
                    sessionIsRunning: resources.session.isRunning,
                    sessionIsInterrupted: resources.session.isInterrupted,
                    hasVideoConnection: connection != nil,
                    videoConnectionIsEnabled: connection?.isEnabled ?? false,
                    videoConnectionIsActive: connection?.isActive ?? false,
                    outputIsRecording: resources.movieOutput.isRecording
                )
                guard let failure = readiness.failure else {
                    WorkoutRecordingDiagnostics.breadcrumb(
                        stage: "recording-connection-ready",
                        attemptID: attempt.id,
                        detail: readiness.diagnosticDetail
                    )
                    resources.movieOutput.startRecording(
                        to: url,
                        recordingDelegate: recordingDelegate
                    )
                    return
                }
                Task { @MainActor [weak self] in
                    self?.recordingConnectionUnavailable(
                        attempt: attempt,
                        url: url,
                        failure: failure
                    )
                }
            }
        } catch {
            guard activeRecordingAttempt?.id == attempt.id,
                  terminalRecordingResults[attempt.id] == nil
            else { return }
            WorkoutRecordingDiagnostics.failure(
                stage: "activation",
                attemptID: attempt.id,
                error: error
            )
            state = .unavailable(error.localizedDescription)
            completeRecordingAttempt(attempt, with: .failed(error))
        }
    }

    private func recordingConnectionUnavailable(
        attempt: WorkoutRecordingAttempt,
        url: URL,
        failure: WorkoutCameraRecordingReadinessFailure
    ) {
        recordingAttemptsByURL.removeValue(forKey: url)
        let resources = recordingResourcesByURL.removeValue(forKey: url)
        try? FileManager.default.removeItem(at: url)
        if temporaryURL == url {
            temporaryURL = nil
            unlockCaptureGeometry()
        }
        guard activeRecordingAttempt?.id == attempt.id,
              terminalRecordingResults[attempt.id] == nil
        else {
            if let resources {
                stopStaleCaptureResources(resources)
            }
            return
        }
        let error = WorkoutCameraError.recordingConnectionUnavailable(
            failure.userFacingReason
        )
        WorkoutRecordingDiagnostics.failure(
            stage: "recording-connection",
            attemptID: attempt.id,
            error: error
        )
        if let resources {
            replaceCaptureResourcesIfCurrent(resources)
        }
        state = .unavailable(error.localizedDescription)
        completeRecordingAttempt(attempt, with: .failed(error))
    }

    func stopRecording(attemptID: UUID) async throws -> String? {
        if let terminal = terminalRecordingResults[attemptID] {
            return try terminal.value()
        }
        guard activeRecordingAttempt?.id == attemptID else {
            return nil
        }
        let resources = activeCaptureResources(for: attemptID)
        if let terminal = terminalRecordingResults[attemptID] {
            return try terminal.value()
        }
        do {
            let path = try await stopWaiters.wait(
                for: attemptID
            ) { [weak self] isFirstWaiter in
                guard let self, isFirstWaiter else { return }
                let wasAlreadyFinishing = recordingAttemptLifecycles[
                    attemptID
                ]?.isFinishing == true
                if !wasAlreadyFinishing {
                    recordingAttemptLifecycles[attemptID]?.requestStop(
                        reason: .expected
                    )
                    armRecordingFinishTimeout(for: attemptID)
                    if let resources {
                        WorkoutRecordingDiagnostics.breadcrumb(
                            stage: "stop-request",
                            attemptID: attemptID,
                            detail: "expected"
                        )
                        resources.queue.async {
                            if resources.movieOutput.isRecording {
                                resources.movieOutput.stopRecording()
                            }
                        }
                    }
                }
            }
            if let resources {
                await stopCaptureSession(resources: resources)
            }
            return path
        } catch {
            if let resources {
                await stopCaptureSession(resources: resources)
            }
            throw error
        }
    }

    func cancelRecording(attemptID: UUID?) async {
        if let attemptID,
           let terminal = terminalRecordingResults[attemptID]
        {
            _ = try? terminal.value()
            return
        }
        guard attemptID == nil || activeRecordingAttempt?.id == attemptID else {
            return
        }
        let attempt = activeRecordingAttempt
        let resources = attempt.flatMap { activeCaptureResources(for: $0.id) }
        let sessionResources = resources ?? captureResources
        let shouldInvalidatePreparation = temporaryURL == nil
            && (attempt != nil || preparationTask != nil)
        discardCurrentRecording = true
        recordingStartupTimeoutTask?.cancel()
        recordingStartupTimeoutTask = nil
        if shouldInvalidatePreparation {
            invalidatePreparation(replacing: captureResources)
        }
        if let attempt {
            recordingAttemptLifecycles[attempt.id]?.requestStop(
                reason: .cancelled
            )
            completeRecordingAttempt(attempt, with: .cancelled)
        }
        if shouldInvalidatePreparation {
            shouldRecoverCapture = false
            state = .idle
            return
        }
        if let resources {
            resources.queue.async {
                if resources.movieOutput.isRecording {
                    resources.movieOutput.stopRecording()
                }
            }
        } else {
            unlockCaptureGeometry()
            removeTemporaryRecordingIfPresent()
        }
        await stopCaptureSession(resources: sessionResources)
    }

    func attachPreviewLayer(
        _ layer: AVCaptureVideoPreviewLayer,
        hostID: UUID,
        videoGravity: AVLayerVideoGravity
    ) {
        guard layer === sharedPreviewLayer else { return }
        guard activePreviewHostID != hostID else {
            layer.videoGravity = videoGravity
            applyCaptureGeometry(captureGeometry)
            refreshPreviewConnectionState()
            return
        }

        activePreviewHostID = hostID
        previewRotationObservation = nil
        captureRotationObservation = nil
        rotationCoordinator = nil
        previewReadinessObservation = nil
        previewStartupTimeoutTask?.cancel()
        isPreviewReady = false
        previewIssueMessage = nil

        // Rebuild only the lightweight preview connection after a host handoff.
        // The capture session and movie output continue running unchanged.
        // BUG 0025：录像开始会把界面切到放大取景，SwiftUI 因此换 preview host。此时重绑
        // 同一个 session 只会打断预览连接，所以 session 未变时不动它。
        if layer.session !== captureSession {
            layer.session = nil
            layer.session = captureSession
        }
        layer.videoGravity = videoGravity
        configureRotationCoordinatorIfPossible()
        applyCaptureGeometry(captureGeometry)
        observePreviewReadiness(on: layer, hostID: hostID)
        refreshPreviewConnectionState()
        armPreviewStartupTimeout()
    }

    func detachPreviewLayer(
        _ layer: AVCaptureVideoPreviewLayer,
        hostID: UUID
    ) {
        guard layer === sharedPreviewLayer,
              activePreviewHostID == hostID
        else {
            return
        }
        previewRotationObservation = nil
        captureRotationObservation = nil
        rotationCoordinator = nil
        previewReadinessObservation = nil
        previewStartupTimeoutTask?.cancel()
        previewStartupTimeoutTask = nil
        activePreviewHostID = nil
        isPreviewReady = false
        previewIssueMessage = nil
    }

    func stopPreview() async {
        guard sessionOwnership.activeOwner == nil else {
            WorkoutRecordingDiagnostics.breadcrumb(
                stage: "legacy-preview-stop-ignored",
                detail: "guided_owner=active"
            )
            return
        }
        await cancelRecording(attemptID: nil)
        resetExplicitPreviewState()
    }

    #if DEBUG
        var activePreviewHostIDForTesting: UUID? {
            activePreviewHostID
        }

        var activeWorkoutSessionOwnerForTesting:
            WorkoutCameraSessionOwnerToken?
        {
            sessionOwnership.activeOwner
        }

        var captureResourceIdentityForTesting: ObjectIdentifier {
            ObjectIdentifier(captureResources)
        }

        func useCaptureGeometryForTesting(_ geometry: WorkoutCaptureGeometry) {
            captureGeometry = geometry
            applyCaptureGeometry(geometry)
        }

        func useCameraStateForTesting(_ cameraState: WorkoutCameraState) {
            state = cameraState
        }

        func finishWorkoutSessionTeardownForTesting(
            owner: WorkoutCameraSessionOwnerToken,
            afterSuspension: @escaping @MainActor () async -> Void
        ) async {
            guard sessionOwnership.accepts(owner) else { return }
            await afterSuspension()
            guard sessionOwnership.accepts(owner) else { return }
            commitWorkoutSessionEnd(owner: owner)
        }
    #endif

    private func finishRecording(at url: URL, error: Error?) async {
        let resources = recordingResourcesByURL.removeValue(forKey: url)
        guard let attempt = recordingAttemptsByURL.removeValue(
            forKey: url
        ) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard terminalRecordingResults[attempt.id] == nil,
              activeRecordingAttempt?.id == attempt.id
        else {
            try? FileManager.default.removeItem(at: url)
            if temporaryURL == url {
                temporaryURL = nil
                discardCurrentRecording = false
                unlockCaptureGeometry()
                if activeRecordingAttempt == nil {
                    if case .unavailable = state {
                        // Keep the failure visible after physical cleanup.
                    } else {
                        state = .idle
                    }
                    if let resources {
                        await stopCaptureSession(resources: resources)
                    }
                }
            }
            return
        }
        recordingStartupTimeoutTask?.cancel()
        recordingStartupTimeoutTask = nil
        recordingFinishTimeoutTask?.cancel()
        recordingFinishTimeoutTask = nil
        let didFinishSuccessfully = Self.recordingFinishedSuccessfully(
            error: error,
            hasUsableFile: Self.hasUsableRecordingFile(at: url)
        )
        if recordingAttemptLifecycles[attempt.id]?.isFinishing == false,
           !discardCurrentRecording
        {
            // BUG 0025：这条分支是"没人请求停止但录像自己结束了"。原来只给一句固定文案，
            // AVFoundation 的错误被丢弃，导致用户看不到原因、日志里也查不到。
            let diagnosis = WorkoutRecordingFailureDiagnosis.make(
                error: error,
                stage: "finish-unexpected"
            )
            WorkoutRecordingDiagnostics.unexpectedFinish(
                attemptID: attempt.id,
                diagnosis: diagnosis,
                error: error
            )
            recordingAttemptLifecycles[attempt.id]?.requestStop(
                reason: .unexpected(message: diagnosis.partialRecordingMessage)
            )
        }
        let disposition = recordingAttemptLifecycles[attempt.id]?
            .delegateDisposition(
                finishedSuccessfully: didFinishSuccessfully
            ) ?? (discardCurrentRecording
                ? .cancel
                : (didFinishSuccessfully ? .persist : .fail))
        switch disposition {
        case .cancel:
            try? FileManager.default.removeItem(at: url)
            completeRecordingAttempt(attempt, with: .cancelled)
        case .persist:
            do {
                let path = try MediaStore.saveVideo(from: url)
                try? FileManager.default.removeItem(at: url)
                lastSavedPath = path
                completeRecordingAttempt(
                    attempt,
                    with: .saved(path)
                )
            } catch {
                WorkoutRecordingDiagnostics.failure(
                    stage: "persist",
                    attemptID: attempt.id,
                    error: error
                )
                try? FileManager.default.removeItem(at: url)
                state = .unavailable(error.localizedDescription)
                completeRecordingAttempt(
                    attempt,
                    with: .failed(error)
                )
            }
        case let .persistPartial(message):
            do {
                let path = try MediaStore.saveVideo(from: url)
                try? FileManager.default.removeItem(at: url)
                lastSavedPath = path
                completeRecordingAttempt(
                    attempt,
                    with: .savedPartial(path, message: message)
                )
            } catch {
                WorkoutRecordingDiagnostics.failure(
                    stage: "persist-partial",
                    attemptID: attempt.id,
                    error: error
                )
                try? FileManager.default.removeItem(at: url)
                state = .unavailable(error.localizedDescription)
                completeRecordingAttempt(
                    attempt,
                    with: .failed(error)
                )
            }
        case .fail:
            // BUG 0025：失败路径必须给出可行动的具体原因，而不是 AVFoundation 的
            // "The operation could not be completed"。
            let diagnosis = WorkoutRecordingFailureDiagnosis.make(
                error: error,
                stage: "finish-failed"
            )
            let sourceError = error ?? WorkoutCameraError.recordingFailed(
                diagnosis.failureMessage
            )
            WorkoutRecordingDiagnostics.failure(
                stage: "finish · \(diagnosis.technical)",
                attemptID: attempt.id,
                error: sourceError
            )
            try? FileManager.default.removeItem(at: url)
            let resolved: Error = if sourceError is WorkoutCameraError {
                sourceError
            } else {
                WorkoutCameraError.recordingFailed(diagnosis.failureMessage)
            }
            state = .unavailable(resolved.localizedDescription)
            completeRecordingAttempt(
                attempt,
                with: .failed(resolved)
            )
        }
        if temporaryURL == url {
            temporaryURL = nil
            discardCurrentRecording = false
            unlockCaptureGeometry()
        }
        if case .unavailable = state {
            // Preserve the actionable failure while the capture session stops.
        } else {
            state = .idle
        }
        if let resources {
            await stopCaptureSession(resources: resources)
        }
        await recoverCaptureIfNeeded()
    }

    private func recordingDidStart(at url: URL) {
        guard let attempt = recordingAttemptsByURL[url] else {
            return
        }
        guard activeRecordingAttempt?.id == attempt.id,
              terminalRecordingResults[attempt.id] == nil,
              !discardCurrentRecording
        else {
            if let resources = recordingResourcesByURL[url] {
                resources.queue.async {
                    if resources.movieOutput.isRecording {
                        resources.movieOutput.stopRecording()
                    }
                }
            }
            return
        }
        if recordingAttemptLifecycles[attempt.id]?.isFinishing == true {
            if let resources = recordingResourcesByURL[url] {
                resources.queue.async {
                    if resources.movieOutput.isRecording {
                        resources.movieOutput.stopRecording()
                    }
                }
            }
            return
        }
        recordingAttemptLifecycles[attempt.id]?.markStarted()
        recordingStartupTimeoutTask?.cancel()
        recordingStartupTimeoutTask = nil
        state = .recording
        pendingRecordingAttemptID = nil
        WorkoutRecordingDiagnostics.breadcrumb(
            stage: "did-start",
            attemptID: attempt.id
        )
        refreshPreviewConnectionState()
        armPreviewStartupTimeout()
        recordingEventHandler?(.started(attempt))
        startContinuation?.resume()
        startContinuation = nil
    }

    static func recordingFinishedSuccessfully(
        error: Error?,
        hasUsableFile: Bool
    ) -> Bool {
        guard hasUsableFile else { return false }
        guard let error else { return true }
        let value = (error as NSError).userInfo[
            AVErrorRecordingSuccessfullyFinishedKey
        ]
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return value as? Bool == true
    }

    private static func hasUsableRecordingFile(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ), let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    private func completeRecordingAttempt(
        _ attempt: WorkoutRecordingAttempt,
        with terminal: WorkoutRecordingTerminalResult
    ) {
        guard terminalRecordingResults[attempt.id] == nil else { return }
        terminalRecordingResults[attempt.id] = terminal
        terminalRecordingOrder.append(attempt.id)
        while terminalRecordingOrder.count > 8 {
            let expiredID = terminalRecordingOrder.removeFirst()
            terminalRecordingResults.removeValue(forKey: expiredID)
            recordingAttemptLifecycles.removeValue(forKey: expiredID)
        }
        recordingStartupTimeoutTask?.cancel()
        recordingStartupTimeoutTask = nil
        recordingFinishTimeoutTask?.cancel()
        recordingFinishTimeoutTask = nil
        if activeRecordingAttempt?.id == attempt.id {
            activeRecordingAttempt = nil
        }
        if pendingRecordingAttemptID == attempt.id {
            pendingRecordingAttemptID = nil
        }
        switch terminal {
        case .saved, .savedPartial:
            recordingAttemptLifecycles[attempt.id]?.finish(.saved)
        case .failed:
            recordingAttemptLifecycles[attempt.id]?.finish(.failed)
        case .cancelled:
            recordingAttemptLifecycles[attempt.id]?.finish(.cancelled)
        }
        switch terminal {
        case let .saved(path):
            recordingEventHandler?(.saved(attempt, path: path))
            startContinuation?.resume()
            stopWaiters.resolve(
                attemptID: attempt.id,
                with: .success(path)
            )
        case let .savedPartial(path, message):
            recordingEventHandler?(.savedPartial(
                attempt,
                path: path,
                message: message
            ))
            startContinuation?.resume()
            stopWaiters.resolve(
                attemptID: attempt.id,
                with: .success(path)
            )
        case let .failed(error):
            recordingEventHandler?(.failed(attempt, error))
            startContinuation?.resume(throwing: error)
            stopWaiters.resolve(
                attemptID: attempt.id,
                with: .failure(error)
            )
        case .cancelled:
            recordingEventHandler?(.cancelled(attempt))
            startContinuation?.resume(
                throwing: WorkoutCameraError.recordingFailed("录像已取消")
            )
            stopWaiters.resolve(
                attemptID: attempt.id,
                with: .success(nil)
            )
        }
        startContinuation = nil
    }

    static func settledState(
        after current: WorkoutCameraState,
        sessionIsRunning: Bool
    ) -> WorkoutCameraState {
        if case .unavailable = current {
            return current
        }
        return sessionIsRunning ? .previewing : .idle
    }

    private func cameraPermissionGranted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

extension WorkoutCameraService {
    private func activateCaptureResources(
        _ resources: WorkoutCameraCaptureResources,
        generation: UUID
    ) async throws -> WorkoutCameraRecordingReadiness {
        state = .configuring
        WorkoutRecordingDiagnostics.breadcrumb(
            stage: "configure",
            attemptID: pendingRecordingAttemptID
        )
        return try await withCheckedThrowingContinuation { continuation in
            machineActivationContinuation = continuation
            machineActivationGeneration = generation
            machineActivationTimeoutTask?.cancel()
            machineActivationTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard let self,
                      !Task.isCancelled,
                      activationGenerationGate.expire(generation),
                      machineActivationGeneration == generation
                else { return }
                let error = WorkoutCameraError.activationTimedOut
                WorkoutRecordingDiagnostics.failure(
                    stage: "activation-timeout",
                    attemptID: pendingRecordingAttemptID,
                    error: error
                )
                machineActivationGeneration = nil
                let pending = machineActivationContinuation
                machineActivationContinuation = nil
                replaceCaptureResourcesIfCurrent(resources)
                pending?.resume(throwing: error)
            }
            resources.queue.async { [weak self, weak resources] in
                guard let resources else { return }
                do {
                    if !resources.isConfigured {
                        // BUG 0025：带练录像只采视频。默认值会让 AVCaptureSession 接管
                        // AVAudioSession，于是语音提示每次播报都在重配置同一个音频会话，
                        // 可能把正在进行的录制打断。这里明确交出音频会话所有权。
                        resources.session
                            .automaticallyConfiguresApplicationAudioSession = false
                        resources.session.beginConfiguration()
                        defer { resources.session.commitConfiguration() }
                        if resources.session.canSetSessionPreset(.high) {
                            resources.session.sessionPreset = .high
                        }
                        guard let camera = AVCaptureDevice.default(
                            .builtInWideAngleCamera,
                            for: .video,
                            position: .front
                        ) else {
                            throw WorkoutCameraError.frontCameraUnavailable
                        }
                        let input = try AVCaptureDeviceInput(device: camera)
                        guard resources.session.canAddInput(input),
                              resources.session.canAddOutput(
                                  resources.movieOutput
                              )
                        else {
                            throw WorkoutCameraError.configurationFailed
                        }
                        resources.session.addInput(input)
                        resources.session.addOutput(resources.movieOutput)
                        resources.captureDevice = camera
                        if let connection = resources.movieOutput.connection(
                            with: .video
                        ), connection.isVideoMirroringSupported {
                            connection.automaticallyAdjustsVideoMirroring = false
                            connection.isVideoMirrored = true
                        }
                        resources.isConfigured = true
                    }
                    Task { @MainActor [weak self, weak resources] in
                        guard let self,
                              let resources,
                              resources === captureResources,
                              activationGenerationGate.isCurrent(generation)
                        else { return }
                        state = .startingSession
                        WorkoutRecordingDiagnostics.breadcrumb(
                            stage: "session-start",
                            attemptID: pendingRecordingAttemptID
                        )
                    }
                    if !resources.session.isRunning {
                        resources.session.startRunning()
                    }
                    let connection = resources.movieOutput.connection(
                        with: .video
                    )
                    let readiness = WorkoutCameraRecordingReadiness(
                        sessionIsRunning: resources.session.isRunning,
                        sessionIsInterrupted: resources.session.isInterrupted,
                        hasVideoConnection: connection != nil,
                        videoConnectionIsEnabled: connection?.isEnabled ?? false,
                        videoConnectionIsActive: connection?.isActive ?? false,
                        outputIsRecording: resources.movieOutput.isRecording
                    )
                    if let failure = readiness.failure {
                        throw WorkoutCameraError.recordingConnectionUnavailable(
                            failure.userFacingReason
                        )
                    }
                    guard let self else { return }
                    Task { @MainActor in
                        self.completeMachineActivation(
                            generation: generation,
                            resources: resources,
                            result: .success(readiness)
                        )
                    }
                } catch {
                    guard let self else { return }
                    Task { @MainActor in
                        self.completeMachineActivation(
                            generation: generation,
                            resources: resources,
                            result: .failure(error)
                        )
                    }
                }
            }
        }
    }

    private func completeMachineActivation(
        generation: UUID,
        resources: WorkoutCameraCaptureResources,
        result: Result<WorkoutCameraRecordingReadiness, Error>
    ) {
        guard resources === captureResources,
              machineActivationGeneration == generation,
              activationGenerationGate.accept(generation)
        else {
            stopStaleCaptureResources(resources)
            return
        }
        machineActivationTimeoutTask?.cancel()
        machineActivationTimeoutTask = nil
        machineActivationGeneration = nil
        let pending = machineActivationContinuation
        machineActivationContinuation = nil
        if case .failure = result {
            replaceCaptureResourcesIfCurrent(resources)
        }
        pending?.resume(with: result)
    }

    private func stopStaleCaptureResources(
        _ resources: WorkoutCameraCaptureResources
    ) {
        guard resources !== captureResources else { return }
        resources.queue.async {
            if resources.session.isRunning {
                resources.session.stopRunning()
            }
        }
    }

    private func replaceCaptureResourcesIfCurrent(
        _ resources: WorkoutCameraCaptureResources
    ) {
        guard captureResources === resources else { return }
        sharedPreviewLayer.session = nil
        captureResources = WorkoutCameraCaptureResources()
        ownedCaptureSessionIDs.insert(ObjectIdentifier(captureSession))
        requiresCaptureResourceRebuild = false
        rotationCoordinator = nil
        previewRotationObservation = nil
        captureRotationObservation = nil
        previewReadinessObservation = nil
        isPreviewReady = false
        previewIssueMessage = nil
        stopStaleCaptureResources(resources)
    }

    private func invalidatePreparation(
        replacing resources: WorkoutCameraCaptureResources? = nil
    ) {
        let superseded = activationGenerationGate.supersede()
        preparationTask?.cancel()
        preparationTask = nil
        preparationTaskID = nil
        machineActivationTimeoutTask?.cancel()
        machineActivationTimeoutTask = nil
        if let generation = machineActivationGeneration,
           superseded == generation
        {
            let pending = machineActivationContinuation
            machineActivationContinuation = nil
            machineActivationGeneration = nil
            pending?.resume(throwing: WorkoutCameraError.activationSuperseded)
        }
        if let resources {
            replaceCaptureResourcesIfCurrent(resources)
        }
    }

    private func supersedeCaptureIntentForNewWorkoutSession() {
        let attempt = activeRecordingAttempt
        let url = temporaryURL
        let recordingResources = url.flatMap { recordingResourcesByURL[$0] }
            ?? attempt.flatMap { activeCaptureResources(for: $0.id) }
        if let recordingResources {
            recordingResources.queue.async {
                if recordingResources.movieOutput.isRecording {
                    recordingResources.movieOutput.stopRecording()
                }
            }
        }
        if let attempt {
            recordingAttemptLifecycles[attempt.id]?.requestStop(
                reason: .cancelled
            )
            completeRecordingAttempt(attempt, with: .cancelled)
        }
        if let url {
            recordingAttemptsByURL.removeValue(forKey: url)
            recordingResourcesByURL.removeValue(forKey: url)
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURL = nil
        discardCurrentRecording = false
        isCaptureGeometryLocked = false
        invalidatePreparation(replacing: captureResources)
        shouldRecoverCapture = false
        resetExplicitPreviewState()
    }

    private func commitWorkoutSessionEnd(
        owner: WorkoutCameraSessionOwnerToken
    ) {
        guard sessionOwnership.release(owner) else { return }
        shouldRecoverCapture = false
        resetExplicitPreviewState()
        WorkoutRecordingDiagnostics.breadcrumb(
            stage: "session-owner-ended",
            detail: "generation=released"
        )
    }

    private func resetExplicitPreviewState() {
        previewStartupTimeoutTask?.cancel()
        previewStartupTimeoutTask = nil
        previewReadinessObservation = nil
        previewRotationObservation = nil
        captureRotationObservation = nil
        rotationCoordinator = nil
        activePreviewHostID = nil
        isPreviewReady = false
        previewIssueMessage = nil
        sharedPreviewLayer.session = nil
        state = Self.stateAfterExplicitTeardown(state)
    }

    private func activeCaptureResources(
        for attemptID: UUID
    ) -> WorkoutCameraCaptureResources? {
        guard activeRecordingAttempt?.id == attemptID else { return nil }
        if let temporaryURL {
            return recordingResourcesByURL[temporaryURL]
        }
        return captureResources
    }

    private func stopCaptureSession() async {
        await stopCaptureSession(resources: captureResources)
    }

    private func stopCaptureSession(
        resources: WorkoutCameraCaptureResources
    ) async {
        let wasCurrent = resources === captureResources
        if wasCurrent {
            replaceCaptureResourcesIfCurrent(resources)
        } else {
            stopStaleCaptureResources(resources)
        }
        guard wasCurrent else { return }
        if case .unavailable = state {
            return
        }
        previewStartupTimeoutTask?.cancel()
        isPreviewReady = false
        previewIssueMessage = nil
        state = .idle
    }

    private var hasRecordingCapacity: Bool {
        let values = try? FileManager.default
            .temporaryDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Self.hasSufficientRecordingCapacity(
            values?.volumeAvailableCapacityForImportantUsage
        )
    }

    static func hasSufficientRecordingCapacity(_ capacity: Int64?) -> Bool {
        guard let capacity else { return true }
        return capacity > 100 * 1024 * 1024
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.interrupt(
                    diagnosis: WorkoutRecordingFailureDiagnosis(
                        cause: "App 进入后台，系统禁止继续使用摄像头",
                        technical: "lifecycle=background · interrupt"
                    ),
                    reasonCode: "background"
                )
            }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.recoverCaptureIfNeeded()
            }
        })
        observers.append(center.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let reasonCode = (notification.userInfo?[
                AVCaptureSessionInterruptionReasonKey
            ] as? NSNumber)?.intValue
            Task { @MainActor in
                guard let self,
                      (notification.object as? AVCaptureSession) === self.captureSession
                else { return }
                await self.interrupt(
                    diagnosis: WorkoutRecordingFailureDiagnosis.interruption(
                        reasonCode: reasonCode,
                        stage: "session-interruption"
                    ),
                    reasonCode: "session-interruption"
                )
            }
        })
        observers.append(center.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      let session = notification.object as? AVCaptureSession,
                      Self.shouldRecoverAfterInterruptionEnded(
                          isOwnedSession: self.ownedCaptureSessionIDs.contains(
                              ObjectIdentifier(session)
                          ),
                          shouldRecover: self.shouldRecoverCapture
                      )
                else { return }
                WorkoutRecordingDiagnostics.breadcrumb(
                    stage: "interruption-ended",
                    attemptID: self.activeRecordingAttempt?.id
                )
                await self.recoverCaptureIfNeeded()
            }
        })
        observers.append(center.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let runtimeError = notification.userInfo?[
                AVCaptureSessionErrorKey
            ] as? Error
            Task { @MainActor in
                guard let self,
                      (notification.object as? AVCaptureSession) === self.captureSession
                else { return }
                if let runtimeError {
                    WorkoutRecordingDiagnostics.failure(
                        stage: "runtime",
                        attemptID: self.activeRecordingAttempt?.id,
                        error: runtimeError
                    )
                    let nsError = runtimeError as NSError
                    if nsError.domain == AVFoundationErrorDomain,
                       nsError.code == AVError.mediaServicesWereReset.rawValue
                    {
                        self.requiresCaptureResourceRebuild = true
                    }
                }
                await self.interrupt(
                    diagnosis: WorkoutRecordingFailureDiagnosis.make(
                        error: runtimeError,
                        stage: "session-runtime-error"
                    ),
                    reasonCode: "runtime"
                )
            }
        })
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                let thermalState = ProcessInfo.processInfo.thermalState
                if thermalState == .serious || thermalState == .critical {
                    await self?.interrupt(
                        diagnosis: WorkoutRecordingFailureDiagnosis(
                            cause: thermalState == .critical
                                ? "设备温度已达临界，系统要求停止录像"
                                : "设备温度偏高，系统要求停止录像",
                            technical: "thermal_state=\(thermalState.rawValue) · interrupt"
                        ),
                        reasonCode: "thermal"
                    )
                } else {
                    await self?.recoverCaptureIfNeeded()
                }
            }
        })
    }

    private func configureRotationCoordinatorIfPossible() {
        guard let captureDevice else {
            return
        }
        previewRotationObservation = nil
        captureRotationObservation = nil
        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: captureDevice,
            previewLayer: sharedPreviewLayer
        )
        rotationCoordinator = coordinator
        previewRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshCaptureGeometry()
            }
        }
        captureRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshCaptureGeometry()
            }
        }
        refreshCaptureGeometry()
    }

    private func refreshPreviewConnectionState() {
        guard activePreviewHostID != nil else {
            isPreviewReady = false
            previewIssueMessage = nil
            return
        }

        isPreviewReady = sharedPreviewLayer.isPreviewing
        if isPreviewReady {
            previewIssueMessage = nil
            previewStartupTimeoutTask?.cancel()
            previewStartupTimeoutTask = nil
        }
    }

    private func observePreviewReadiness(
        on layer: AVCaptureVideoPreviewLayer,
        hostID: UUID
    ) {
        previewReadinessObservation = layer.observe(
            \.isPreviewing,
            options: [.initial, .new]
        ) { [weak self] layer, _ in
            Task { @MainActor [weak self] in
                guard let self, activePreviewHostID == hostID else { return }
                isPreviewReady = layer.isPreviewing
                if isPreviewReady {
                    previewIssueMessage = nil
                    previewStartupTimeoutTask?.cancel()
                    previewStartupTimeoutTask = nil
                }
            }
        }
    }

    private func armPreviewStartupTimeout() {
        guard let hostID = activePreviewHostID,
              isPreviewCapableState,
              !isPreviewReady
        else {
            return
        }
        previewStartupTimeoutTask?.cancel()
        previewStartupTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self,
                  !Task.isCancelled,
                  activePreviewHostID == hostID,
                  !sharedPreviewLayer.isPreviewing,
                  isPreviewCapableState
            else {
                return
            }
            isPreviewReady = false
            let message = "相机画面未能显示；训练可以继续，请收起后重新进入取景。"
            previewIssueMessage = message
            WorkoutRecordingDiagnostics.failure(
                stage: "preview-timeout",
                attemptID: activeRecordingAttempt?.id,
                error: WorkoutCameraError.recordingFailed(message)
            )
        }
    }

    private func armRecordingStartupTimeout() {
        recordingStartupTimeoutTask?.cancel()
        recordingStartupTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self,
                  !Task.isCancelled,
                  startContinuation != nil,
                  let attempt = activeRecordingAttempt
            else {
                return
            }
            let error = WorkoutCameraError.recordingFailed(
                "系统未在限定时间内确认录像启动，请重试。训练仍可继续。"
            )
            WorkoutRecordingDiagnostics.failure(
                stage: "start-timeout",
                attemptID: attempt.id,
                error: error
            )
            state = .unavailable(error.localizedDescription)
            recordingAttemptLifecycles[attempt.id]?.requestStop(
                reason: .unexpected(
                    message: "系统没有确认录像启动；已保留可能生成的部分视频，训练数据不受影响。"
                )
            )
            armRecordingFinishTimeout(for: attempt.id)
            if let resources = activeCaptureResources(for: attempt.id) {
                resources.queue.async {
                    if resources.movieOutput.isRecording {
                        resources.movieOutput.stopRecording()
                    }
                }
            }
        }
    }

    private func armRecordingFinishTimeout(for attemptID: UUID) {
        recordingFinishTimeoutTask?.cancel()
        recordingFinishTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self,
                  !Task.isCancelled,
                  let attempt = activeRecordingAttempt,
                  attempt.id == attemptID,
                  terminalRecordingResults[attemptID] == nil,
                  let url = temporaryURL
            else {
                return
            }
            let error = WorkoutCameraError.recordingFailed(
                "系统未返回录像结束结果；训练数据已保留。"
            )
            WorkoutRecordingDiagnostics.breadcrumb(
                stage: "finish-timeout",
                attemptID: attempt.id
            )
            let disposition = await finishTimeoutResolver.resolve(at: url)
            guard !Task.isCancelled,
                  activeRecordingAttempt?.id == attemptID,
                  terminalRecordingResults[attemptID] == nil,
                  temporaryURL == url
            else { return }
            let resources = recordingResourcesByURL.removeValue(forKey: url)
                ?? activeCaptureResources(for: attempt.id)
            recordingAttemptsByURL.removeValue(forKey: url)
            temporaryURL = nil
            discardCurrentRecording = false
            unlockCaptureGeometry()

            switch disposition {
            case .savePartial:
                do {
                    let path = try MediaStore.saveVideo(from: url)
                    try? FileManager.default.removeItem(at: url)
                    lastSavedPath = path
                    let message = recordingAttemptLifecycles[attempt.id]?
                        .stopReason?.partialRecordingMessage
                        ?? "系统未返回录像结束确认；已保留可读取的部分视频，训练数据不受影响。"
                    WorkoutRecordingDiagnostics.breadcrumb(
                        stage: "finish-timeout-salvaged",
                        attemptID: attempt.id,
                        detail: "readable_video_track=true"
                    )
                    state = .unavailable(message)
                    completeRecordingAttempt(
                        attempt,
                        with: .savedPartial(path, message: message)
                    )
                } catch {
                    WorkoutRecordingDiagnostics.failure(
                        stage: "finish-timeout-persist",
                        attemptID: attempt.id,
                        error: error
                    )
                    try? FileManager.default.removeItem(at: url)
                    discardCurrentRecording = true
                    recordingAttemptLifecycles[attempt.id]?
                        .failAfterFinishTimeout()
                    state = .unavailable(error.localizedDescription)
                    completeRecordingAttempt(
                        attempt,
                        with: .failed(error)
                    )
                }
            case .fail:
                WorkoutRecordingDiagnostics.failure(
                    stage: "finish-timeout-invalid-media",
                    attemptID: attempt.id,
                    error: error
                )
                discardCurrentRecording = true
                recordingAttemptLifecycles[attempt.id]?
                    .failAfterFinishTimeout()
                state = .unavailable(error.localizedDescription)
                try? FileManager.default.removeItem(at: url)
                completeRecordingAttempt(
                    attempt,
                    with: .failed(error)
                )
            }
            if let resources {
                await stopCaptureSession(resources: resources)
            }
            await recoverCaptureIfNeeded()
        }
    }

    private func refreshCaptureGeometry() {
        guard !isCaptureGeometryLocked,
              let rotationCoordinator
        else {
            return
        }
        let geometry = Self.captureGeometry(
            previewRotationAngle: Double(
                rotationCoordinator.videoRotationAngleForHorizonLevelPreview
            ),
            captureRotationAngle: Double(
                rotationCoordinator.videoRotationAngleForHorizonLevelCapture
            ),
            isMirrored: true
        )
        captureGeometry = geometry
        applyCaptureGeometry(geometry)
    }

    private func lockCaptureGeometry() {
        refreshCaptureGeometry()
        isCaptureGeometryLocked = true
        applyCaptureGeometry(captureGeometry)
    }

    private func unlockCaptureGeometry() {
        isCaptureGeometryLocked = false
        refreshCaptureGeometry()
    }

    private func applyCaptureGeometry(_ geometry: WorkoutCaptureGeometry) {
        if let connection = sharedPreviewLayer.connection {
            if connection.isVideoRotationAngleSupported(
                CGFloat(geometry.previewRotationAngle)
            ) {
                connection.videoRotationAngle = CGFloat(
                    geometry.previewRotationAngle
                )
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = geometry.isMirrored
            }
        }
        let resources = captureResources
        let skipMovieOutputGeometry = state == .startingRecording
            || state == .recording
        resources.queue.async {
            // BUG 0025：录像已经开始或即将开始后改写 movieOutput 视频连接的旋转或镜像，
            // 会让 AVFoundation 结束这次录制并只留下几帧可播放文件。录像开始前几何已经
            // 锁定，录像中再写既违规又没有意义，所以这里直接跳过。
            guard !skipMovieOutputGeometry, !resources.movieOutput.isRecording else {
                WorkoutRecordingDiagnostics.breadcrumb(
                    stage: "capture-geometry-skipped-while-recording"
                )
                return
            }
            if let connection = resources.movieOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(
                    CGFloat(geometry.captureRotationAngle)
                ) {
                    connection.videoRotationAngle = CGFloat(
                        geometry.captureRotationAngle
                    )
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = geometry.isMirrored
                }
            }
        }
    }

    static func captureGeometry(
        previewRotationAngle: Double,
        captureRotationAngle: Double,
        isMirrored: Bool
    ) -> WorkoutCaptureGeometry {
        let normalized = normalizedAngle(captureRotationAngle)
        let orientation: WorkoutCaptureOrientation = switch normalized {
        case 0:
            .landscapeRight
        case 180:
            .landscapeLeft
        default:
            .portrait
        }
        return WorkoutCaptureGeometry(
            orientation: orientation,
            previewRotationAngle: normalizedAngle(previewRotationAngle),
            captureRotationAngle: normalized,
            isMirrored: isMirrored
        )
    }

    private static func normalizedAngle(_ value: Double) -> Double {
        let normalized = value.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        return (positive / 90).rounded() * 90
    }

    private var isPreviewCapableState: Bool {
        switch state {
        case .previewing, .startingRecording, .recording:
            true
        default:
            false
        }
    }

    /// BUG 0025：中断原因必须一路带到用户可见文案和诊断日志，不能压成一句通用提示。
    private func interrupt(
        diagnosis: WorkoutRecordingFailureDiagnosis,
        reasonCode: String
    ) async {
        let message = diagnosis.failureMessage
        let attempt = activeRecordingAttempt
        guard Self.shouldHandleLifecycleInterruption(
            state: state,
            hasActiveAttempt: attempt != nil,
            hasPreparation: preparationTask != nil
        ) else {
            WorkoutRecordingDiagnostics.breadcrumb(
                stage: "interruption-ignored",
                detail: reasonCode
            )
            return
        }
        shouldRecoverCapture = true
        WorkoutRecordingDiagnostics.interruption(
            reason: "\(reasonCode) \(diagnosis.cause) \(diagnosis.technical)",
            attemptID: attempt?.id
        )
        if let attempt {
            state = .unavailable(message)
            // AVFoundation can report an interruption error even after it has
            // produced a valid movie. Keep this attempt open until the file
            // delegate resolves the success key and file contents. The finish
            // timeout remains the sole fallback when no delegate arrives.
            recordingStartupTimeoutTask?.cancel()
            recordingStartupTimeoutTask = nil
            guard temporaryURL != nil else {
                invalidatePreparation(replacing: captureResources)
                completeRecordingAttempt(
                    attempt,
                    with: .failed(WorkoutCameraError.recordingFailed(message))
                )
                await recoverCaptureIfNeeded()
                return
            }
            recordingAttemptLifecycles[attempt.id]?.requestStop(
                reason: .unexpected(
                    message: diagnosis.partialRecordingMessage
                )
            )
            armRecordingFinishTimeout(for: attempt.id)
            let resources = activeCaptureResources(for: attempt.id)
            if let resources {
                resources.queue.async {
                    if resources.movieOutput.isRecording {
                        resources.movieOutput.stopRecording()
                    }
                }
            }
        } else {
            if preparationTask != nil {
                invalidatePreparation(replacing: captureResources)
            } else {
                await stopCaptureSession()
            }
        }
        state = .unavailable(message)
        if reasonCode == "runtime" {
            await recoverCaptureIfNeeded()
        }
    }

    private func recoverCaptureIfNeeded() async {
        guard shouldRecoverCapture,
              activeRecordingAttempt == nil,
              UIApplication.shared.applicationState == .active,
              ProcessInfo.processInfo.thermalState != .serious,
              ProcessInfo.processInfo.thermalState != .critical
        else { return }
        if requiresCaptureResourceRebuild {
            replaceCaptureResourcesIfCurrent(captureResources)
        }
        WorkoutRecordingDiagnostics.breadcrumb(stage: "recovery-request")
        do {
            try await prepare()
            shouldRecoverCapture = false
            WorkoutRecordingDiagnostics.breadcrumb(stage: "recovery-ready")
        } catch {
            WorkoutRecordingDiagnostics.failure(
                stage: "recovery",
                error: error
            )
        }
    }

    static func shouldHandleLifecycleInterruption(
        state: WorkoutCameraState,
        hasActiveAttempt: Bool,
        hasPreparation: Bool
    ) -> Bool {
        if hasActiveAttempt || hasPreparation {
            return true
        }
        switch state {
        case .requestingPermission,
             .configuring,
             .startingSession,
             .previewing,
             .startingRecording,
             .recording:
            return true
        case .idle, .unavailable:
            return false
        }
    }

    static func shouldRebuildCaptureResources(
        requiresRebuild: Bool,
        hasActiveAttempt: Bool
    ) -> Bool {
        requiresRebuild && !hasActiveAttempt
    }

    static func shouldRecoverAfterInterruptionEnded(
        isOwnedSession: Bool,
        shouldRecover: Bool
    ) -> Bool {
        isOwnedSession && shouldRecover
    }

    private func removeTemporaryRecordingIfPresent() {
        guard let temporaryURL else { return }
        try? FileManager.default.removeItem(at: temporaryURL)
        recordingAttemptsByURL.removeValue(forKey: temporaryURL)
        recordingResourcesByURL.removeValue(forKey: temporaryURL)
        self.temporaryURL = nil
    }
}

private final class MovieRecordingDelegate:
    NSObject,
    @unchecked Sendable,
    AVCaptureFileOutputRecordingDelegate
{
    var started: ((URL) -> Void)?
    var completion: ((URL, Error?) -> Void)?

    func fileOutput(
        _: AVCaptureFileOutput,
        didStartRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection]
    ) {
        started?(outputFileURL)
    }

    func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: Error?
    ) {
        completion?(outputFileURL, error)
    }
}

@MainActor
@Observable
final class WorkoutRuntime {
    let camera: WorkoutCameraService
    let coordinator: GuidedWorkoutCoordinator

    init() {
        let camera = WorkoutCameraService()
        self.camera = camera
        coordinator = GuidedWorkoutCoordinator(
            recorder: camera,
            cues: SystemWorkoutCueProvider()
        )
    }
}
