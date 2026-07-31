@testable import Soma
import SwiftData
import XCTest

@MainActor
private final class RecordingSpy: WorkoutRecordingControlling {
    var startedPerformanceIDs: [UUID] = []
    var stopCount = 0
    var cancelCount = 0
    var path: String? = "PrivateMedia/test-guided.mov"

    func prepare() async throws {}

    func startRecording(performanceID: UUID) async throws {
        startedPerformanceIDs.append(performanceID)
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
private struct SilentCues: WorkoutCueProviding {
    func announce(_: String) {}
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
            autoRecordingPolicy: .enabled
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
