import Foundation
import Observation

enum CaptureRequestLifecycle: Equatable {
    case idle
    case queued
    case waitingForActiveScene
    case presenting
    case completed
    case cancelled
    case failed
}

struct CapturePresentation: Identifiable, Equatable {
    let id: UUID
    let requestID: UUID
    let mode: CaptureEntryMode
}

@MainActor
@Observable
final class CapturePresentationCoordinator {
    private(set) var lifecycle: CaptureRequestLifecycle = .idle
    private(set) var request: CaptureEntryRequest?
    var presentation: CapturePresentation?

    @discardableResult
    func enqueue(_ request: CaptureEntryRequest, sceneIsActive: Bool) -> Bool {
        guard self.request == nil, presentation == nil else { return false }
        self.request = request
        lifecycle = .queued
        if sceneIsActive {
            presentIfPossible()
        } else {
            lifecycle = .waitingForActiveScene
        }
        return true
    }

    func sceneBecameActive() {
        guard lifecycle == .waitingForActiveScene || lifecycle == .queued else { return }
        presentIfPossible()
    }

    func complete(requestID: UUID) -> Bool {
        guard request?.id == requestID, lifecycle == .presenting else { return false }
        lifecycle = .completed
        resetTransaction()
        return true
    }

    func cancel(requestID: UUID) -> Bool {
        guard request?.id == requestID else { return false }
        lifecycle = .cancelled
        resetTransaction()
        return true
    }

    func cancelForSceneDeactivation() -> UUID? {
        guard let request,
              lifecycle == .presenting
              || lifecycle == .queued
              || lifecycle == .waitingForActiveScene
        else {
            return nil
        }
        let id = request.id
        lifecycle = .cancelled
        resetTransaction()
        return id
    }

    func fail(requestID: UUID) -> Bool {
        guard request?.id == requestID else { return false }
        lifecycle = .failed
        resetTransaction()
        return true
    }

    private func presentIfPossible() {
        guard let request else { return }
        guard request.mode != .text else {
            lifecycle = .completed
            resetTransaction()
            return
        }
        lifecycle = .presenting
        presentation = CapturePresentation(
            id: request.id,
            requestID: request.id,
            mode: request.mode
        )
    }

    private func resetTransaction() {
        presentation = nil
        request = nil
    }
}
