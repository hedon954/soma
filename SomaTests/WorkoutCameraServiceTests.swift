import AVFoundation
@testable import Soma
import XCTest

final class WorkoutCameraServiceTests: XCTestCase {
    @MainActor
    func testCameraCompletionPreservesActionableInterruption() {
        let interruption = WorkoutCameraState.unavailable("相机被系统中断")

        XCTAssertEqual(
            WorkoutCameraService.settledState(
                after: interruption,
                sessionIsRunning: true
            ),
            interruption
        )
        XCTAssertEqual(
            WorkoutCameraService.settledState(
                after: .recording,
                sessionIsRunning: true
            ),
            .previewing
        )
        XCTAssertEqual(
            WorkoutCameraService.settledState(
                after: .recording,
                sessionIsRunning: false
            ),
            .idle
        )

        XCTAssertEqual(
            WorkoutCameraService.captureGeometry(
                previewRotationAngle: 450,
                captureRotationAngle: 90,
                isMirrored: true
            ),
            WorkoutCaptureGeometry(
                orientation: .portrait,
                previewRotationAngle: 90,
                captureRotationAngle: 90,
                isMirrored: true
            )
        )
        XCTAssertEqual(
            WorkoutCameraService.captureGeometry(
                previewRotationAngle: 180,
                captureRotationAngle: 180,
                isMirrored: true
            ).orientation,
            .landscapeLeft
        )
        XCTAssertEqual(
            WorkoutCameraService.captureGeometry(
                previewRotationAngle: 0,
                captureRotationAngle: 0,
                isMirrored: true
            ).orientation,
            .landscapeRight
        )
        XCTAssertTrue(WorkoutCameraService.hasSufficientRecordingCapacity(nil))
        XCTAssertFalse(WorkoutCameraService.hasSufficientRecordingCapacity(50 * 1024 * 1024))
        XCTAssertTrue(WorkoutCameraService.hasSufficientRecordingCapacity(200 * 1024 * 1024))
    }

    @MainActor
    func testDelegateSuccessKeyOverridesInterruptionErrorForUsableFile() {
        let successfulFinishError = NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.unknown.rawValue,
            userInfo: [AVErrorRecordingSuccessfullyFinishedKey: true]
        )
        XCTAssertTrue(WorkoutCameraService.recordingFinishedSuccessfully(
            error: successfulFinishError,
            hasUsableFile: true
        ))
        XCTAssertFalse(WorkoutCameraService.recordingFinishedSuccessfully(
            error: successfulFinishError,
            hasUsableFile: false
        ))
        XCTAssertFalse(WorkoutCameraService.recordingFinishedSuccessfully(
            error: NSError(
                domain: AVFoundationErrorDomain,
                code: AVError.unknown.rawValue,
                userInfo: [AVErrorRecordingSuccessfullyFinishedKey: false]
            ),
            hasUsableFile: true
        ))

