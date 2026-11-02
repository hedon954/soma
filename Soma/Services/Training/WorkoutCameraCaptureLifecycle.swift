@preconcurrency import AVFoundation
import Observation
import UIKit

@MainActor
extension WorkoutCameraService {
    func activateCaptureResources(
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

    func completeMachineActivation(
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

    func stopStaleCaptureResources(
        _ resources: WorkoutCameraCaptureResources
    ) {
        guard resources !== captureResources else { return }
        resources.queue.async {
            if resources.session.isRunning {
                resources.session.stopRunning()
            }
        }
    }

    func replaceCaptureResourcesIfCurrent(
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

    func invalidatePreparation(
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

    func supersedeCaptureIntentForNewWorkoutSession() {
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

    func commitWorkoutSessionEnd(
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

    func resetExplicitPreviewState() {
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

    func activeCaptureResources(
        for attemptID: UUID
    ) -> WorkoutCameraCaptureResources? {
        guard activeRecordingAttempt?.id == attemptID else { return nil }
        if let temporaryURL {
            return recordingResourcesByURL[temporaryURL]
        }
        return captureResources
    }

    func stopCaptureSession() async {
        await stopCaptureSession(resources: captureResources)
    }

    func stopCaptureSession(
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

    var hasRecordingCapacity: Bool {
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

    func installObservers() {
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

    func configureRotationCoordinatorIfPossible() {
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

    func refreshPreviewConnectionState() {
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

    func observePreviewReadiness(
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

    func armPreviewStartupTimeout() {
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

    func armRecordingStartupTimeout() {
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
            state = .unavailable(AppErrorMessage.message(for: error, operation: .recording))
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

    func armRecordingFinishTimeout(for attemptID: UUID) {
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
                    let path = try await MediaStore.saveVideoAsync(from: url)
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
                    state = .unavailable(AppErrorMessage.message(for: error, operation: .recording))
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
                state = .unavailable(AppErrorMessage.message(for: error, operation: .recording))
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

    func refreshCaptureGeometry() {
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

    func lockCaptureGeometry() {
        refreshCaptureGeometry()
        isCaptureGeometryLocked = true
        applyCaptureGeometry(captureGeometry)
    }

    func unlockCaptureGeometry() {
        isCaptureGeometryLocked = false
        refreshCaptureGeometry()
    }

    func applyCaptureGeometry(_ geometry: WorkoutCaptureGeometry) {
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
            // BUG 0025：录像已开始后改写 movieOutput 连接会结束当前文件，这里直接跳过。
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

    static func normalizedAngle(_ value: Double) -> Double {
        let normalized = value.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        return (positive / 90).rounded() * 90
    }

    var isPreviewCapableState: Bool {
        switch state {
        case .previewing, .startingRecording, .recording:
            true
        default:
            false
        }
    }

    func interrupt(
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
        if GuidedPreviewHostSettlement.shouldIgnoreTransientPreviewInterruption(
            reasonCode: reasonCode,
            hasActiveAttempt: attempt != nil,
            hasSessionOwner: sessionOwnership.activeOwner != nil
        ) {
            shouldRecoverCapture = true
            WorkoutRecordingDiagnostics.breadcrumb(
                stage: "interruption-ignored",
                detail: "\(reasonCode)-while-previewing"
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
        } else if preparationTask != nil {
            invalidatePreparation(replacing: captureResources)
        } else {
            await stopCaptureSession()
        }
        state = .unavailable(message)
        if reasonCode == "runtime" {
            await recoverCaptureIfNeeded()
        }
    }

    func recoverCaptureIfNeeded() async {
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

    func removeTemporaryRecordingIfPresent() {
        guard let temporaryURL else { return }
        try? FileManager.default.removeItem(at: temporaryURL)
        recordingAttemptsByURL.removeValue(forKey: temporaryURL)
        recordingResourcesByURL.removeValue(forKey: temporaryURL)
        self.temporaryURL = nil
    }
}
