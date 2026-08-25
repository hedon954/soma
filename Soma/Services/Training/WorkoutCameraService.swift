@preconcurrency import AVFoundation
import Observation
import UIKit

enum WorkoutRecordingTerminalResult {
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

final class WorkoutCameraCaptureResources: @unchecked Sendable {
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
    var state: WorkoutCameraState = .idle
    var lastSavedPath: String?
    var captureGeometry = WorkoutCaptureGeometry.portrait
    var isCaptureGeometryLocked = false
    var isPreviewReady = false
    var previewIssueMessage: String?
    @ObservationIgnored let sharedPreviewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    @ObservationIgnored var captureResources =
        WorkoutCameraCaptureResources()
    @ObservationIgnored var rotationCoordinator:
        AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored var previewRotationObservation:
        NSKeyValueObservation?
    @ObservationIgnored var captureRotationObservation:
        NSKeyValueObservation?
    @ObservationIgnored var previewReadinessObservation:
        NSKeyValueObservation?
    @ObservationIgnored let recordingDelegate = MovieRecordingDelegate()
    @ObservationIgnored var temporaryURL: URL?
    @ObservationIgnored let stopWaiters =
        WorkoutRecordingStopWaiters()
    @ObservationIgnored let finishTimeoutResolver:
        WorkoutRecordingFinishTimeoutResolver
    @ObservationIgnored var startContinuation:
        CheckedContinuation<Void, Error>?
    @ObservationIgnored var discardCurrentRecording = false
    @ObservationIgnored var activeRecordingAttempt:
        WorkoutRecordingAttempt?
    @ObservationIgnored var terminalRecordingResults:
        [UUID: WorkoutRecordingTerminalResult] = [:]
    @ObservationIgnored var terminalRecordingOrder: [UUID] = []
    @ObservationIgnored var recordingAttemptsByURL:
        [URL: WorkoutRecordingAttempt] = [:]
    @ObservationIgnored var recordingResourcesByURL:
        [URL: WorkoutCameraCaptureResources] = [:]
    @ObservationIgnored var recordingAttemptLifecycles:
        [UUID: WorkoutRecordingAttemptLifecycle] = [:]
    @ObservationIgnored var observers: [NSObjectProtocol] = []
    @ObservationIgnored var preparationTask: Task<Void, Error>?
    @ObservationIgnored var preparationTaskID: UUID?
    @ObservationIgnored var activationGenerationGate =
        WorkoutCameraActivationGenerationGate()
    @ObservationIgnored var machineActivationContinuation:
        CheckedContinuation<WorkoutCameraRecordingReadiness, Error>?
    @ObservationIgnored var machineActivationGeneration: UUID?
    @ObservationIgnored var machineActivationTimeoutTask:
        Task<Void, Never>?
    @ObservationIgnored var pendingRecordingAttemptID: UUID?
    @ObservationIgnored var previewStartupTimeoutTask: Task<Void, Never>?
    @ObservationIgnored var recordingStartupTimeoutTask: Task<Void, Never>?
    @ObservationIgnored var recordingFinishTimeoutTask: Task<Void, Never>?
    @ObservationIgnored var activePreviewHostID: UUID?
    @ObservationIgnored var previewHostWaiters: [WorkoutPreviewHostWaiter] = []
    @ObservationIgnored var previewHostWaitTimeoutTask: Task<Void, Never>?
    @ObservationIgnored var shouldRecoverCapture = false
    @ObservationIgnored var requiresCaptureResourceRebuild = false
    @ObservationIgnored var ownedCaptureSessionIDs: Set<ObjectIdentifier> = []
    @ObservationIgnored var sessionOwnership =
        WorkoutCameraSessionOwnership()

    var captureSession: AVCaptureSession {
        captureResources.session
    }

    var captureDevice: AVCaptureDevice? {
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
        if GuidedPreviewHostSettlement.shouldReuseRunningCaptureSession(
            state: state,
            sessionIsRunning: captureSession.isRunning,
            sessionIsInterrupted: captureSession.isInterrupted
        ) {
            WorkoutRecordingDiagnostics.breadcrumb(
                stage: "prepare-reused-running-session",
                attemptID: pendingRecordingAttemptID
            )
            if state != .previewing,
               state != .recording,
               state != .startingRecording
            {
                state = .previewing
            }
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

    func performPreparation(generation: UUID) async throws {
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

    func continueRecordingStart(
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

    func recordingConnectionUnavailable(
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
        let rebuildConnections = GuidedPreviewHostSettlement.shouldRebuildCaptureConnections(
            cameraState: state,
            hasLivePreview: GuidedPreviewHostSettlement.hasLivePreview(
                layerHasSession: layer.session != nil,
                cameraState: state
            )
        )
        guard activePreviewHostID != hostID else {
            layer.videoGravity = videoGravity
            if rebuildConnections {
                applyCaptureGeometry(captureGeometry)
            }
            refreshPreviewConnectionState()
            return
        }

        activePreviewHostID = hostID
        if !rebuildConnections {
            layer.videoGravity = videoGravity
            observePreviewReadiness(on: layer, hostID: hostID)
            refreshPreviewConnectionState()
            resumeSettledPreviewHostWaiters()
            return
        }

        previewRotationObservation = nil
        captureRotationObservation = nil
        rotationCoordinator = nil
        previewReadinessObservation = nil
        previewStartupTimeoutTask?.cancel()
        isPreviewReady = false
        previewIssueMessage = nil
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
        resumeSettledPreviewHostWaiters()
    }

    func detachPreviewLayer(
        _ layer: AVCaptureVideoPreviewLayer,
        hostID: UUID
    ) {
        guard layer === sharedPreviewLayer, activePreviewHostID == hostID else {
            return
        }
        if !GuidedPreviewHostSettlement.shouldRebuildCaptureConnections(
            cameraState: state,
            hasLivePreview: GuidedPreviewHostSettlement.hasLivePreview(
                layerHasSession: layer.session != nil,
                cameraState: state
            )
        ) {
            WorkoutRecordingDiagnostics.breadcrumb(
                stage: "preview-detach-skipped-while-recording",
                attemptID: activeRecordingAttempt?.id,
                detail: WorkoutRecordingDiagnostics.callStackSummary()
            )
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

    func finishRecording(at url: URL, error: Error?) async {
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
                let path = try await MediaStore.saveVideoAsync(from: url)
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
                let path = try await MediaStore.saveVideoAsync(from: url)
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

    func recordingDidStart(at url: URL) {
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

    static func hasUsableRecordingFile(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ), let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    func completeRecordingAttempt(
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

    func cameraPermissionGranted() async -> Bool {
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
