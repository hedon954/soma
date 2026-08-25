@preconcurrency import AVFoundation
import Observation
import UIKit

@MainActor
extension WorkoutCameraService {
    var previewHostID: UUID? {
        activePreviewHostID
    }

    func waitUntilPreviewHostSettled(from previousHostID: UUID?) async {
        if GuidedPreviewHostSettlement.isSettled(
            currentHostID: activePreviewHostID,
            previousHostID: previousHostID
        ) {
            return
        }
        await withCheckedContinuation { continuation in
            previewHostWaiters.append(
                WorkoutPreviewHostWaiter(
                    previousHostID: previousHostID,
                    continuation: continuation
                )
            )
            previewHostWaitTimeoutTask?.cancel()
            previewHostWaitTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                self?.resumeAllPreviewHostWaiters()
            }
        }
    }

    func resumeSettledPreviewHostWaiters() {
        let remaining = previewHostWaiters.filter { waiter in
            if GuidedPreviewHostSettlement.isSettled(
                currentHostID: activePreviewHostID,
                previousHostID: waiter.previousHostID
            ) {
                waiter.continuation.resume()
                return false
            }
            return true
        }
        previewHostWaiters = remaining
        if remaining.isEmpty {
            previewHostWaitTimeoutTask?.cancel()
            previewHostWaitTimeoutTask = nil
        }
    }

    func resumeAllPreviewHostWaiters() {
        let waiters = previewHostWaiters
        previewHostWaiters = []
        previewHostWaitTimeoutTask?.cancel()
        previewHostWaitTimeoutTask = nil
        waiters.forEach { $0.continuation.resume() }
    }

    func idlePreviewKeepingSessionOwner() async {
        guard sessionOwnership.activeOwner != nil,
              state != .startingRecording, state != .recording else { return }
        shouldRecoverCapture = false
        await stopCaptureSession()
    }
}
