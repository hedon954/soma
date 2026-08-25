@testable import Soma
import SwiftData
import XCTest

@MainActor
private final class RecordingRecoverySpy: WorkoutRecordingControlling {
    enum PreparationBehavior {
        case succeed
        case fail(WorkoutCameraError)
        case suspend
    }

    var recordingEventHandler: ((WorkoutRecordingAttemptEvent) -> Void)?
    var preparationBehavior: PreparationBehavior
    private(set) var prepareCount = 0
    private(set) var cancelCount = 0
    private(set) var idlePreviewCount = 0
    private(set) var attempts: [WorkoutRecordingAttempt] = []
    private var activeAttempt: WorkoutRecordingAttempt?
    private var preparationContinuation: CheckedContinuation<Void, Never>?

    init(preparationBehavior: PreparationBehavior = .succeed) {
        self.preparationBehavior = preparationBehavior
    }

    func prepare() async throws {
        prepareCount += 1
        switch preparationBehavior {
        case .succeed:
            return
        case let .fail(error):
            throw error
        case .suspend:
            await withCheckedContinuation { continuation in
                preparationContinuation = continuation
            }
        }
    }

    func startRecording(attempt: WorkoutRecordingAttempt) async throws {
        attempts.append(attempt)
        activeAttempt = attempt
        recordingEventHandler?(.started(attempt))
    }

    func stopRecording(attemptID: UUID) async throws -> String? {
        guard let attempt = activeAttempt, attempt.id == attemptID else {
            return nil
        }
        activeAttempt = nil
        let path = "PrivateMedia/complete-\(attempt.id.uuidString).mov"
        recordingEventHandler?(.saved(attempt, path: path))
        return path
    }

    func cancelRecording(attemptID _: UUID?) async {
        cancelCount += 1
        activeAttempt = nil
    }

    func idlePreviewKeepingSessionOwner() async {
        idlePreviewCount += 1
    }

    func resumePreparation() {
        preparationContinuation?.resume()
        preparationContinuation = nil
    }

    func finishWithFailure(_ message: String = "虚构系统提前停止") {
        guard let attempt = activeAttempt else { return }
        activeAttempt = nil
        recordingEventHandler?(.failed(
            attempt,
            WorkoutCameraError.recordingFailed(message)
        ))
    }

    func finishWithPartial(path: String, message: String) {
        guard let attempt = activeAttempt else { return }
        activeAttempt = nil
        recordingEventHandler?(.savedPartial(
            attempt,
            path: path,
            message: message
        ))
    }
}

@MainActor
final class SuspendedStopRecordingSpy: WorkoutRecordingControlling {
    var recordingEventHandler: ((WorkoutRecordingAttemptEvent) -> Void)?
    private(set) var stopCount = 0
    private(set) var isStopSuspended = false
    private var activeAttempt: WorkoutRecordingAttempt?
    private var stopContinuation: CheckedContinuation<Void, Error>?

    func prepare() async throws {}

    func startRecording(attempt: WorkoutRecordingAttempt) async throws {
        activeAttempt = attempt
        recordingEventHandler?(.started(attempt))
    }

    func stopRecording(attemptID: UUID) async throws -> String? {
        stopCount += 1
        isStopSuspended = true
        try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
        }
        isStopSuspended = false
        let path = "PrivateMedia/suspended-stop.mov"
        if let attempt = activeAttempt, attempt.id == attemptID {
            activeAttempt = nil
            recordingEventHandler?(.saved(attempt, path: path))
        }
        return path
    }

    func cancelRecording(attemptID _: UUID?) async {}

    func resumeStop() {
        stopContinuation?.resume()
        stopContinuation = nil
    }
}

