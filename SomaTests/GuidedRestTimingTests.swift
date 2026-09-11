@testable import Soma
import SwiftUI
import XCTest

final class GuidedRestTimingTests: XCTestCase {
    @MainActor
    func testLatestSystemProjectionRunsAfterAnUncancellableOldWrite() async {
        let queue = WorkoutProjectionSerialQueue()
        let id = UUID()
        let started = expectation(description: "old system write started")
        var finishOldWrite: CheckedContinuation<Void, Never>?
        var writes: [String] = []
        let first = queue.enqueue(sessionID: id) {
            await withCheckedContinuation { continuation in
                finishOldWrite = continuation
                started.fulfill()
            }
            writes.append("old deadline")
        }
        await fulfillment(of: [started], timeout: 1)
        let skipped = queue.enqueue(sessionID: id) { writes.append("intermediate deadline") }
        let latest = queue.enqueue(sessionID: id) { writes.append("latest deadline") }
        XCTAssertTrue(first.isCancelled)
        XCTAssertTrue(skipped.isCancelled)
        finishOldWrite?.resume()
        await latest.value
        XCTAssertEqual(writes, ["old deadline", "latest deadline"])
    }

    @MainActor
    func testPausedAndCompletedRestDoNotProjectARunningCountdown() {
        let deadline = Date().addingTimeInterval(90)
        for status in [WorkoutSessionStatus.paused, .completed, .abandoned] {
            let state = WorkoutSystemProjectionCoordinator.contentState(
                status: status, guidedPhase: .resting, restTargetEndAt: deadline,
                completedSetCount: 1, totalSetCount: 5
            )
            XCTAssertNil(state.restEndAt, "\(status) must not run a lock-screen countdown")
        }
    }

    @MainActor
    func testRestDisplayCannotAdvanceSessionUsingItsCapturedDeadline() async {
        let advanced = expectation(description: "Only the coordinator may advance a rest deadline")
        advanced.isInverted = true
        let host = UIHostingController(rootView: GuidedRestView(
            nextTargetText: "虚构下一组",
            remainingSeconds: { 0 },
            onTick: { _ in },
            onAdjust: { _ in },
            onFinish: { advanced.fulfill() }
        ))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()

        // A mounted leaf can still have an expired deadline when the owner has
        // extended or paused the rest. It must never advance without validation.
        await fulfillment(of: [advanced], timeout: 0.8)
    }

    @MainActor
    func testAdjustedRestRejectsOldDeadlineAndAdvancesOnceAtNewDeadline() async throws {
        var time = Date(timeIntervalSince1970: 2_000_000_000)
        let fixture = try GuidedWorkoutCoordinatorTests().makeFixture(
            firstSetIsWarmup: false, setCount: 2, recordingPolicy: .disabled, now: time
        )
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let coordinator = GuidedWorkoutCoordinator(recorder: TimingRecorder(), cues: TimingCues(), now: { time })
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(actualReps: 8, actualWeightKG: 20, in: fixture.context)
        let oldRevision = fixture.session.transitionRevision
        let originalEnd = try XCTUnwrap(fixture.session.phaseDeadlineAt)

        try coordinator.adjustRest(by: 15, in: fixture.context)
        let extendedRevision = fixture.session.transitionRevision
        XCTAssertEqual(fixture.session.phaseDeadlineAt, originalEnd.addingTimeInterval(15))
        XCTAssertEqual(fixture.session.phaseDeadlineAt, fixture.session.restTargetEndAt)
        time = originalEnd
        try await coordinator.advanceTimelineIfDue(expectedRevision: oldRevision, in: fixture.context)
        try await coordinator.advanceTimelineIfDue(expectedRevision: extendedRevision, in: fixture.context)
        XCTAssertEqual(fixture.session.guidedPhase, .resting)
        XCTAssertEqual(coordinator.remainingRestSeconds(for: fixture.session, in: fixture.context), 15)

        try coordinator.adjustRest(by: -30, in: fixture.context)
        let shortenedRevision = fixture.session.transitionRevision
        XCTAssertEqual(fixture.session.phaseDeadlineAt, time)
        try await coordinator.advanceTimelineIfDue(expectedRevision: shortenedRevision, in: fixture.context)
        XCTAssertEqual(fixture.session.guidedPhase, .preSetCountdown)
        let countdownRevision = fixture.session.transitionRevision
        try await coordinator.advanceTimelineIfDue(expectedRevision: shortenedRevision, in: fixture.context)
        XCTAssertEqual(fixture.session.transitionRevision, countdownRevision)
        XCTAssertEqual(fixture.sets[0].actualRestSeconds, 90)
    }

    @MainActor
    func testPausedRestCannotExpireAndResumePreservesRemainingTime() async throws {
        var time = Date(timeIntervalSince1970: 2_000_000_000)
        let fixture = try GuidedWorkoutCoordinatorTests().makeFixture(
            firstSetIsWarmup: false, setCount: 2, recordingPolicy: .disabled, now: time
        )
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let coordinator = GuidedWorkoutCoordinator(recorder: TimingRecorder(), cues: TimingCues(), now: { time })
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(actualReps: 8, actualWeightKG: 20, in: fixture.context)
        time = time.addingTimeInterval(20)
        try await coordinator.pause(in: fixture.context)
        let pausedRevision = fixture.session.transitionRevision
        time = time.addingTimeInterval(120)
        try await coordinator.advanceTimelineIfDue(expectedRevision: pausedRevision, in: fixture.context)
        XCTAssertEqual(fixture.session.guidedPhase, .resting)
        try coordinator.resume(in: fixture.context)
        XCTAssertEqual(coordinator.remainingRestSeconds(for: fixture.session, in: fixture.context), 70)
    }
}

@MainActor
private final class TimingRecorder: WorkoutRecordingControlling {
    var recordingEventHandler: ((WorkoutRecordingAttemptEvent) -> Void)?
    func prepare() async throws {}
    func startRecording(attempt _: WorkoutRecordingAttempt) async throws {}
    func stopRecording(attemptID _: UUID) async throws -> String? {
        nil
    }

    func cancelRecording(attemptID _: UUID?) async {}
}

@MainActor
private struct TimingCues: WorkoutCueProviding {
    func announce(_: String) {}
    func success() {}
}
