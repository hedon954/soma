@testable import Soma
import SwiftData
import XCTest

@MainActor
private final class RecordingSpy: WorkoutRecordingControlling {
    var startedPerformanceIDs: [UUID] = []
    var startedSetIDs: [UUID] = []
    var prepareCount = 0
    var stopCount = 0
    var cancelCount = 0
    var path: String? = "PrivateMedia/test-guided.mov"

    func prepare() async throws {
        prepareCount += 1
    }

    func startRecording(performanceID: UUID, setID: UUID) async throws {
        startedPerformanceIDs.append(performanceID)
        startedSetIDs.append(setID)
    }

    func stopRecording() async throws -> String? {
        stopCount += 1
        return path
    }

    func cancelRecording() async {
        cancelCount += 1
    }
}

@MainActor
private final class SuspendedRecordingSpy: WorkoutRecordingControlling {
    private(set) var startInvoked = false
    private var continuation: CheckedContinuation<Void, Never>?

    func prepare() async throws {}

    func startRecording(performanceID _: UUID, setID _: UUID) async throws {
        startInvoked = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func stopRecording() async throws -> String? {
        nil
    }

    func cancelRecording() async {}

    func resumeStart() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private struct SilentCues: WorkoutCueProviding {
    func announce(_: String) {}
    func success() {}
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
        var context: ModelContext
        var defaults: UserDefaults
        var suiteName: String
        var session: WorkoutSession
        var performance: ExercisePerformance
        var sets: [WorkoutSet]
        var now: Date
    }

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

    func testFullCaptureOnlyStaysVisibleWhileActuallyRecording() {
        var state = GuidedWorkoutPresentationState()

        state.expand()
        state.cameraStateChanged(.previewing)
        XCTAssertEqual(state.mode, .compact)

        state.collapse()
        state.cameraStateChanged(.recording)
        XCTAssertEqual(state.mode, .expandedCapture)

        state.phaseChanged(.resting)
        XCTAssertEqual(state.mode, .compact)
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
        XCTAssertEqual(recorder.prepareCount, 1)
        XCTAssertEqual(recorder.startedSetIDs, [fixture.sets[0].id])

        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        XCTAssertEqual(fixture.sets[0].recordedVideoPath, recorder.path)
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

        XCTAssertEqual(cues.messages, [
            "接下来，测试深蹲",
            "准备第 1 组",
            "3",
            "2",
            "1",
            "开始第 1 组",
            "第 1 组完成，休息 90 秒",
            "准备第 2 组",
            "开始第 2 组",
            "训练完成，共完成 2 组"
        ])
    }

    @MainActor
    func testSetBecomesVisibleBeforeCameraStartupCompletes() async throws {
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

        XCTAssertEqual(fixture.session.guidedPhase, .setInProgress)
        XCTAssertEqual(fixture.sets[0].status, .inProgress)

        recorder.resumeStart()
        try await startTask.value
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
        XCTAssertEqual(fixture.sets[1].actualRestSeconds, 35)
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

    @MainActor
    private func makeFixture(
        firstSetIsWarmup: Bool,
        setCount: Int,
        recordingPolicy: AutoRecordingPolicy = .enabled,
        now: Date = Date(timeIntervalSince1970: 2_000_000_000)
    ) throws -> Fixture {
        let suiteName = "GuidedWorkoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(spaces.personalContainer)
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "测试深蹲",
            in: context
        )
        let prescription = TemplateExercisePrescription(
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            targetSets: setCount,
            targetReps: 8,
            targetWeightKG: 20,
            targetRestSeconds: 90,
            firstSetIsWarmup: firstSetIsWarmup
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
                plannedReps: 8,
                plannedWeightKG: 20,
                plannedRestSeconds: 90
            )
        }
        session.currentPerformanceID = performance.id
        context.insert(session)
        context.insert(performance)
        sets.forEach(context.insert)
        try context.save()
        return Fixture(
            context: context,
            defaults: defaults,
            suiteName: suiteName,
            session: session,
            performance: performance,
            sets: sets,
            now: now
        )
    }
}
