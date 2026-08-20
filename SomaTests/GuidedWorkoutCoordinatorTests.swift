import AVFoundation
@testable import Soma
import SwiftData
import XCTest

@MainActor
private final class RecordingSpy: WorkoutRecordingControlling {
    var recordingEventHandler: ((WorkoutRecordingAttemptEvent) -> Void)?
    var startedPerformanceIDs: [UUID] = []
    var startedSetIDs: [UUID] = []
    var startedEffortIDs: [UUID] = []
    var prepareCount = 0
    var stopCount = 0
    var cancelCount = 0
    var path: String? = "PrivateMedia/test-guided.mov"

    func prepare() async throws {
        prepareCount += 1
    }

    func startRecording(attempt: WorkoutRecordingAttempt) async throws {
        startedPerformanceIDs.append(attempt.performanceID)
        startedSetIDs.append(attempt.setID)
        if let effortID = attempt.effortID {
            startedEffortIDs.append(effortID)
        }
    }

    func stopRecording(attemptID _: UUID) async throws -> String? {
        stopCount += 1
        return path
    }

    func cancelRecording(attemptID _: UUID?) async {
        cancelCount += 1
    }
}

@MainActor
private final class SuspendedRecordingSpy: WorkoutRecordingControlling {
    var recordingEventHandler: ((WorkoutRecordingAttemptEvent) -> Void)?
    private(set) var startInvoked = false
    private var continuation: CheckedContinuation<Void, Never>?

    func prepare() async throws {}

    func startRecording(attempt _: WorkoutRecordingAttempt) async throws {
        startInvoked = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func stopRecording(attemptID _: UUID) async throws -> String? {
        nil
    }

    func cancelRecording(attemptID _: UUID?) async {}

    func resumeStart() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class FailingRecordingSpy: WorkoutRecordingControlling {
    var recordingEventHandler: ((WorkoutRecordingAttemptEvent) -> Void)?
    private(set) var startCount = 0

    func prepare() async throws {}

    func startRecording(attempt _: WorkoutRecordingAttempt) async throws {
        startCount += 1
        throw WorkoutCameraError.recordingFailed("虚构启动失败")
    }

    func stopRecording(attemptID _: UUID) async throws -> String? {
        nil
    }

    func cancelRecording(attemptID _: UUID?) async {}
}

@MainActor
private final class SequencedRecordingSpy: WorkoutRecordingControlling {
    var recordingEventHandler: ((WorkoutRecordingAttemptEvent) -> Void)?
    private(set) var attempts: [WorkoutRecordingAttempt] = []
    private let failingStartNumbers: Set<Int>

    init(failingStartNumbers: Set<Int>) {
        self.failingStartNumbers = failingStartNumbers
    }

    func prepare() async throws {}

    func startRecording(attempt: WorkoutRecordingAttempt) async throws {
        attempts.append(attempt)
        if failingStartNumbers.contains(attempts.count) {
            throw WorkoutCameraError.recordingFailed("虚构第 \(attempts.count) 次失败")
        }
        recordingEventHandler?(.started(attempt))
    }

    func stopRecording(attemptID: UUID) async throws -> String? {
        let path = "PrivateMedia/manual-retry.mov"
        if let attempt = attempts.first(where: { $0.id == attemptID }) {
            recordingEventHandler?(.saved(attempt, path: path))
        }
        return path
    }

    func cancelRecording(attemptID _: UUID?) async {}
}

@MainActor
private final class EarlyTerminalRecordingSpy: WorkoutRecordingControlling {
    var recordingEventHandler: ((WorkoutRecordingAttemptEvent) -> Void)?
    private(set) var activeAttempt: WorkoutRecordingAttempt?
    private(set) var stopCount = 0

    func prepare() async throws {}

    func startRecording(attempt: WorkoutRecordingAttempt) async throws {
        activeAttempt = attempt
        recordingEventHandler?(.started(attempt))
    }

    func stopRecording(attemptID _: UUID) async throws -> String? {
        stopCount += 1
        return nil
    }

    func cancelRecording(attemptID _: UUID?) async {
        activeAttempt = nil
    }

    func finishEarlyWithFailure() {
        guard let attempt = activeAttempt else { return }
        activeAttempt = nil
        recordingEventHandler?(.failed(
            attempt,
            WorkoutCameraError.recordingFailed("虚构系统提前停止")
        ))
    }

    func finishEarlySuccessfully(path: String) {
        guard let attempt = activeAttempt else { return }
        activeAttempt = nil
        recordingEventHandler?(.saved(attempt, path: path))
    }
}

@MainActor
private struct SilentCues: WorkoutCueProviding {
    func announce(_: String) {}
    func success() {}
}

@MainActor
private func expectAsyncError(
    _ operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected operation to throw", file: file, line: line)
    } catch {}
}

@MainActor
private final class CueSpy: WorkoutCueProviding {
    private(set) var messages: [String] = []

    func announce(_ text: String) {
        messages.append(text)
    }

    func success() {}
}

final class GuidedWorkoutCoordinatorTests: XCTestCase {
    private struct Fixture {
        var container: ModelContainer
        var context: ModelContext
        var defaults: UserDefaults
        var suiteName: String
        var session: WorkoutSession
        var performance: ExercisePerformance
        var sets: [WorkoutSet]
        var efforts: [WorkoutEffort]
        var now: Date
    }