        let attemptID = UUID()
        let diagnostics = WorkoutRecordingDiagnostics.metadata(
            stage: "finish",
            attemptID: attemptID,
            error: NSError(
                domain: AVFoundationErrorDomain,
                code: AVError.unknown.rawValue,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "杠铃深蹲 80kg /private/var/mobile/secret.mov"
                ]
            )
        )
        XCTAssertTrue(diagnostics.contains(attemptID.uuidString))
        XCTAssertTrue(diagnostics.contains("stage=finish"))
        XCTAssertFalse(diagnostics.contains("杠铃深蹲"))
        XCTAssertFalse(diagnostics.contains("80kg"))
        XCTAssertFalse(diagnostics.contains("secret.mov"))
        XCTAssertFalse(
            WorkoutRecordingDiagnostics.callStackSummary()
                .contains(NSHomeDirectory())
        )
    }

    @MainActor
    func testLateDelegateSuccessAfterStartupTimeoutRemainsSavable() {
        let lateFinishError = NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.unknown.rawValue,
            userInfo: [AVErrorRecordingSuccessfullyFinishedKey: true]
        )

        let finishedSuccessfully = WorkoutCameraService.recordingFinishedSuccessfully(
            error: lateFinishError,
            hasUsableFile: true
        )
        var lifecycle = WorkoutRecordingAttemptLifecycle()
        lifecycle.requestStop(
            reason: .unexpected(message: "已保留部分录像")
        )

        XCTAssertEqual(lifecycle.phase, .finishing)
        XCTAssertFalse(lifecycle.shouldDiscard)
        XCTAssertFalse(lifecycle.isTerminal)
        XCTAssertEqual(
            lifecycle.delegateDisposition(
                finishedSuccessfully: finishedSuccessfully
            ),
            .persistPartial(message: "已保留部分录像")
        )
        lifecycle.finish(.saved)
        XCTAssertEqual(lifecycle.phase, .terminal(.saved))
    }

    @MainActor
    func testInterruptionLifecycleAwaitsDelegateWithoutDiscarding() {
        var lifecycle = WorkoutRecordingAttemptLifecycle()
        lifecycle.markStarted()
        lifecycle.requestStop(
            reason: .unexpected(message: "系统中断，已保留部分录像")
        )

        XCTAssertEqual(lifecycle.phase, .finishing)
        XCTAssertFalse(lifecycle.shouldDiscard)
        XCTAssertEqual(
            lifecycle.delegateDisposition(finishedSuccessfully: true),
            .persistPartial(message: "系统中断，已保留部分录像")
        )
        lifecycle.finish(.saved)
        XCTAssertEqual(lifecycle.phase, .terminal(.saved))
    }

    func testExpiredActivationRejectsLateCompletionAndAllowsFreshRetry() {
        var gate = WorkoutCameraActivationGenerationGate()
        let hungGeneration = gate.begin()

        XCTAssertTrue(gate.isCurrent(hungGeneration))
        XCTAssertTrue(gate.expire(hungGeneration))
        XCTAssertFalse(gate.accept(hungGeneration))

        let retryGeneration = gate.begin()
        XCTAssertNotEqual(retryGeneration, hungGeneration)
        XCTAssertTrue(gate.isCurrent(retryGeneration))
        XCTAssertTrue(gate.accept(retryGeneration))
        XCTAssertNil(gate.activeGeneration)
    }

    @MainActor
    func testNonblockingStopSettlesStateAndAllowsFreshResourceGeneration() {
        var gate = WorkoutCameraActivationGenerationGate()
        let oldGeneration = gate.begin()
        XCTAssertEqual(gate.supersede(), oldGeneration)
        XCTAssertEqual(
            WorkoutCameraService.settledState(
                after: .recording,
                sessionIsRunning: false
            ),
            .idle
        )

        let retryGeneration = gate.begin()
        XCTAssertFalse(gate.accept(oldGeneration))
        XCTAssertTrue(gate.accept(retryGeneration))
    }

    @MainActor
    func testConcurrentDuplicateStopWaitersReceiveSameTerminalResult() async throws {
        let waiters = WorkoutRecordingStopWaiters()
        let attemptID = UUID()
        let firstRegistered = expectation(description: "first stop registered")
        let secondRegistered = expectation(description: "second stop registered")
        var commandCount = 0

        let first = Task { @MainActor in
            try await waiters.wait(for: attemptID) { isFirstWaiter in
                XCTAssertTrue(isFirstWaiter)
                commandCount += 1
                firstRegistered.fulfill()
            }
        }
        await fulfillment(of: [firstRegistered], timeout: 1)

        let second = Task { @MainActor in
            try await waiters.wait(for: attemptID) { isFirstWaiter in
                XCTAssertFalse(isFirstWaiter)
                if isFirstWaiter {
                    commandCount += 1
                }
                secondRegistered.fulfill()
            }
        }
        await fulfillment(of: [secondRegistered], timeout: 1)

        XCTAssertEqual(waiters.waiterCount(for: attemptID), 2)
        XCTAssertEqual(commandCount, 1)
        waiters.resolve(
            attemptID: attemptID,
            with: .success("saved-partial.mov")
        )

        let firstPath = try await first.value
        let secondPath = try await second.value
        XCTAssertEqual(firstPath, "saved-partial.mov")
        XCTAssertEqual(secondPath, "saved-partial.mov")
        XCTAssertEqual(waiters.waiterCount(for: attemptID), 0)
    }

    func testFinishTimeoutSalvagesMediaWithReadableVideoTrack() async {
        let resolver = WorkoutRecordingFinishTimeoutResolver(
            verifier: StubWorkoutRecordingMediaVerifier(result: true),
            validationDeadline: .seconds(1)
        )

        let disposition = await resolver.resolve(
            at: URL(fileURLWithPath: "/tmp/virtual-readable-video.mov")
        )

        XCTAssertEqual(disposition, .savePartial)
    }

    func testFinishTimeoutRejectsFileWithoutReadableVideoTrack() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        try Data("not a movie".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let resolver = WorkoutRecordingFinishTimeoutResolver(
            validationDeadline: .seconds(1)
        )

        let disposition = await resolver.resolve(at: url)

        XCTAssertEqual(disposition, .fail)
    }

    @MainActor
    func testExplicitSessionTeardownClearsUnavailableStateForFreshSession() {
        XCTAssertEqual(
            WorkoutCameraService.stateAfterExplicitTeardown(
                .unavailable("旧会话错误")
            ),
            .idle
        )
        var gate = WorkoutCameraActivationGenerationGate()
        let oldGeneration = gate.begin()
        XCTAssertEqual(gate.supersede(), oldGeneration)
        let freshGeneration = gate.begin()
        XCTAssertFalse(gate.accept(oldGeneration))
        XCTAssertTrue(gate.accept(freshGeneration))
    }

    func testWorkoutSessionOwnerGenerationRejectsPreviousClaim() {
        var ownership = WorkoutCameraSessionOwnership()
        let sessionID = UUID()
        let previousOwner = ownership.claim(sessionID: sessionID)
        let currentOwner = ownership.claim(sessionID: sessionID)

        XCTAssertNotEqual(previousOwner.generation, currentOwner.generation)
        XCTAssertFalse(ownership.accepts(previousOwner))
        XCTAssertTrue(ownership.accepts(currentOwner))
        XCTAssertFalse(ownership.release(previousOwner))
        XCTAssertEqual(ownership.activeOwner, currentOwner)
    }

    @MainActor
    func testLateOldOwnerTeardownCannotAlterNewOwnerStateOrResources() async {
        let camera = WorkoutCameraService()
        let previousOwner = camera.claimWorkoutSession(sessionID: UUID())
        let teardownSuspended = expectation(
            description: "old owner teardown suspended"
        )
        var resumeTeardown: CheckedContinuation<Void, Never>?
        let lateTeardown = Task { @MainActor in
            await camera.finishWorkoutSessionTeardownForTesting(
                owner: previousOwner
            ) {
                await withCheckedContinuation { continuation in
                    resumeTeardown = continuation
                    teardownSuspended.fulfill()
                }
            }
        }
        await fulfillment(of: [teardownSuspended], timeout: 1)

        let currentOwner = camera.claimWorkoutSession(sessionID: UUID())
        camera.useCameraStateForTesting(.startingSession)
        let currentResourceIdentity = camera
            .captureResourceIdentityForTesting
        resumeTeardown?.resume()
        resumeTeardown = nil
        await lateTeardown.value

        XCTAssertEqual(
            camera.activeWorkoutSessionOwnerForTesting,
            currentOwner
        )
        XCTAssertEqual(camera.state, .startingSession)
        XCTAssertEqual(
            camera.captureResourceIdentityForTesting,
            currentResourceIdentity
        )
        await camera.endWorkoutSession(owner: currentOwner)
    }

    func testPreflightCancellationSupersedesPermissionAndCannotPublishIntoRetry() {
        var gate = WorkoutCameraActivationGenerationGate()
        let permissionGeneration = gate.begin()

        XCTAssertEqual(gate.supersede(), permissionGeneration)
        let retryGeneration = gate.begin()

        XCTAssertFalse(gate.accept(permissionGeneration))
        XCTAssertTrue(gate.accept(retryGeneration))
    }

    func testRecordingReadinessRejectsEveryInvalidConnectionState() {
        let ready = WorkoutCameraRecordingReadiness(
            sessionIsRunning: true,
            sessionIsInterrupted: false,
            hasVideoConnection: true,
            videoConnectionIsEnabled: true,
            videoConnectionIsActive: true,
            outputIsRecording: false
        )
        XCTAssertNil(ready.failure)

        var value = ready
        value.sessionIsRunning = false
        XCTAssertEqual(value.failure, .sessionNotRunning)
        value = ready
        value.sessionIsInterrupted = true
        XCTAssertEqual(value.failure, .sessionInterrupted)
        value = ready
        value.hasVideoConnection = false
        XCTAssertEqual(value.failure, .videoConnectionMissing)
        value = ready
        value.videoConnectionIsEnabled = false
        XCTAssertEqual(value.failure, .videoConnectionDisabled)
        value = ready
        value.videoConnectionIsActive = false
        XCTAssertEqual(value.failure, .videoConnectionInactive)
        value = ready
        value.outputIsRecording = true
        XCTAssertEqual(value.failure, .outputAlreadyRecording)
        XCTAssertEqual(
            WorkoutCameraRecordingReadinessFailure.videoConnectionInactive
                .userFacingReason,
            "录像连接尚未激活"
        )
    }

    func testExpectedStopPersistsAsFullRecording() {
        var lifecycle = WorkoutRecordingAttemptLifecycle()
        lifecycle.markStarted()
        lifecycle.requestStop(reason: .expected)

        XCTAssertEqual(
            lifecycle.delegateDisposition(finishedSuccessfully: true),
            .persist
        )
    }

    func testCancellationBeforeMovieCommandRejectsLateSuccessfulFinish() {
        var lifecycle = WorkoutRecordingAttemptLifecycle()
        lifecycle.requestStop(reason: .cancelled)

        XCTAssertTrue(lifecycle.shouldDiscard)
        XCTAssertEqual(
            lifecycle.delegateDisposition(finishedSuccessfully: true),
            .cancel
        )
    }

    @MainActor
    func testIdleLifecycleDoesNotCreateCameraIntent() {
        XCTAssertFalse(WorkoutCameraService.shouldHandleLifecycleInterruption(
            state: .idle,
            hasActiveAttempt: false,
            hasPreparation: false
        ))
        XCTAssertTrue(WorkoutCameraService.shouldHandleLifecycleInterruption(
            state: .requestingPermission,
            hasActiveAttempt: false,
            hasPreparation: true
        ))
        XCTAssertTrue(WorkoutCameraService.shouldHandleLifecycleInterruption(
            state: .previewing,
            hasActiveAttempt: false,
            hasPreparation: false
        ))
    }

    @MainActor
    func testMediaServicesResetRebuildsBeforeNextPreparation() {
        XCTAssertTrue(WorkoutCameraService.shouldRebuildCaptureResources(
            requiresRebuild: true,
            hasActiveAttempt: false
        ))
        XCTAssertFalse(WorkoutCameraService.shouldRebuildCaptureResources(
            requiresRebuild: true,
            hasActiveAttempt: true
        ))
        XCTAssertFalse(WorkoutCameraService.shouldRebuildCaptureResources(
            requiresRebuild: false,
            hasActiveAttempt: false
        ))
    }

    @MainActor
    func testOwnedOldSessionInterruptionEndCanRecoverReplacementSession() {
        XCTAssertTrue(WorkoutCameraService.shouldRecoverAfterInterruptionEnded(
            isOwnedSession: true,
            shouldRecover: true
        ))
        XCTAssertFalse(WorkoutCameraService.shouldRecoverAfterInterruptionEnded(
            isOwnedSession: false,
            shouldRecover: true
        ))
        XCTAssertFalse(WorkoutCameraService.shouldRecoverAfterInterruptionEnded(
            isOwnedSession: true,
            shouldRecover: false
        ))
    }

    func testCountdownClockReachesZeroAndBecomesDue() {
        let startedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let clock = GuidedSetCountdownClock(startedAt: startedAt)

        XCTAssertEqual(clock.remaining(at: startedAt), 3)
        XCTAssertEqual(
            clock.remaining(at: startedAt.addingTimeInterval(2.01)),
            1
        )
        XCTAssertEqual(
            clock.remaining(at: startedAt.addingTimeInterval(3)),
            0
        )
        XCTAssertTrue(clock.isDue(at: startedAt.addingTimeInterval(3)))
        XCTAssertEqual(
            clock.delay(at: startedAt.addingTimeInterval(4)),
            0
        )
    }

    func testSetStartExpandsCaptureAndCollapseSurvivesRecording() {
        var state = GuidedWorkoutPresentationState()

        state.cameraStateChanged(.previewing)
        XCTAssertEqual(state.mode, .compact)

        state.phaseChanged(.setInProgress, expandForRecording: true)
        state.cameraStateChanged(.idle, isStartingRecording: true)
        XCTAssertEqual(state.mode, .expandedCapture)

        state.collapse()
        state.cameraStateChanged(.recording)
        XCTAssertEqual(state.mode, .compact)
        XCTAssertFalse(
            GuidedExpandedCaptureVisibility.isVisible(
                sessionIsActive: true,
                mode: state.mode,
                phase: .setInProgress,
                cameraState: .recording,
                isStartingRecording: false
            )
        )

        state.phaseChanged(.resting)
        XCTAssertEqual(state.mode, .compact)
    }

    func testPreviewHostSettlementWaitsForANewHost() {
        let countdownHost = UUID()
        let setHost = UUID()
        XCTAssertFalse(
            GuidedPreviewHostSettlement.isSettled(
                currentHostID: nil,
                previousHostID: countdownHost
            )
        )
        XCTAssertFalse(
            GuidedPreviewHostSettlement.isSettled(
                currentHostID: countdownHost,
                previousHostID: countdownHost
            )
        )
        XCTAssertTrue(
            GuidedPreviewHostSettlement.isSettled(
                currentHostID: setHost,
                previousHostID: countdownHost
            )
        )
        XCTAssertTrue(
            GuidedPreviewHostSettlement.isSettled(
                currentHostID: setHost,
                previousHostID: nil
            )
        )
        XCTAssertFalse(
            GuidedPreviewHostSettlement.shouldRebuildCaptureConnections(
                cameraState: .startingRecording
            )
        )
        XCTAssertFalse(
            GuidedPreviewHostSettlement.shouldRebuildCaptureConnections(
                cameraState: .recording
            )
        )
        XCTAssertFalse(
            GuidedPreviewHostSettlement.shouldRebuildCaptureConnections(
                cameraState: .previewing,
                hasLivePreview: true
            )
        )
        XCTAssertTrue(
            GuidedPreviewHostSettlement.shouldRebuildCaptureConnections(
                cameraState: .previewing,
                hasLivePreview: false
            )
        )
        XCTAssertTrue(
            GuidedPreviewHostSettlement.hasLivePreview(
                layerHasSession: true,
                cameraState: .previewing
            )
        )
        XCTAssertFalse(
            GuidedPreviewHostSettlement.hasLivePreview(
                layerHasSession: false,
                cameraState: .previewing
            )
        )
        XCTAssertTrue(
            GuidedPreviewHostSettlement.shouldReuseRunningCaptureSession(
                state: .idle,
                sessionIsRunning: true,
                sessionIsInterrupted: false
            )
        )
        XCTAssertFalse(
            GuidedPreviewHostSettlement.shouldReuseRunningCaptureSession(
                state: .previewing,
                sessionIsRunning: true,
                sessionIsInterrupted: true
            )
        )
        XCTAssertTrue(
            GuidedPreviewHostSettlement.shouldIgnoreTransientPreviewInterruption(
                reasonCode: "session-interruption",
                hasActiveAttempt: false,
                hasSessionOwner: true
            )
        )
        XCTAssertFalse(
            GuidedPreviewHostSettlement.shouldIgnoreTransientPreviewInterruption(
                reasonCode: "background",
                hasActiveAttempt: false,
                hasSessionOwner: true
            )
        )
        XCTAssertFalse(
            GuidedPreviewHostSettlement.shouldIgnoreTransientPreviewInterruption(
                reasonCode: "session-interruption",
                hasActiveAttempt: true,
                hasSessionOwner: true
            )
        )
    }
}

private struct StubWorkoutRecordingMediaVerifier:
    WorkoutRecordingMediaVerifying
{
    let result: Bool

    func hasReadableVideoTrack(at _: URL) async -> Bool {
        result
    }
}
