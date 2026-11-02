@testable import Soma
import XCTest

@MainActor
private struct AutomaticRecordingSilentCues: WorkoutCueProviding {
    func announce(_: String) {}
    func success() {}
}

@MainActor
private final class SnapshotAwareRecordingSpy: WorkoutRecordingControlling {
    var recordingEventHandler: ((WorkoutRecordingAttemptEvent) -> Void)?
    private(set) var events: [String] = []
    var didPresentInProgressSnapshot = false

    func prepare() async throws {}

    func waitUntilPreviewHostSettled(from _: UUID?) async {
        events.append(
            didPresentInProgressSnapshot
                ? "wait-after-snapshot"
                : "wait-before-snapshot"
        )
    }

    func startRecording(attempt _: WorkoutRecordingAttempt) async throws {
        events.append("start-recording")
    }

    func markInProgressSnapshotPresented() {
        didPresentInProgressSnapshot = true
        events.append("present-snapshot")
    }

    func stopRecording(attemptID _: UUID) async throws -> String? {
        nil
    }

    func cancelRecording(attemptID _: UUID?) async {}
}

@MainActor
extension GuidedWorkoutCoordinatorTests {
    func testAutomaticRecordingWaitsForInProgressSnapshotPresentation() async throws {
        let fixture = try makeFixture(firstSetIsWarmup: false, setCount: 1)
        defer {
            fixture.defaults.removePersistentDomain(
                forName: fixture.suiteName
            )
        }
        let recorder = SnapshotAwareRecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: AutomaticRecordingSilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)

        let countdownTask = Task { @MainActor in
            try await coordinator.beginCurrentSet(in: fixture.context) {
                let snapshot = try? GuidedWorkoutScreenSnapshotLoader.load(
                    sessionID: fixture.session.id,
                    from: fixture.context.container
                )
                XCTAssertEqual(snapshot?.session.guidedPhase, .setInProgress)
                recorder.markInProgressSnapshotPresented()
                // SwiftUI 在快照切换后移除倒计时视图，从而取消拥有该
                // 回调的 `.task`。协调器仍须完成首组的自动录像启动。
                withUnsafeCurrentTask { task in
                    task?.cancel()
                }
            }
        }
        try await countdownTask.value

        XCTAssertEqual(recorder.events, [
            "present-snapshot",
            "wait-after-snapshot",
            "start-recording"
        ])
    }
}
