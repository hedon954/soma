@testable import Soma
import XCTest

final class ForegroundRecoveryCoordinatorTests: XCTestCase {
    @MainActor
    func testLatestGenerationSupersedesPendingRecovery() async {
        let coordinator = ForegroundRecoveryCoordinator()
        var firstFrame: CheckedContinuation<Void, Never>?
        var firstRuns = 0
        var secondRuns = 0

        coordinator.schedule(waitForFrame: {
            await withCheckedContinuation { firstFrame = $0 }
        }) { _ in
            firstRuns += 1
        }
        await Task.yield()
        coordinator.schedule(waitForFrame: {}) { _ in
            secondRuns += 1
        }
        firstFrame?.resume()
        await Task.yield()

        XCTAssertEqual(firstRuns, 0)
        XCTAssertEqual(secondRuns, 1)
    }

    @MainActor
    func testSceneCancellationPreventsRecovery() async {
        let coordinator = ForegroundRecoveryCoordinator()
        var frame: CheckedContinuation<Void, Never>?
        var runs = 0

        coordinator.schedule(waitForFrame: {
            await withCheckedContinuation { frame = $0 }
        }) { _ in
            runs += 1
        }
        await Task.yield()
        coordinator.cancel()
        frame?.resume()
        await Task.yield()

        XCTAssertEqual(runs, 0)
    }
}