@MainActor
private final class SuspendedSessionEndRecordingSpy:
    WorkoutRecordingControlling
{
    var recordingEventHandler: ((WorkoutRecordingAttemptEvent) -> Void)?
    private var ownership = WorkoutCameraSessionOwnership()
    private var endContinuation: CheckedContinuation<Void, Never>?
    private(set) var prepareCount = 0
    private(set) var isEndSuspended = false
    private(set) var activeAttempt: WorkoutRecordingAttempt?

    var activeOwner: WorkoutCameraSessionOwnerToken? {
        ownership.activeOwner
    }

    func claimWorkoutSession(
        sessionID: UUID
    ) -> WorkoutCameraSessionOwnerToken {
        activeAttempt = nil
        return ownership.claim(sessionID: sessionID)
    }

    func endWorkoutSession(owner: WorkoutCameraSessionOwnerToken) async {
        guard ownership.accepts(owner) else { return }
        isEndSuspended = true
        await withCheckedContinuation { continuation in
            endContinuation = continuation
        }
        isEndSuspended = false
        guard ownership.release(owner) else { return }
        activeAttempt = nil
    }

    func prepare() async throws {
        prepareCount += 1
    }

    func startRecording(attempt: WorkoutRecordingAttempt) async throws {
        activeAttempt = attempt
        recordingEventHandler?(.started(attempt))
    }

    func stopRecording(attemptID _: UUID) async throws -> String? {
        nil
    }

    func cancelRecording(attemptID _: UUID?) async {
        activeAttempt = nil
    }

    func resumeEnd() {
        endContinuation?.resume()
        endContinuation = nil
    }
}

@MainActor
private struct RecordingRecoveryCues: WorkoutCueProviding {
    func announce(_: String) {}
    func success() {}
}

final class GuidedWorkoutRecordingRecoveryTests: XCTestCase {
    private struct Fixture {
        let context: ModelContext
        let defaults: UserDefaults
        let suiteName: String
        let session: WorkoutSession
        let performances: [ExercisePerformance]
        let sets: [WorkoutSet]
        let efforts: [WorkoutEffort]
        let now: Date
    }

    @MainActor
    func testEverySetPreflightsAgainForNextEffort() async throws {
        let fixture = try makeFixture(setCount: 2, policy: .everySet)
        defer { clearDefaults(fixture) }
        let recorder = RecordingRecoverySpy()
        let coordinator = makeCoordinator(recorder, fixture: fixture)

        await coordinator.activate(fixture.session, in: fixture.context)
        XCTAssertEqual(recorder.prepareCount, 1)
        XCTAssertTrue(recorder.attempts.isEmpty)

        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        try coordinator.finishRest(in: fixture.context)
        await coordinator.preflightAutomaticRecording(in: fixture.context)

        XCTAssertEqual(recorder.prepareCount, 2)
        XCTAssertEqual(fixture.session.currentEffortID, fixture.efforts[1].id)
    }

    @MainActor
    func testEnabledPolicyDoesNotRecordLaterSetsAndReleasesPreview() async throws {
        let fixture = try makeFixture(
            performanceCount: 1,
            setCount: 2,
            policy: .enabled,
            restSeconds: 0
        )
        defer { clearDefaults(fixture) }
        let recorder = RecordingRecoverySpy()
        let coordinator = makeCoordinator(recorder, fixture: fixture)

        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        XCTAssertTrue(coordinator.shouldCaptureCurrentEffort(in: fixture.context))
        try await coordinator.beginCurrentSet(in: fixture.context)
        XCTAssertEqual(recorder.attempts.map(\.setID), [fixture.sets[0].id])

        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        try await coordinator.beginCurrentSet(in: fixture.context)

        XCTAssertEqual(recorder.attempts.map(\.setID), [fixture.sets[0].id])
        XCTAssertGreaterThanOrEqual(recorder.idlePreviewCount, 1)
        XCTAssertFalse(coordinator.shouldCaptureCurrentEffort(in: fixture.context))
    }

