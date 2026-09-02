@testable import Soma
import XCTest

final class CapturePresentationCoordinatorTests: XCTestCase {
    @MainActor
    func testInactiveRequestWaitsAndPresentsExactlyOnceAfterActivation() {
        let coordinator = CapturePresentationCoordinator()
        let request = CaptureEntryRequest(mode: .camera)

        XCTAssertTrue(coordinator.enqueue(request, sceneIsActive: false))
        XCTAssertEqual(coordinator.lifecycle, .waitingForActiveScene)
        XCTAssertNil(coordinator.presentation)

        coordinator.sceneBecameActive()
        XCTAssertEqual(coordinator.lifecycle, .presenting)
        XCTAssertEqual(coordinator.presentation?.requestID, request.id)

        coordinator.sceneBecameActive()
        XCTAssertEqual(coordinator.presentation?.requestID, request.id)
    }

    @MainActor
    func testDuplicateRequestIsIgnoredWhilePresenting() {
        let coordinator = CapturePresentationCoordinator()
        let first = CaptureEntryRequest(mode: .camera)
        let duplicate = CaptureEntryRequest(mode: .camera)

        XCTAssertTrue(coordinator.enqueue(first, sceneIsActive: true))
        XCTAssertFalse(coordinator.enqueue(duplicate, sceneIsActive: true))
        XCTAssertEqual(coordinator.presentation?.requestID, first.id)
    }

    @MainActor
    func testCancelClearsPresentationAndAllowsNextRequest() {
        let coordinator = CapturePresentationCoordinator()
        let first = CaptureEntryRequest(mode: .camera)
        let second = CaptureEntryRequest(mode: .media)
        XCTAssertTrue(coordinator.enqueue(first, sceneIsActive: true))

        XCTAssertTrue(coordinator.cancel(requestID: first.id))
        XCTAssertNil(coordinator.presentation)
        XCTAssertNil(coordinator.request)
        XCTAssertTrue(coordinator.enqueue(second, sceneIsActive: true))
        XCTAssertEqual(coordinator.presentation?.mode, .media)
    }

    @MainActor
    func testCompletionAndRepeatedDeliveryAreIdempotent() {
        let coordinator = CapturePresentationCoordinator()
        let request = CaptureEntryRequest(mode: .camera)
        XCTAssertTrue(coordinator.enqueue(request, sceneIsActive: true))

        XCTAssertTrue(coordinator.complete(requestID: request.id))
        XCTAssertFalse(coordinator.complete(requestID: request.id))
        XCTAssertNil(coordinator.presentation)
    }

    @MainActor
    func testSceneDeactivationCancelsPresentedCamera() {
        let coordinator = CapturePresentationCoordinator()
        let request = CaptureEntryRequest(mode: .camera)
        XCTAssertTrue(coordinator.enqueue(request, sceneIsActive: true))

        XCTAssertEqual(coordinator.cancelForSceneDeactivation(), request.id)
        XCTAssertNil(coordinator.presentation)
        XCTAssertEqual(coordinator.lifecycle, .cancelled)
    }
}