    @MainActor
    func testSetCanCompleteDirectlyFromInProgress() async throws {
        let fixture = try makeFixture(firstSetIsWarmup: false, setCount: 1)
        defer {
            fixture.defaults.removePersistentDomain(
                forName: fixture.suiteName
            )
        }
        let recorder = RecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        XCTAssertEqual(fixture.sets[0].status, .completed)
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)
        XCTAssertEqual(recorder.stopCount, 1)
    }

    @MainActor
    func testDisabledAutomaticRecordingDoesNotPrepareCameraAndAllowsManualRecording() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let recorder = RecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )

        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        XCTAssertEqual(recorder.prepareCount, 0)
        XCTAssertTrue(recorder.startedSetIDs.isEmpty)

        try await coordinator.startManualRecording(in: fixture.context)
        // A real recording attempt owns camera activation end-to-end. The
        // coordinator must not await a second, unbounded prepare outside it.
        XCTAssertEqual(recorder.prepareCount, 0)
        XCTAssertEqual(recorder.startedSetIDs, [fixture.sets[0].id])

        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        XCTAssertEqual(fixture.sets[0].recordedVideoPath, recorder.path)
    }

    @MainActor
    func testManualRecordingToggleStopsAndPersistsWithoutCompletingSet() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let recorder = RecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        try await coordinator.toggleManualRecording(in: fixture.context)
        XCTAssertEqual(coordinator.recordingSetID, fixture.sets[0].id)

        try await coordinator.toggleManualRecording(in: fixture.context)

        XCTAssertNil(coordinator.recordingSetID)
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(fixture.sets[0].recordedVideoPath, recorder.path)
        XCTAssertEqual(fixture.sets[0].status, .inProgress)
    }

    @MainActor
    func testRepeatedRecordingFailureProducesDistinctFailureEvents() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let recorder = FailingRecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        try await coordinator.startManualRecording(in: fixture.context)
        let firstFailure = try XCTUnwrap(coordinator.recordingFailure)
        try await coordinator.startManualRecording(in: fixture.context)
        let secondFailure = try XCTUnwrap(coordinator.recordingFailure)

        XCTAssertEqual(recorder.startCount, 2)
        XCTAssertNotEqual(firstFailure.id, secondFailure.id)
        XCTAssertEqual(firstFailure.message, secondFailure.message)
        XCTAssertTrue(secondFailure.message.contains("虚构启动失败"))
    }

    @MainActor
    func testEarlyDelegateFailureClearsAttemptAndDoesNotFailAgainWhenSetCompletes() async throws {
        let fixture = try makeFixture(firstSetIsWarmup: false, setCount: 1)
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let recorder = EarlyTerminalRecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        XCTAssertEqual(coordinator.recordingSetID, fixture.sets[0].id)
        recorder.finishEarlyWithFailure()
        let failure = try XCTUnwrap(coordinator.recordingFailure)

        XCTAssertNil(coordinator.recordingSetID)
        XCTAssertTrue(failure.message.contains("虚构系统提前停止"))

        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        XCTAssertEqual(recorder.stopCount, 0)
        XCTAssertEqual(coordinator.recordingFailure?.id, failure.id)
        XCTAssertEqual(fixture.sets[0].status, .completed)
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)
    }

    @MainActor
    func testEarlySuccessfulFinishIsDurableAcrossCoordinatorRebuild() async throws {
        let fixture = try makeFixture(firstSetIsWarmup: false, setCount: 1)
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let recorder = EarlyTerminalRecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        recorder.finishEarlySuccessfully(path: "PrivateMedia/early.mov")
        XCTAssertEqual(
            fixture.efforts[0].recordedVideoPath,
            "PrivateMedia/early.mov"
        )
        XCTAssertEqual(
            fixture.sets[0].recordedVideoPath,
            "PrivateMedia/early.mov"
        )
        XCTAssertEqual(
            fixture.performance.activeVideoPath,
            "PrivateMedia/early.mov"
        )

        let rebuilt = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await rebuilt.activate(fixture.session, in: fixture.context)
        try await rebuilt.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        XCTAssertEqual(recorder.stopCount, 0)
        XCTAssertEqual(
            fixture.sets[0].recordedVideoPath,
            "PrivateMedia/early.mov"
        )
        XCTAssertNil(rebuilt.recordingFailure)
    }

    @MainActor
    func testSavedBindingFailureSurvivesNewCoordinatorAndContextRetry() async throws {
        let fixture = try makeFixture(firstSetIsWarmup: false, setCount: 1)
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let recorder = EarlyTerminalRecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now },
            recordingBindingDefaults: fixture.defaults,
            saveRecordingBinding: { _ in
                throw NSError(
                    domain: "SomaTests.RecordingBinding",
                    code: 1
                )
            }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        let path = "PrivateMedia/durable-binding.mov"
        recorder.finishEarlySuccessfully(path: path)

        let failure = try XCTUnwrap(coordinator.recordingFailure)
        XCTAssertTrue(failure.message.contains("视频已经保存"))
        XCTAssertFalse(failure.message.contains(path))
        let inbox = WorkoutRecordingBindingInbox(defaults: fixture.defaults)
        XCTAssertEqual(inbox.facts(for: fixture.session.id).count, 1)

        let freshContext = ModelContext(fixture.container)
        let sessionID = fixture.session.id
        let effortID = fixture.efforts[0].id
        let freshSession = try XCTUnwrap(
            try freshContext.fetch(FetchDescriptor<WorkoutSession>())
                .first(where: { $0.id == sessionID })
        )
        let effortBeforeReplay = try XCTUnwrap(
            try freshContext.fetch(FetchDescriptor<WorkoutEffort>())
                .first(where: { $0.id == effortID })
        )
        XCTAssertNil(effortBeforeReplay.recordedVideoPath)

        let rebuilt = GuidedWorkoutCoordinator(
            recorder: EarlyTerminalRecordingSpy(),
            cues: SilentCues(),
            now: { fixture.now },
            recordingBindingDefaults: fixture.defaults
        )
        await rebuilt.activate(freshSession, in: freshContext)

        let reboundEffort = try XCTUnwrap(
            try freshContext.fetch(FetchDescriptor<WorkoutEffort>())
                .first(where: { $0.id == effortID })
        )
        XCTAssertEqual(reboundEffort.recordedVideoPath, path)
        XCTAssertTrue(inbox.facts(for: sessionID).isEmpty)
        XCTAssertNil(rebuilt.recordingFailure)
    }

    @MainActor
    func testPendingRecordingBindingDoesNotConsumeMismatchedRelationshipChain() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let inbox = WorkoutRecordingBindingInbox(defaults: fixture.defaults)
        let unrelated = WorkoutRecordingBindingFact(
            sessionID: fixture.session.id,
            attempt: WorkoutRecordingAttempt(
                performanceID: UUID(),
                setID: UUID(),
                effortID: UUID()
            ),
            path: "PrivateMedia/wrong-space.mov"
        )
        inbox.upsert(unrelated)
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { fixture.now },
            recordingBindingDefaults: fixture.defaults
        )

        await coordinator.activate(fixture.session, in: fixture.context)

        XCTAssertEqual(
            inbox.facts(for: fixture.session.id),
            [unrelated]
        )
        XCTAssertNil(fixture.efforts[0].recordedVideoPath)
        XCTAssertNil(fixture.sets[0].recordedVideoPath)
        XCTAssertNil(fixture.performance.activeVideoPath)
    }

    @MainActor
    func testTerminalPerformanceCreatesWorkoutEntryBeforeSessionCompletion() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 3,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        try coordinator.finishRest(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: nil,
            actualWeightKG: nil,
            in: fixture.context
        )
        try coordinator.finishRest(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.skipCurrentSet(in: fixture.context)

        let workouts = try fixture.context.fetch(FetchDescriptor<WorkoutEntry>())
        let workout = try XCTUnwrap(workouts.first)
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workout.sourceWorkoutSessionID, fixture.session.id)
        XCTAssertEqual(workout.sourcePerformanceID, fixture.performance.id)
        XCTAssertEqual(workout.setEntries.count, 2)
        XCTAssertEqual(workout.setEntries.map(\.reps), [8, nil])
        XCTAssertEqual(workout.setEntries.map(\.externalWeightKG), [20, nil])
        XCTAssertEqual(GuidedWorkoutRecordStore.backfill(in: fixture.context), 0)
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<WorkoutEntry>()).count,
            1
        )
        try GuidedWorkoutRecordStore.delete(workout, in: fixture.context)
        XCTAssertTrue(fixture.performance.workoutProjectionSuppressed)
        XCTAssertEqual(GuidedWorkoutRecordStore.backfill(in: fixture.context), 0)
        XCTAssertTrue(
            try fixture.context.fetch(FetchDescriptor<WorkoutEntry>()).isEmpty
        )
        XCTAssertTrue(TrainingVolumeAnalytics.dailyPoints(
            from: [],
            sessions: [fixture.session],
            performances: [fixture.performance],
            sets: fixture.sets
        ).isEmpty)
        XCTAssertEqual(fixture.session.status, .active)
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)
    }

    @MainActor
    func testFullySkippedPerformanceDoesNotCreateEmptyWorkoutEntry() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 2,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)

        try await coordinator.skipCurrentExercise(in: fixture.context)

        XCTAssertTrue(
            try fixture.context.fetch(FetchDescriptor<WorkoutEntry>()).isEmpty
        )
        XCTAssertEqual(fixture.performance.status, .skipped)
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)
    }

    @MainActor
    func testEverySetPolicyRecordsAndPersistsEverySet() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 2,
            recordingPolicy: .everySet
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let recorder = RecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )

        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        try coordinator.finishRest(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        XCTAssertEqual(recorder.startedSetIDs, fixture.sets.map(\.id))
        XCTAssertEqual(recorder.stopCount, 2)
        XCTAssertTrue(fixture.sets.allSatisfy { $0.recordedVideoPath == recorder.path })
    }

    @MainActor
    func testCueSequenceCoversCountdownLaterSetsAndCompletion() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 2,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let cues = CueSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: cues,
            now: { fixture.now }
        )

        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        coordinator.announceCountdown(3)
        coordinator.announceCountdown(2)
        coordinator.announceCountdown(1)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        try coordinator.finishRest(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        XCTAssertEqual(cues.messages.prefix(5), [
            "接下来，测试深蹲，共 2 组，每组 8 次",
            "准备，开始第 1 组，20 kg · 8 次",
            "3",
            "2",
            "1"
        ])
        XCTAssertTrue(cues.messages.contains("开始第 2 组，20 kg · 8 次"))
        XCTAssertEqual(cues.messages.last, "训练完成，共完成 2 组")
    }

    @MainActor
    func testAutomaticRecordingStartsOnCountdownHostBeforeSetPhase() async throws {
        let fixture = try makeFixture(firstSetIsWarmup: false, setCount: 1)
        defer {
            fixture.defaults.removePersistentDomain(
                forName: fixture.suiteName
            )
        }
        let recorder = SuspendedRecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)

        let startTask = Task {
            try await coordinator.beginCurrentSet(in: fixture.context)
        }
        while !recorder.startInvoked {
            await Task.yield()
        }

        // PRD 034 / BUG 0025：自动录像必须在倒计时 PIP 宿主上完成 startRecording
        // 之后才切到 setInProgress，否则会拆宿主并改写 movieOutput。
        XCTAssertEqual(fixture.session.guidedPhase, .preSetCountdown)
        XCTAssertEqual(fixture.sets[0].status, .inProgress)

        recorder.resumeStart()
        try await startTask.value
        XCTAssertEqual(fixture.session.guidedPhase, .setInProgress)
    }

    @MainActor
    func testWarmupRecordsSecondSetAndPersistsConfirmation() async throws {
        let fixture = try makeFixture(firstSetIsWarmup: true, setCount: 2)
        defer {
            fixture.defaults.removePersistentDomain(
                forName: fixture.suiteName
            )
        }
        let recorder = RecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        XCTAssertTrue(recorder.startedPerformanceIDs.isEmpty)
        try coordinator.requestSetConfirmation(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        XCTAssertEqual(fixture.session.guidedPhase, .resting)

        try coordinator.finishRest(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        XCTAssertEqual(recorder.startedPerformanceIDs, [
            fixture.performance.id
        ])
        try coordinator.requestSetConfirmation(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(
            fixture.performance.activeVideoPath,
            "PrivateMedia/test-guided.mov"
        )
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)
        XCTAssertTrue(fixture.sets.allSatisfy { $0.status == .completed })
    }

    @MainActor
    func testInterruptedInProgressSetReturnsToConfirmationNotCompleted() async throws {
        let fixture = try makeFixture(firstSetIsWarmup: false, setCount: 1)
        defer {
            fixture.defaults.removePersistentDomain(
                forName: fixture.suiteName
            )
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues()
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        let rebuilt = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues()
        )
        await rebuilt.activate(fixture.session, in: fixture.context)

        XCTAssertEqual(fixture.session.guidedPhase, .setConfirmation)
        XCTAssertEqual(fixture.sets[0].status, .inProgress)
        XCTAssertNil(fixture.sets[0].completedAt)
    }

    @MainActor
    func testRestRemainingUsesPersistedStartTime() async throws {
        var time = Date(timeIntervalSince1970: 2_000_000_000)
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 2,
            now: time
        )
        defer {
            fixture.defaults.removePersistentDomain(
                forName: fixture.suiteName
            )
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { time }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try coordinator.requestSetConfirmation(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        time = time.addingTimeInterval(35)

        XCTAssertEqual(
            coordinator.remainingRestSeconds(
                for: fixture.session,
                in: fixture.context
            ),
            55
        )
        try coordinator.finishRest(in: fixture.context)
        XCTAssertEqual(fixture.sets[0].actualRestSeconds, 35)
    }

    @MainActor
    func testRestAdjustmentPersistsTargetEndTime() async throws {
        let time = Date(timeIntervalSince1970: 2_000_000_000)
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 2,
            now: time
        )
        defer {
            fixture.defaults.removePersistentDomain(
                forName: fixture.suiteName
            )
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { time }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        try coordinator.adjustRest(by: -15, in: fixture.context)
        XCTAssertEqual(
            fixture.session.restTargetEndAt,
            time.addingTimeInterval(75)
        )
        XCTAssertEqual(
            coordinator.remainingRestSeconds(
                for: fixture.session,
                in: fixture.context
            ),
            75
        )
    }

    @MainActor
    func testRedoResetsInterruptedSetWithoutCompletingIt() async throws {
        let fixture = try makeFixture(firstSetIsWarmup: false, setCount: 1)
        defer {
            fixture.defaults.removePersistentDomain(
                forName: fixture.suiteName
            )
        }
        let recorder = RecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues()
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        try await coordinator.redoCurrentSet(in: fixture.context)

        XCTAssertEqual(fixture.sets[0].status, .pending)
        XCTAssertNil(fixture.sets[0].startedAt)
        XCTAssertEqual(fixture.session.guidedPhase, .preSetCountdown)
        XCTAssertEqual(recorder.cancelCount, 1)
    }

    @MainActor
    func testPauseAndCancelRecordingDoNotLoseSetFacts() async throws {
        let fixture = try makeFixture(firstSetIsWarmup: false, setCount: 1)
        defer {
            fixture.defaults.removePersistentDomain(
                forName: fixture.suiteName
            )
        }
        let recorder = RecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues()
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.pause(in: fixture.context)

        XCTAssertEqual(fixture.session.status, .paused)
        XCTAssertEqual(fixture.sets[0].status, .inProgress)
        XCTAssertEqual(recorder.cancelCount, 1)
    }
}

extension GuidedWorkoutCoordinatorTests {
    @MainActor
    func testBothLateralityAdvancesLeftThenSideRestThenRightAndSetRest() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 2,
            recordingPolicy: .disabled,
            laterality: .both,
            restBetweenSidesSeconds: 20,
            restAfterSetSeconds: 90
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { fixture.now }
        )

        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        XCTAssertEqual(fixture.efforts[0].side, .left)

        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        XCTAssertEqual(fixture.session.guidedPhase, .resting)
        XCTAssertEqual(fixture.session.currentEffortID, fixture.efforts[1].id)
        XCTAssertEqual(
            fixture.session.phaseDeadlineAt,
            fixture.now.addingTimeInterval(20)
        )
        XCTAssertEqual(
            GuidedWorkoutProgressExercise.completionFraction(
                set: fixture.sets[0],
                efforts: Array(fixture.efforts.prefix(2))
            ),
            0.5
        )

        try coordinator.finishRest(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        XCTAssertEqual(fixture.efforts[1].side, .right)
        try await coordinator.confirmCurrentSet(
            actualReps: 7,
            actualWeightKG: 22,
            in: fixture.context
        )

        XCTAssertEqual(fixture.sets[0].status, .completed)
        XCTAssertEqual(fixture.sets[0].actualReps, 15)
        XCTAssertNil(fixture.sets[0].actualWeightKG)
        XCTAssertEqual(fixture.session.guidedPhase, .resting)
        XCTAssertEqual(fixture.session.currentEffortID, fixture.efforts[2].id)
        XCTAssertEqual(
            fixture.session.phaseDeadlineAt,
            fixture.now.addingTimeInterval(90)
        )
    }

    @MainActor
    func testSkippingOneSidePreservesCompletedSideEvidence() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled,
            laterality: .both,
            restBetweenSidesSeconds: 0
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.skipCurrentSet(in: fixture.context)

        XCTAssertEqual(fixture.efforts[0].status, .completed)
        XCTAssertEqual(fixture.efforts[0].actualReps, 8)
        XCTAssertEqual(fixture.efforts[1].status, .skipped)
        XCTAssertEqual(fixture.sets[0].status, .partial)
        XCTAssertEqual(fixture.sets[0].actualReps, 8)
        XCTAssertEqual(
            GuidedWorkoutProgressExercise.completionFraction(
                set: fixture.sets[0],
                efforts: fixture.efforts
            ),
            0.5
        )
        let summary = TrainingPlanStore.summary(
            for: fixture.session.id,
            in: fixture.context
        )
        XCTAssertEqual(summary.completedSets, 0)
        XCTAssertEqual(summary.partialSets, 1)
        XCTAssertEqual(summary.exerciseCount, 1)
        let share = WorkoutSharePosterBuilder.makeModel(
            session: fixture.session,
            in: fixture.context
        )
        XCTAssertEqual(share.completedSets, 0)
        XCTAssertEqual(share.partialSets, 1)
        XCTAssertEqual(share.exercises.first?.partialSetCount, 1)
        XCTAssertEqual(
            GuidedWorkoutCoordinator.terminalSetStatus(
                for: [.completed, .failed]
            ),
            .partial
        )
        XCTAssertEqual(
            GuidedWorkoutCoordinator.terminalSetStatus(
                for: [.failed, .skipped]
            ),
            .failed
        )
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)
    }

    @MainActor
    func testRepetitionEffortPersistsActualElapsedDuration() async throws {
        var time = Date(timeIntervalSince1970: 2_000_000_000)
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled,
            now: time
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { time }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        time = time.addingTimeInterval(12)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        XCTAssertEqual(fixture.efforts[0].actualDurationSeconds, 12)
        XCTAssertEqual(fixture.sets[0].actualDurationSeconds, 12)
    }

    @MainActor
    func testDurationDeadlineCompletesExactlyOnce() async throws {
        var time = Date(timeIntervalSince1970: 2_000_000_000)
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled,
            targetKind: .duration,
            targetDurationSeconds: 30,
            now: time
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { time }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        let revision = fixture.session.transitionRevision

        time = time.addingTimeInterval(30)
        try await coordinator.advanceTimelineIfDue(
            expectedRevision: revision,
            in: fixture.context
        )
        try await coordinator.advanceTimelineIfDue(
            expectedRevision: revision,
            in: fixture.context
        )

        XCTAssertEqual(fixture.efforts[0].status, .completed)
        XCTAssertEqual(fixture.efforts[0].actualDurationSeconds, 30)
        XCTAssertEqual(fixture.sets[0].actualDurationSeconds, 30)
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)
    }

    @MainActor
    func testDurationMaterializationFailureRollsBackAndCanRetryCompletion() async throws {
        var time = Date(timeIntervalSince1970: 2_000_000_000)
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled,
            targetKind: .duration,
            targetDurationSeconds: 30,
            now: time
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let recorder = RecordingSpy()
        var shouldFailMaterialization = true
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { time },
            materializePerformance: { performance, session, context in
                if shouldFailMaterialization {
                    shouldFailMaterialization = false
                    throw TrainingPlanError.missingExercise(
                        performance.exerciseID
                    )
                }
                return try GuidedWorkoutRecordStore.materialize(
                    performance: performance,
                    session: session,
                    in: context
                )
            }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.startManualRecording(in: fixture.context)

        let revision = fixture.session.transitionRevision
        time = time.addingTimeInterval(30)

        await expectAsyncError {
            try await coordinator.advanceTimelineIfDue(
                expectedRevision: revision,
                in: fixture.context
            )
        }
        let rolledBackEffort = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<WorkoutEffort>())
                .first { $0.id == fixture.efforts[0].id }
        )
        let rolledBackSet = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<WorkoutSet>())
                .first { $0.id == fixture.sets[0].id }
        )
        let rolledBackPerformance = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<ExercisePerformance>())
                .first { $0.id == fixture.performance.id }
        )
        XCTAssertEqual(rolledBackEffort.status, .inProgress)
        XCTAssertEqual(rolledBackSet.status, .inProgress)
        XCTAssertEqual(rolledBackPerformance.status, .active)
        XCTAssertEqual(fixture.session.guidedPhase, .setInProgress)
        XCTAssertEqual(
            rolledBackEffort.recordedVideoPath,
            recorder.path
        )

        try await coordinator.completeCurrentEffort(
            actualReps: nil,
            actualDurationSeconds: 30,
            actualWeightKG: 20,
            in: fixture.context
        )

        XCTAssertEqual(fixture.efforts[0].status, .completed)
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)
    }

    @MainActor
    func testConcurrentDoubleCompletionStopsAndAdvancesOnlyOnce() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let recorder = SuspendedStopRecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.startManualRecording(in: fixture.context)
        let revision = fixture.session.transitionRevision

        let firstCompletion = Task { @MainActor in
            try await coordinator.completeCurrentEffort(
                actualReps: 8,
                actualDurationSeconds: nil,
                actualWeightKG: 20,
                in: fixture.context
            )
        }
        while !recorder.isStopSuspended {
            await Task.yield()
        }

        XCTAssertTrue(coordinator.isCompletingCurrentEffort)
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(fixture.efforts[0].status, .inProgress)
        XCTAssertEqual(fixture.session.transitionRevision, revision)

        try await coordinator.completeCurrentEffort(
            actualReps: 8,
            actualDurationSeconds: nil,
            actualWeightKG: 20,
            in: fixture.context
        )
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(fixture.efforts[0].status, .inProgress)

        recorder.resumeStop()
        try await firstCompletion.value

        XCTAssertFalse(coordinator.isCompletingCurrentEffort)
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(fixture.efforts[0].status, .completed)
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)
    }

    @MainActor
    func testRepetitionMaterializationFailureRollsBackAndCanRetryCompletion() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        var shouldFailMaterialization = true
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { fixture.now },
            materializePerformance: { performance, session, context in
                if shouldFailMaterialization {
                    shouldFailMaterialization = false
                    throw TrainingPlanError.missingExercise(
                        performance.exerciseID
                    )
                }
                return try GuidedWorkoutRecordStore.materialize(
                    performance: performance,
                    session: session,
                    in: context
                )
            }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        await expectAsyncError {
            try await coordinator.confirmCurrentSet(
                actualReps: 8,
                actualWeightKG: 20,
                in: fixture.context
            )
        }
        let rolledBackEffort = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<WorkoutEffort>())
                .first { $0.id == fixture.efforts[0].id }
        )
        XCTAssertEqual(rolledBackEffort.status, .inProgress)
        XCTAssertEqual(fixture.session.guidedPhase, .setInProgress)

        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)
    }

    @MainActor
    func testSkipRollsBackWhenMaterializationFailsAndCanRetry() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        var shouldFailMaterialization = true
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { fixture.now },
            materializePerformance: { performance, session, context in
                if shouldFailMaterialization {
                    shouldFailMaterialization = false
                    throw TrainingPlanError.missingExercise(
                        performance.exerciseID
                    )
                }
                return try GuidedWorkoutRecordStore.materialize(
                    performance: performance,
                    session: session,
                    in: context
                )
            }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        await expectAsyncError {
            try await coordinator.skipCurrentSet(in: fixture.context)
        }
        let rolledBackEffort = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<WorkoutEffort>())
                .first { $0.id == fixture.efforts[0].id }
        )
        let rolledBackSet = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<WorkoutSet>())
                .first { $0.id == fixture.sets[0].id }
        )
        XCTAssertEqual(rolledBackEffort.status, .inProgress)
        XCTAssertEqual(rolledBackSet.status, .inProgress)
        XCTAssertEqual(fixture.session.guidedPhase, .setInProgress)

        try await coordinator.skipCurrentSet(in: fixture.context)

        XCTAssertEqual(fixture.efforts[0].status, .skipped)
        XCTAssertEqual(fixture.sets[0].status, .skipped)
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)
    }

    @MainActor
    func testZeroRestMovesDirectlyIntoThreeSecondCountdown() async throws {
        var time = Date(timeIntervalSince1970: 2_000_000_000)
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 2,
            recordingPolicy: .disabled,
            restAfterSetSeconds: 0,
            now: time
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { time }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        XCTAssertEqual(fixture.session.guidedPhase, .preSetCountdown)
        XCTAssertEqual(
            fixture.session.phaseDeadlineAt,
            time.addingTimeInterval(3)
        )
        let revision = fixture.session.transitionRevision
        time = time.addingTimeInterval(3)
        try await coordinator.advanceTimelineIfDue(
            expectedRevision: revision,
            in: fixture.context
        )
        XCTAssertEqual(fixture.session.guidedPhase, .setInProgress)
        XCTAssertEqual(fixture.session.currentSetID, fixture.sets[1].id)
    }

    @MainActor
    func testPauseFreezesAndResumeShiftsDurationDeadline() async throws {
        var time = Date(timeIntervalSince1970: 2_000_000_000)
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled,
            targetKind: .duration,
            targetDurationSeconds: 30,
            now: time
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { time }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        let originalDeadline = try XCTUnwrap(fixture.session.phaseDeadlineAt)

        time = time.addingTimeInterval(10)
        try await coordinator.pause(in: fixture.context)
        time = time.addingTimeInterval(20)
        try coordinator.resume(in: fixture.context)

        XCTAssertEqual(
            fixture.session.phaseDeadlineAt,
            originalDeadline.addingTimeInterval(20)
        )
        XCTAssertEqual(
            coordinator.remainingEffortSeconds(
                for: fixture.session,
                in: fixture.context
            ),
            20
        )
        XCTAssertEqual(fixture.efforts[0].status, .inProgress)
    }

    @MainActor
    func testFirstWorkingSetRecordsBothEffortsIndependently() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 2,
            laterality: .both,
            restBetweenSidesSeconds: 0,
            restAfterSetSeconds: 0
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let recorder = RecordingSpy()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        try await coordinator.beginCurrentSet(in: fixture.context)

        XCTAssertEqual(
            recorder.startedEffortIDs,
            Array(fixture.efforts.prefix(2)).map(\.id)
        )
        XCTAssertEqual(recorder.stopCount, 2)
        XCTAssertNotNil(fixture.efforts[0].recordedVideoPath)
        XCTAssertNotNil(fixture.efforts[1].recordedVideoPath)
    }

    @MainActor
    func testRecordingPauseSurvivesRebuildAndClearsOnlyAfterManualSave() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 3,
            recordingPolicy: .everySet,
            restAfterSetSeconds: 0
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let recorder = SequencedRecordingSpy(failingStartNumbers: [1, 2])
        let firstCoordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await firstCoordinator.activate(fixture.session, in: fixture.context)
        try firstCoordinator.introduceCurrentExercise(in: fixture.context)
        try firstCoordinator.prepareCurrentSet(in: fixture.context)
        try await firstCoordinator.beginCurrentSet(in: fixture.context)
        XCTAssertTrue(firstCoordinator.automaticRecordingPaused)
        XCTAssertTrue(fixture.session.automaticRecordingPaused)

        try await firstCoordinator.startManualRecording(in: fixture.context)
        XCTAssertTrue(firstCoordinator.automaticRecordingPaused)
        XCTAssertEqual(recorder.attempts.count, 2)
        try await firstCoordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        let rebuilt = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await rebuilt.activate(fixture.session, in: fixture.context)
        XCTAssertTrue(rebuilt.automaticRecordingPaused)
        XCTAssertTrue(rebuilt.recordingStatusMessage?.contains("手动重试") == true)
        try await rebuilt.beginCurrentSet(in: fixture.context)
        XCTAssertEqual(recorder.attempts.count, 2)

        try await rebuilt.startManualRecording(in: fixture.context)
        XCTAssertTrue(rebuilt.automaticRecordingPaused)
        try await rebuilt.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        XCTAssertFalse(rebuilt.automaticRecordingPaused)
        XCTAssertFalse(fixture.session.automaticRecordingPaused)
        XCTAssertNil(rebuilt.recordingFailure)

        let resumed = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await resumed.activate(fixture.session, in: fixture.context)
        XCTAssertFalse(resumed.automaticRecordingPaused)
        try await resumed.beginCurrentSet(in: fixture.context)

        XCTAssertEqual(recorder.attempts.count, 4)
        XCTAssertEqual(recorder.attempts[3].effortID, fixture.efforts[2].id)
    }

    @MainActor
    func testManualRecordingCanBeQueuedBeforeEffortStarts() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let recorder = RecordingSpy()
        let firstCoordinator = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await firstCoordinator.activate(fixture.session, in: fixture.context)
        try firstCoordinator.introduceCurrentExercise(in: fixture.context)
        try await firstCoordinator.toggleManualRecording(in: fixture.context)
        XCTAssertTrue(firstCoordinator.manualRecordingQueued)
        XCTAssertEqual(recorder.prepareCount, 1)
        XCTAssertTrue(firstCoordinator.recordingStatusMessage?.contains("已就绪") == true)
        XCTAssertEqual(
            fixture.session.queuedRecordingEffortID,
            fixture.efforts[0].id
        )

        let rebuilt = GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: SilentCues(),
            now: { fixture.now }
        )
        await rebuilt.activate(fixture.session, in: fixture.context)
        XCTAssertTrue(rebuilt.manualRecordingQueued)
        try rebuilt.prepareCurrentSet(in: fixture.context)
        try await rebuilt.beginCurrentSet(in: fixture.context)

        XCTAssertFalse(rebuilt.manualRecordingQueued)
        XCTAssertNil(fixture.session.queuedRecordingEffortID)
        XCTAssertEqual(recorder.startedEffortIDs, [fixture.efforts[0].id])
    }

    @MainActor
    func testFinalizeRejectsNonterminalFacts() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        fixture.session.guidedPhase = .sessionReview
        try fixture.context.save()
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues()
        )
        await coordinator.activate(fixture.session, in: fixture.context)

        XCTAssertThrowsError(try coordinator.complete(in: fixture.context)) {
            XCTAssertEqual(
                $0 as? GuidedWorkoutError,
                .sessionNotReadyForCompletion
            )
        }
        XCTAssertEqual(fixture.session.status, .active)
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)
    }

    @MainActor
    func testFinalizeMaterializesActionRecordBeforeCompletingSession() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        try coordinator.complete(in: fixture.context)

        XCTAssertEqual(fixture.session.status, .completed)
        XCTAssertEqual(fixture.session.guidedPhase, .completed)
        let entries = try fixture.context.fetch(FetchDescriptor<WorkoutEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].sourcePerformanceID, fixture.performance.id)
    }

    @MainActor
    func testFinalizeCanRetryAfterMaterializationThrows() async throws {
        let fixture = try makeFixture(
            firstSetIsWarmup: false,
            setCount: 1,
            recordingPolicy: .disabled
        )
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
        }
        let coordinator = GuidedWorkoutCoordinator(
            recorder: RecordingSpy(),
            cues: SilentCues(),
            now: { fixture.now }
        )
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )

        let definitionID = fixture.performance.exerciseID
        fixture.performance.exerciseID = UUID()
        fixture.performance.exerciseDefinition = nil
        try fixture.context.save()

        XCTAssertThrowsError(try coordinator.complete(in: fixture.context))
        XCTAssertEqual(fixture.session.status, .active)
        XCTAssertEqual(fixture.session.guidedPhase, .sessionReview)

        fixture.performance.exerciseID = definitionID
        try fixture.context.save()
        try coordinator.complete(in: fixture.context)

        XCTAssertEqual(fixture.session.status, .completed)
        XCTAssertEqual(fixture.session.guidedPhase, .completed)
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<WorkoutEntry>()).count,
            1
        )
    }

    @MainActor
    private func makeFixture(
        firstSetIsWarmup: Bool,
        setCount: Int,
        recordingPolicy: AutoRecordingPolicy = .enabled,
        laterality: ExerciseLaterality = .none,
        targetKind: WorkoutTargetKind = .repetitions,
        targetDurationSeconds: Int? = nil,
        restBetweenSidesSeconds: Int? = nil,
        restAfterSetSeconds: Int = 90,
        now: Date = Date(timeIntervalSince1970: 2_000_000_000)
    ) throws -> Fixture {
        let suiteName = "GuidedWorkoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let container = try XCTUnwrap(spaces.personalContainer)
        let context = ModelContext(container)
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "测试深蹲",
            in: context
        )
        let plannedSets = (1 ... setCount).map { order in
            TemplateSetPrescriptionValue(
                order: order,
                kind: firstSetIsWarmup && order == 1 ? .warmup : .working,
                targetKind: targetKind,
                targetReps: targetKind == .repetitions ? 8 : nil,
                targetDurationSeconds: targetKind == .duration
                    ? targetDurationSeconds
                    : nil,
                targetWeightKG: 20,
                restBetweenSidesSeconds: restBetweenSidesSeconds,
                restAfterSetSeconds: restAfterSetSeconds
            )
        }
        let prescription = TemplateExercisePrescription(
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            targetSets: setCount,
            targetReps: 8,
            targetWeightKG: 20,
            targetRestSeconds: 90,
            firstSetIsWarmup: firstSetIsWarmup,
            laterality: laterality,
            plannedSets: plannedSets
        )
        let session = WorkoutSession(
            startedAt: now,
            prescriptionSnapshot: [prescription],
            status: .active,
            autoRecordingPolicy: recordingPolicy
        )
        let performance = ExercisePerformance(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            prescriptionSnapshot: prescription
        )
        let sets = (1 ... setCount).map { order in
            WorkoutSet(
                performanceID: performance.id,
                order: order,
                kind: firstSetIsWarmup && order == 1 ? .warmup : .working,
                laterality: laterality.rawValue,
                plannedTargetKind: targetKind,
                plannedReps: targetKind == .repetitions ? 8 : nil,
                plannedDurationSeconds: targetKind == .duration
                    ? targetDurationSeconds
                    : nil,
                plannedWeightKG: 20,
                plannedRestSeconds: restAfterSetSeconds,
                restBetweenSidesSeconds: restBetweenSidesSeconds
            )
        }
        let sides: [WorkoutEffortSide] = switch laterality {
        case .none: [.none]
        case .both: [.left, .right]
        case .left: [.left]
        case .right: [.right]
        }
        let efforts = sets.flatMap { set in
            sides.enumerated().map { index, side in
                WorkoutEffort(
                    workoutSetID: set.id,
                    order: index + 1,
                    side: side,
                    targetKind: targetKind,
                    plannedReps: targetKind == .repetitions ? 8 : nil,
                    plannedDurationSeconds: targetKind == .duration
                        ? targetDurationSeconds
                        : nil,
                    plannedWeightKG: 20
                )
            }
        }
        session.currentPerformanceID = performance.id
        session.currentSetID = sets.first?.id
        session.currentEffortID = efforts.first?.id
        performance.session = session
        for set in sets {
            set.performance = performance
        }
        for effort in efforts {
            effort.workoutSet = sets.first { $0.id == effort.workoutSetID }
        }
        context.insert(session)
        context.insert(performance)
        sets.forEach(context.insert)
        efforts.forEach(context.insert)
        try context.save()
        return Fixture(
            container: container,
            context: context,
            defaults: defaults,
            suiteName: suiteName,
            session: session,
            performance: performance,
            sets: sets,
            efforts: efforts,
            now: now
        )
    }
}