    @MainActor
    func testEndEarlyAbandonsSessionWithoutRequiringRemainingSets() async throws {
        let fixture = try makeFixture(
            performanceCount: 1,
            setCount: 2,
            policy: .disabled,
            restSeconds: 0
        )
        defer { clearDefaults(fixture) }
        let coordinator = makeCoordinator(
            RecordingRecoverySpy(),
            fixture: fixture
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
        try await coordinator.endEarly(in: fixture.context)

        XCTAssertEqual(fixture.session.status, .abandoned)
        XCTAssertEqual(fixture.sets[0].status, .completed)
    }

    @MainActor
    func testEnabledPolicyPreflightsSecondPerformanceAfterFirstStops() async throws {
        let fixture = try makeFixture(
            performanceCount: 2,
            setCount: 1,
            policy: .enabled,
            restSeconds: 0
        )
        defer { clearDefaults(fixture) }
        let recorder = RecordingRecoverySpy()
        let coordinator = makeCoordinator(recorder, fixture: fixture)

        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        XCTAssertEqual(
            fixture.session.currentPerformanceID,
            fixture.performances[1].id
        )

        await coordinator.preflightAutomaticRecording(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)

        XCTAssertEqual(recorder.prepareCount, 2)
        XCTAssertEqual(recorder.attempts.count, 2)
        XCTAssertEqual(
            recorder.attempts.last?.performanceID,
            fixture.performances[1].id
        )
    }

    @MainActor
    func testAutomaticPreflightFailurePausesAndDoesNotRepeatAfterRebuild() async throws {
        let fixture = try makeFixture(setCount: 1, policy: .everySet)
        defer { clearDefaults(fixture) }
        let recorder = RecordingRecoverySpy(
            preparationBehavior: .fail(.permissionDenied)
        )
        let coordinator = makeCoordinator(recorder, fixture: fixture)

        await coordinator.activate(fixture.session, in: fixture.context)

        XCTAssertEqual(recorder.prepareCount, 1)
        XCTAssertTrue(coordinator.automaticRecordingPaused)
        XCTAssertTrue(fixture.session.automaticRecordingPaused)
        XCTAssertEqual(
            fixture.session.automaticRecordingPauseCode,
            .permissionDenied
        )
        XCTAssertTrue(
            fixture.session.automaticRecordingPauseReason?
                .contains("系统设置") == true
        )
        XCTAssertNotNil(coordinator.recordingFailure)
        XCTAssertFalse(coordinator.isStartingRecording)

        let rebuilt = makeCoordinator(recorder, fixture: fixture)
        await rebuilt.activate(fixture.session, in: fixture.context)

        XCTAssertEqual(recorder.prepareCount, 1)
        XCTAssertTrue(rebuilt.recordingStatusMessage?.contains("手动重试") == true)
        XCTAssertTrue(rebuilt.recordingStatusMessage?.contains("系统设置") == true)
        XCTAssertTrue(rebuilt.recordingErrorMessage?.contains("系统设置") == true)
    }

    @MainActor
    func testPartialRecordingIsDurableAndWarnedOnlyOnce() async throws {
        let fixture = try makeFixture(setCount: 1, policy: .enabled)
        defer { clearDefaults(fixture) }
        let recorder = RecordingRecoverySpy()
        let coordinator = makeCoordinator(recorder, fixture: fixture)
        try await startFirstSet(coordinator, fixture: fixture)

        let attempt = try XCTUnwrap(recorder.attempts.last)
        let path = "PrivateMedia/partial.mov"
        let message = "系统提前停止录像；已保留可用片段，训练仍可继续。"
        recorder.finishWithPartial(path: path, message: message)
        let firstFailure = try XCTUnwrap(coordinator.recordingFailure)
        recorder.recordingEventHandler?(.savedPartial(
            attempt,
            path: path,
            message: message
        ))

        XCTAssertEqual(fixture.efforts[0].recordedVideoPath, path)
        XCTAssertEqual(fixture.efforts[0].recordedVideoKind, .partial)
        XCTAssertEqual(fixture.sets[0].recordedVideoKind, .partial)
        XCTAssertEqual(fixture.performances[0].activeVideoKind, .partial)
        XCTAssertEqual(coordinator.recordingFailure?.id, firstFailure.id)
        XCTAssertEqual(coordinator.recordingFailure?.message, message)
        XCTAssertTrue(coordinator.automaticRecordingPaused)
        XCTAssertNil(coordinator.recordingSetID)

        try await coordinator.confirmCurrentSet(
            actualReps: 8,
            actualWeightKG: 20,
            in: fixture.context
        )
        let entry = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<WorkoutEntry>()).first
        )
        XCTAssertEqual(entry.setEntries.first?.recordedVideoKind, .partial)
    }

    @MainActor
    func testPartialManualRetryDoesNotResumeAutomaticRecording() async throws {
        let fixture = try makeFixture(setCount: 1, policy: .enabled)
        defer { clearDefaults(fixture) }
        let recorder = RecordingRecoverySpy()
        let coordinator = makeCoordinator(recorder, fixture: fixture)
        try await startFirstSet(coordinator, fixture: fixture)
        recorder.finishWithFailure()
        XCTAssertTrue(coordinator.automaticRecordingPaused)

        try await coordinator.startManualRecording(in: fixture.context)
        recorder.finishWithPartial(
            path: "PrivateMedia/manual-partial.mov",
            message: "手动重试也被系统提前停止；已保留片段。"
        )

        XCTAssertTrue(coordinator.automaticRecordingPaused)
        XCTAssertTrue(fixture.session.automaticRecordingPaused)
        XCTAssertEqual(
            fixture.efforts[0].recordedVideoPath,
            "PrivateMedia/manual-partial.mov"
        )
    }

    @MainActor
    func testQueueFromConfirmationTargetsNextPendingEffort() async throws {
        let fixture = try makeFixture(
            setCount: 2,
            policy: .disabled,
            restSeconds: 0
        )
        defer { clearDefaults(fixture) }
        let recorder = RecordingRecoverySpy()
        let coordinator = makeCoordinator(recorder, fixture: fixture)
        try await startFirstSet(coordinator, fixture: fixture)
        try coordinator.requestSetConfirmation(in: fixture.context)

        try await coordinator.toggleManualRecording(in: fixture.context)

        XCTAssertEqual(
            fixture.session.queuedRecordingEffortID,
            fixture.efforts[1].id
        )
        XCTAssertNotEqual(
            fixture.session.queuedRecordingEffortID,
            fixture.efforts[0].id
        )
        XCTAssertEqual(recorder.prepareCount, 1)
    }

    @MainActor
    func testQueuedPreparationCanBeCancelledWhilePrepareIsSuspended() async throws {
        let fixture = try makeFixture(setCount: 1, policy: .disabled)
        defer { clearDefaults(fixture) }
        let recorder = RecordingRecoverySpy(preparationBehavior: .suspend)
        let coordinator = makeCoordinator(recorder, fixture: fixture)
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)

        let prepareTask = Task {
            try await coordinator.toggleManualRecording(in: fixture.context)
        }
        while recorder.prepareCount == 0 {
            await Task.yield()
        }
        XCTAssertTrue(coordinator.isStartingRecording)
        XCTAssertTrue(coordinator.manualRecordingQueued)

        try await coordinator.toggleManualRecording(in: fixture.context)
        XCTAssertFalse(coordinator.isStartingRecording)
        XCTAssertFalse(coordinator.manualRecordingQueued)
        XCTAssertNil(fixture.session.queuedRecordingEffortID)
        XCTAssertEqual(recorder.cancelCount, 1)

        recorder.resumePreparation()
        try await prepareTask.value
        XCTAssertFalse(coordinator.manualRecordingQueued)
    }

    @MainActor
    func testSkippingQueuedExerciseRedirectsReservationToNextPerformance() async throws {
        let fixture = try makeFixture(
            performanceCount: 2,
            setCount: 1,
            policy: .disabled
        )
        defer { clearDefaults(fixture) }
        let recorder = RecordingRecoverySpy()
        let coordinator = makeCoordinator(recorder, fixture: fixture)
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try await coordinator.toggleManualRecording(in: fixture.context)
        XCTAssertEqual(
            fixture.session.queuedRecordingEffortID,
            fixture.efforts[0].id
        )

        try await coordinator.skipCurrentExercise(in: fixture.context)

        XCTAssertEqual(
            fixture.session.currentPerformanceID,
            fixture.performances[1].id
        )
        XCTAssertEqual(
            fixture.session.queuedRecordingEffortID,
            fixture.efforts[1].id
        )
        XCTAssertTrue(coordinator.manualRecordingQueued)
    }

    @MainActor
    func testActivateRedirectsStaleQueuedEffortAndPauseClearsIt() async throws {
        let fixture = try makeFixture(setCount: 2, policy: .disabled)
        defer { clearDefaults(fixture) }
        fixture.efforts[0].status = .skipped
        fixture.sets[0].status = .skipped
        fixture.session.currentSetID = fixture.sets[1].id
        fixture.session.currentEffortID = fixture.efforts[1].id
        fixture.session.queuedRecordingEffortID = fixture.efforts[0].id
        try fixture.context.save()
        let recorder = RecordingRecoverySpy()
        let coordinator = makeCoordinator(recorder, fixture: fixture)

        await coordinator.activate(fixture.session, in: fixture.context)

        XCTAssertEqual(
            fixture.session.queuedRecordingEffortID,
            fixture.efforts[1].id
        )
        XCTAssertTrue(coordinator.manualRecordingQueued)
        XCTAssertEqual(recorder.prepareCount, 1)

        try await coordinator.pause(in: fixture.context)

        XCTAssertNil(fixture.session.queuedRecordingEffortID)
        XCTAssertFalse(coordinator.manualRecordingQueued)
    }

    func testLegacyBindingFactDecodesMissingKindAsComplete() throws {
        struct LegacyFact: Codable {
            let sessionID: UUID
            let attempt: WorkoutRecordingAttempt
            let path: String
        }
        let legacy = LegacyFact(
            sessionID: UUID(),
            attempt: WorkoutRecordingAttempt(
                performanceID: UUID(),
                setID: UUID()
            ),
            path: "PrivateMedia/legacy.mov"
        )

        let decoded = try JSONDecoder().decode(
            WorkoutRecordingBindingFact.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertEqual(decoded.kind, .complete)
    }

    @MainActor
    func testStaleSessionCleanupCannotTearDownNewSessionRecording() async throws {
        let oldFixture = try makeFixture(setCount: 1, policy: .disabled)
        let newFixture = try makeFixture(setCount: 1, policy: .enabled)
        defer {
            clearDefaults(oldFixture)
            clearDefaults(newFixture)
        }
        let recorder = SuspendedSessionEndRecordingSpy()
        let coordinator = makeCoordinator(recorder, fixture: oldFixture)
        let oldOwner = await coordinator.activate(
            oldFixture.session,
            in: oldFixture.context
        )

        let oldCleanup = Task { @MainActor in
            await coordinator.deactivate(owner: oldOwner)
        }
        while !recorder.isEndSuspended {
            await Task.yield()
        }

        let newOwner = await coordinator.activate(
            newFixture.session,
            in: newFixture.context
        )
        try coordinator.introduceCurrentExercise(in: newFixture.context)
        try coordinator.prepareCurrentSet(in: newFixture.context)
        try await coordinator.beginCurrentSet(in: newFixture.context)
        let newAttempt = try XCTUnwrap(recorder.activeAttempt)

        XCTAssertTrue(coordinator.isActive(owner: newOwner))
        XCTAssertEqual(coordinator.activeSessionID, newFixture.session.id)
        XCTAssertEqual(recorder.activeOwner, newOwner)
        XCTAssertEqual(recorder.prepareCount, 1)
        XCTAssertEqual(newAttempt.effortID, newFixture.efforts[0].id)
        XCTAssertEqual(
            coordinator.recordingSetID,
            newFixture.sets[0].id
        )

        recorder.resumeEnd()
        let didDeactivateOldSession = await oldCleanup.value
        XCTAssertFalse(didDeactivateOldSession)

        XCTAssertTrue(coordinator.isActive(owner: newOwner))
        XCTAssertEqual(coordinator.activeSessionID, newFixture.session.id)
        XCTAssertEqual(recorder.activeOwner, newOwner)
        XCTAssertEqual(recorder.activeAttempt?.id, newAttempt.id)
        XCTAssertEqual(
            coordinator.recordingSetID,
            newFixture.sets[0].id
        )
        XCTAssertEqual(newFixture.session.guidedPhase, .setInProgress)
    }

    @MainActor
    private func startFirstSet(
        _ coordinator: GuidedWorkoutCoordinator,
        fixture: Fixture
    ) async throws {
        await coordinator.activate(fixture.session, in: fixture.context)
        try coordinator.introduceCurrentExercise(in: fixture.context)
        try coordinator.prepareCurrentSet(in: fixture.context)
        try await coordinator.beginCurrentSet(in: fixture.context)
    }

    @MainActor
    private func makeCoordinator(
        _ recorder: WorkoutRecordingControlling,
        fixture: Fixture
    ) -> GuidedWorkoutCoordinator {
        GuidedWorkoutCoordinator(
            recorder: recorder,
            cues: RecordingRecoveryCues(),
            now: { fixture.now },
            recordingBindingDefaults: fixture.defaults
        )
    }

    private func clearDefaults(_ fixture: Fixture) {
        fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
    }

    @MainActor
    private func makeFixture(
        performanceCount: Int = 1,
        setCount: Int,
        policy: AutoRecordingPolicy,
        restSeconds: Int = 90
    ) throws -> Fixture {
        let suiteName = "GuidedRecordingRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let context = try ModelContext(XCTUnwrap(spaces.personalContainer))
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        var prescriptions: [TemplateExercisePrescription] = []
        var performances: [ExercisePerformance] = []
        var sets: [WorkoutSet] = []
        var efforts: [WorkoutEffort] = []

        for performanceOrder in 1 ... performanceCount {
            let definition = try ExerciseLibraryStore.resolveOrCreateExact(
                canonicalName: "恢复测试动作 \(performanceOrder)",
                in: context
            )
            let plannedSets = (1 ... setCount).map { order in
                TemplateSetPrescriptionValue(
                    order: order,
                    kind: .working,
                    targetKind: .repetitions,
                    targetReps: 8,
                    targetWeightKG: 20,
                    restAfterSetSeconds: restSeconds
                )
            }
            let prescription = TemplateExercisePrescription(
                exerciseID: definition.id,
                exerciseName: definition.canonicalName,
                order: performanceOrder,
                targetSets: setCount,
                targetReps: 8,
                targetWeightKG: 20,
                targetRestSeconds: restSeconds,
                firstSetIsWarmup: false,
                laterality: .none,
                plannedSets: plannedSets
            )
            prescriptions.append(prescription)
            let performance = ExercisePerformance(
                sessionID: UUID(),
                exerciseID: definition.id,
                exerciseName: definition.canonicalName,
                order: performanceOrder,
                prescriptionSnapshot: prescription
            )
            performance.exerciseDefinition = definition
            performances.append(performance)
            for setOrder in 1 ... setCount {
                let set = WorkoutSet(
                    performanceID: performance.id,
                    order: setOrder,
                    kind: .working,
                    laterality: ExerciseLaterality.none.rawValue,
                    plannedTargetKind: .repetitions,
                    plannedReps: 8,
                    plannedWeightKG: 20,
                    plannedRestSeconds: restSeconds
                )
                set.performance = performance
                sets.append(set)
                let effort = WorkoutEffort(
                    workoutSetID: set.id,
                    order: 1,
                    side: .none,
                    targetKind: .repetitions,
                    plannedReps: 8,
                    plannedWeightKG: 20
                )
                effort.workoutSet = set
                efforts.append(effort)
            }
        }

        let session = WorkoutSession(
            startedAt: now,
            prescriptionSnapshot: prescriptions,
            status: .active,
            autoRecordingPolicy: policy
        )
        for performance in performances {
            performance.sessionID = session.id
            performance.session = session
        }
        session.currentPerformanceID = performances.first?.id
        session.currentSetID = sets.first?.id
        session.currentEffortID = efforts.first?.id
        context.insert(session)
        performances.forEach(context.insert)
        sets.forEach(context.insert)
        efforts.forEach(context.insert)
        try context.save()
        return Fixture(
            context: context,
            defaults: defaults,
            suiteName: suiteName,
            session: session,
            performances: performances,
            sets: sets,
            efforts: efforts,
            now: now
        )
    }
}
