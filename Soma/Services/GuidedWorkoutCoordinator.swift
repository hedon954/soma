import AVFoundation
import Observation
import SwiftData

@MainActor
@Observable
final class GuidedWorkoutCoordinator {
    private struct EffortCompletionLease: Equatable {
        let id: UUID
        let sessionID: UUID
        let effortID: UUID
        let phase: GuidedWorkoutPhase
        let transitionRevision: Int
    }

    private(set) var activeSessionID: UUID?
    private(set) var activeSessionOwner: WorkoutCameraSessionOwnerToken?
    private(set) var lastErrorMessage: String?
    private(set) var recordingErrorMessage: String?
    private(set) var recordingFailure: WorkoutRecordingFailure?
    private(set) var recordingStatusMessage: String?
    private(set) var recordingSetID: UUID?
    private(set) var isStartingRecording = false
    private(set) var manualRecordingQueued = false
    private(set) var automaticRecordingPaused = false
    private(set) var isCompletingCurrentEffort = false

    @ObservationIgnored private let recorder: WorkoutRecordingControlling
    @ObservationIgnored private let cues: WorkoutCueProviding
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let recordingBindingInbox:
        WorkoutRecordingBindingInbox
    @ObservationIgnored private let saveRecordingBinding:
        @MainActor (ModelContext) throws -> Void
    @ObservationIgnored private let materializePerformance:
        @MainActor (
            ExercisePerformance,
            WorkoutSession,
            ModelContext
        ) throws -> WorkoutEntry?
    @ObservationIgnored private var activeSessionReference: WorkoutSession?
    @ObservationIgnored private var activeContext: ModelContext?
    @ObservationIgnored private var recordingRequestID: UUID?
    @ObservationIgnored private var activeRecordingAttempt:
        WorkoutRecordingAttempt?
    @ObservationIgnored private var pendingRecordings:
        [UUID: WorkoutRecordingBindingFact] = [:]
    @ObservationIgnored private var terminalRecordingAttemptIDs = Set<UUID>()
    @ObservationIgnored private var reportedRecordingAttemptIDs = Set<UUID>()
    @ObservationIgnored private var automaticRecordingAttemptIDs = Set<UUID>()
    @ObservationIgnored private var announcedCountdownValues = Set<Int>()
    @ObservationIgnored private var activeEffortCompletionLease:
        EffortCompletionLease?

    init(
        recorder: WorkoutRecordingControlling,
        cues: WorkoutCueProviding,
        now: @escaping () -> Date = Date.init,
        materializePerformance: @escaping @MainActor (
            ExercisePerformance,
            WorkoutSession,
            ModelContext
        ) throws -> WorkoutEntry? = { performance, session, context in
            try GuidedWorkoutRecordStore.materialize(
                performance: performance,
                session: session,
                in: context
            )
        },
        recordingBindingDefaults: UserDefaults = .standard,
        saveRecordingBinding: @escaping @MainActor (
            ModelContext
        ) throws -> Void = { try $0.save() }
    ) {
        self.recorder = recorder
        self.cues = cues
        self.now = now
        self.materializePerformance = materializePerformance
        recordingBindingInbox = WorkoutRecordingBindingInbox(
            defaults: recordingBindingDefaults
        )
        self.saveRecordingBinding = saveRecordingBinding
        recorder.recordingEventHandler = { [weak self] event in
            self?.handleRecordingEvent(event)
        }
    }

    convenience init() {
        self.init(
            recorder: NoopWorkoutRecordingController(),
            cues: SystemWorkoutCueProvider()
        )
    }

    @discardableResult
    func activate(
        _ session: WorkoutSession,
        in context: ModelContext
    ) async -> WorkoutCameraSessionOwnerToken {
        let owner = recorder.claimWorkoutSession(sessionID: session.id)
        activeSessionOwner = owner
        activeEffortCompletionLease = nil
        isCompletingCurrentEffort = false
        activeSessionID = session.id
        activeSessionReference = session
        activeContext = context
        recordingSetID = nil
        isStartingRecording = false
        recordingRequestID = nil
        activeRecordingAttempt = nil
        pendingRecordings = recordingBindingInbox.facts(for: session.id)
            .reduce(into: [:]) { $0[$1.id] = $1 }
        terminalRecordingAttemptIDs = []
        reportedRecordingAttemptIDs = []
        automaticRecordingAttemptIDs = []
        manualRecordingQueued = session.queuedRecordingEffortID != nil
        automaticRecordingPaused = session.automaticRecordingPaused
        recordingErrorMessage = automaticRecordingPaused
            ? session.automaticRecordingPauseReason
            : nil
        recordingFailure = nil
        recordingStatusMessage = automaticRecordingPaused
            ? Self.pausedRecordingStatus(for: session)
            : nil
        announcedCountdownValues = []
        recover(session, in: context)
        replayPendingRecordingBindings(for: session, in: context)
        normalizeQueuedRecording(for: session, in: context)
        if let queuedEffortID = session.queuedRecordingEffortID {
            await prepareQueuedRecording(for: queuedEffortID)
        } else {
            await preflightAutomaticRecording(in: context)
        }
        return owner
    }

    func isActive(owner: WorkoutCameraSessionOwnerToken) -> Bool {
        activeSessionOwner == owner
            && activeSessionID == owner.sessionID
    }

    @discardableResult
    func deactivate(owner: WorkoutCameraSessionOwnerToken) async -> Bool {
        guard isActive(owner: owner) else { return false }
        await recorder.endWorkoutSession(owner: owner)
        guard isActive(owner: owner) else { return false }
        activeSessionOwner = nil
        activeSessionID = nil
        activeSessionReference = nil
        activeContext = nil
        recordingSetID = nil
        isStartingRecording = false
        recordingRequestID = nil
        activeRecordingAttempt = nil
        pendingRecordings = [:]
        terminalRecordingAttemptIDs = []
        reportedRecordingAttemptIDs = []
        automaticRecordingAttemptIDs = []
        manualRecordingQueued = false
        automaticRecordingPaused = false
        recordingErrorMessage = nil
        recordingFailure = nil
        recordingStatusMessage = nil
        activeEffortCompletionLease = nil
        isCompletingCurrentEffort = false
        return true
    }

    func introduceCurrentExercise(
        in context: ModelContext
    ) throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context) else {
            setPhase(.sessionReview, for: session)
            try context.save()
            return
        }
        setPhase(.exerciseIntroduction, for: session)
        if let prescription = performance.prescriptionSnapshot {
            cues.announce(WorkoutPrescriptionFormatter.exerciseAnnouncement(
                name: performance.exerciseName,
                prescription: prescription
            ))
        } else {
            cues.announce("接下来，\(performance.exerciseName)，请按状态完成")
        }
        try context.save()
    }

    func prepareCurrentSet(
        in context: ModelContext
    ) throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context),
              let set = firstPendingSet(for: performance, in: context),
              let effort = firstPendingEffort(for: set, in: context)
        else {
            try advanceAfterPerformance(session, in: context)
            return
        }
        performance.status = .active
        session.currentSetID = set.id
        session.currentEffortID = effort.id
        beginCountdown(for: session, set: set, effort: effort)
        try context.save()
    }

    func announceCountdown(_ value: Int) {
        guard (1 ... 3).contains(value),
              announcedCountdownValues.insert(value).inserted
        else { return }
        cues.announce("\(value)")
    }

    func beginCurrentSet(
        in context: ModelContext
    ) async throws {
        let session = try activeSession(in: context)
        guard session.status == .active,
              session.guidedPhase == .preSetCountdown
        else { return }
        guard let performance = currentPerformance(for: session, in: context),
              let set = currentSet(for: session, in: context),
              let effort = currentEffort(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingEffort
        }
        set.status = .inProgress
        set.startedAt = set.startedAt ?? now()
        effort.status = .inProgress
        effort.startedAt = effort.startedAt ?? now()
        let deadline = effort.targetKind == .duration
            ? effort.startedAt?.addingTimeInterval(
                TimeInterval(effort.plannedDurationSeconds ?? 0)
            )
            : nil
        // BUG 0025：语音播报会激活并释放 AVAudioSession。在录像刚开始的窗口内做这件事，
        // 可能把这次录制打断，所以播报排到录像启动之后。
        let announcement = WorkoutPrescriptionFormatter.effortAnnouncement(
            set: set,
            effort: effort.side == .none ? nil : effort
        )
        let queuedManualRecording = session.queuedRecordingEffortID == effort.id
        if queuedManualRecording {
            session.queuedRecordingEffortID = nil
            manualRecordingQueued = false
        }
        try context.save()

        // PRD 035：倒计时只取景；开组并等执行页宿主后再写文件。
        let previousPreviewHostID = recorder.previewHostID
        setPhase(.setInProgress, deadline: deadline, for: session)
        try context.save()
        let shouldStartRecording = queuedManualRecording || shouldRecord(
            set: set,
            effort: effort,
            performance: performance,
            session: session
        )
        if shouldStartRecording {
            await recorder.waitUntilPreviewHostSettled(
                from: previousPreviewHostID
            )
            await startRecording(
                for: performance,
                set: set,
                effortID: effort.id,
                automatic: !queuedManualRecording
            )
        } else {
            await releaseCameraIfNotNeeded(in: context)
        }
        cues.announce(announcement)
    }

    func shouldCaptureCurrentEffort(in context: ModelContext) -> Bool {
        guard let session = try? activeSession(in: context) else { return false }
        if recordingSetID != nil || isStartingRecording || manualRecordingQueued {
            return true
        }
        if let performance = currentPerformance(for: session, in: context),
           let set = currentSet(for: session, in: context),
           let effort = currentEffort(for: session, in: context)
        {
            return shouldRecord(
                set: set,
                effort: effort,
                performance: performance,
                session: session
            )
        }
        switch session.guidedPhase {
        case .exerciseIntroduction, .preSetCountdown:
            return nextAutomaticRecordingEffortID(
                for: session,
                in: context
            ) != nil
        case .ready, .setInProgress, .setConfirmation, .resting,
             .sessionReview, .completed:
            return false
        }
    }

    func startManualRecording(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        guard session.guidedPhase == .setInProgress else {
            guard let effort = queueableEffort(for: session, in: context) else {
                throw GuidedWorkoutError.missingEffort
            }
            session.queuedRecordingEffortID = effort.id
            manualRecordingQueued = true
            try context.save()
            await prepareQueuedRecording(for: effort.id)
            return
        }
        guard let performance = currentPerformance(for: session, in: context),
              let set = currentSet(for: session, in: context),
              let effort = currentEffort(for: session, in: context)
        else { throw GuidedWorkoutError.missingEffort }
        guard recordingSetID == nil, !isStartingRecording else { return }
        await startRecording(
            for: performance,
            set: set,
            effortID: effort.id,
            automatic: false
        )
    }

    func preflightAutomaticRecording(in context: ModelContext) async {
        guard let session = try? activeSession(in: context),
              recordingSetID == nil,
              !isStartingRecording,
              session.status == .active,
              session.autoRecordingPolicy.usesAutomaticRecording,
              !automaticRecordingPaused,
              nextAutomaticRecordingEffortID(
                  for: session,
                  in: context
              ) != nil
        else { return }
        await prepareAutomaticRecording()
    }

    func toggleManualRecording(in context: ModelContext) async throws {
        if isStartingRecording, activeRecordingAttempt == nil {
            let session = try activeSession(in: context)
            session.queuedRecordingEffortID = nil
            manualRecordingQueued = false
            await cancelActiveRecording()
            try context.save()
        } else if recordingSetID != nil || isStartingRecording {
            try await stopActiveRecording(in: context)
        } else if let session = try? activeSession(in: context),
                  session.guidedPhase != .setInProgress
        {
            if session.queuedRecordingEffortID != nil {
                session.queuedRecordingEffortID = nil
                manualRecordingQueued = false
                recordingStatusMessage = automaticRecordingPaused
                    ? activeSessionReference.map(Self.pausedRecordingStatus(for:))
                    : nil
                await recorder.cancelRecording(attemptID: nil)
            } else if let effort = queueableEffort(for: session, in: context) {
                session.queuedRecordingEffortID = effort.id
                manualRecordingQueued = true
                try context.save()
                await prepareQueuedRecording(for: effort.id)
                return
            } else {
                throw GuidedWorkoutError.noPendingEffortForRecording
            }
            try context.save()
        } else {
            try await startManualRecording(in: context)
        }
    }

    func stopActiveRecording(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context),
              let set = currentSet(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingSet
        }
        if isStartingRecording {
            await cancelActiveRecording()
            return
        }
        await finishActiveRecording(
            for: performance,
            set: set,
            in: context
        )
        try context.save()
    }

    func requestSetConfirmation(
        in context: ModelContext
    ) throws {
        let session = try activeSession(in: context)
        guard let effort = currentEffort(for: session, in: context) else {
            throw GuidedWorkoutError.missingEffort
        }
        guard effort.targetKind == .repetitions else { return }
        setPhase(.setConfirmation, for: session)
        try context.save()
    }

    func confirmCurrentSet(
        actualReps: Int?,
        actualWeightKG: Double?,
        in context: ModelContext
    ) async throws {
        try await completeCurrentEffort(
            actualReps: actualReps,
            actualDurationSeconds: nil,
            actualWeightKG: actualWeightKG,
            in: context
        )
    }

    func completeCurrentEffort(
        actualReps: Int?,
        actualDurationSeconds: Int?,
        actualWeightKG: Double?,
        in context: ModelContext
    ) async throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context),
              let set = currentSet(for: session, in: context),
              let effort = currentEffort(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingEffort
        }
        guard effort.status == .inProgress else { return }
        guard activeEffortCompletionLease == nil else { return }
        let completionLease = EffortCompletionLease(
            id: UUID(),
            sessionID: session.id,
            effortID: effort.id,
            phase: session.guidedPhase,
            transitionRevision: session.transitionRevision
        )
        activeEffortCompletionLease = completionLease
        isCompletingCurrentEffort = true
        defer {
            if activeEffortCompletionLease == completionLease {
                activeEffortCompletionLease = nil
                isCompletingCurrentEffort = false
            }
        }
        if isStartingRecording {
            await cancelActiveRecording()
        } else if recordingSetID == set.id {
            await finishActiveRecording(
                for: performance,
                set: set,
                in: context
            )
        }
        guard activeEffortCompletionLease == completionLease,
              activeSessionID == completionLease.sessionID,
              activeSessionReference?.id == completionLease.sessionID,
              session.status == .active,
              session.currentEffortID == completionLease.effortID,
              currentEffort(for: session, in: context)?.id
              == completionLease.effortID,
              effort.status == .inProgress,
              session.guidedPhase == completionLease.phase,
              session.transitionRevision
              == completionLease.transitionRevision
        else { return }
        applyPendingRecordings(
            to: set,
            in: context
        )
        // A successfully saved movie is an independent fact. Commit it before
        // the Effort transaction so a later projection failure can roll back
        // training state without orphaning the video association.
        try context.save()
        do {
            effort.actualReps = effort.targetKind == .repetitions
                ? (actualReps ?? effort.actualReps)
                : nil
            effort.actualDurationSeconds = actualDurationSeconds
                ?? elapsedDuration(for: effort)
            effort.actualWeightKG = actualWeightKG ?? effort.actualWeightKG
            effort.status = .completed
            effort.completedAt = now()
            try advanceAfterEffort(
                effort,
                set: set,
                performance: performance,
                session: session,
                in: context
            )
            normalizeQueuedRecording(for: session, in: context)
            try context.save()
            cues.success()
            await releaseCameraIfNotNeeded(in: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func updateCurrentEffortDraft(
        actualReps: Int?,
        actualDurationSeconds: Int?,
        actualWeightKG: Double?,
        in context: ModelContext
    ) throws {
        let session = try activeSession(in: context)
        guard let effort = currentEffort(for: session, in: context),
              effort.status == .inProgress
        else { throw GuidedWorkoutError.missingEffort }
        if effort.targetKind == .repetitions {
            effort.actualReps = actualReps
        } else {
            effort.actualDurationSeconds = actualDurationSeconds
        }
        effort.actualWeightKG = actualWeightKG
        try context.save()
    }

    func skipCurrentSet(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context),
              let set = currentSet(for: session, in: context),
              let effort = currentEffort(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingEffort
        }
        await cancelActiveRecording()
        do {
            effort.status = .skipped
            effort.completedAt = now()
            try advanceAfterEffort(
                effort,
                set: set,
                performance: performance,
                session: session,
                in: context
            )
            try context.save()
            await releaseCameraIfNotNeeded(in: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func redoCurrentSet(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        guard let set = currentSet(for: session, in: context),
              let effort = currentEffort(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingEffort
        }
        await cancelActiveRecording()
        effort.status = .pending
        effort.startedAt = nil
        effort.completedAt = nil
        effort.actualReps = nil
        effort.actualDurationSeconds = nil
        effort.actualWeightKG = nil
        effort.actualRestSeconds = nil
        aggregate(set: set, in: context)
        beginCountdown(for: session, set: set, effort: effort)
        try context.save()
    }

    func skipCurrentExercise(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingPerformance
        }
        await cancelActiveRecording()
        for set in sets(for: performance, in: context) {
            for effort in efforts(for: set, in: context)
                where effort.status == .pending || effort.status == .inProgress
            {
                effort.status = .skipped
                effort.completedAt = now()
            }
            aggregate(set: set, in: context)
        }
        performance.status = .skipped
        _ = try materializePerformance(performance, session, context)
        try advanceAfterPerformance(session, in: context)
        normalizeQueuedRecording(for: session, in: context)
        try context.save()
    }

    func replaceCurrentExercise(
        with exercise: ExerciseDefinition,
        in context: ModelContext
    ) throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingPerformance
        }
        performance.exerciseID = exercise.id
        performance.exerciseDefinition = exercise
        performance.exerciseName = exercise.canonicalName
        if var prescription = performance.prescriptionSnapshot {
            prescription.exerciseID = exercise.id
            prescription.exerciseName = exercise.canonicalName
            performance.prescriptionSnapshotData = TrainingPlanCoding.encode(
                prescription
            )
        }
        try context.save()
    }

    func finishRest(in context: ModelContext) throws {
        let session = try activeSession(in: context)
        guard session.guidedPhase == .resting else { return }
        persistCompletedRest(for: session, in: context)
        session.restStartedAt = nil
        session.restTargetEndAt = nil
        guard let set = currentSet(for: session, in: context),
              let effort = currentEffort(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingEffort
        }
        beginCountdown(for: session, set: set, effort: effort)
        try context.save()
    }

    func adjustRest(
        by seconds: Int,
        in context: ModelContext
    ) throws {
        let session = try activeSession(in: context)
        guard session.guidedPhase == .resting else { return }
        let currentTarget = resolvedRestTargetEndAt(
            for: session,
            in: context
        ) ?? now()
        session.restTargetEndAt = max(
            currentTarget.addingTimeInterval(TimeInterval(seconds)),
            now()
        )
        session.phaseDeadlineAt = session.restTargetEndAt
        session.transitionRevision += 1
        announcedCountdownValues = []
        try context.save()
    }

    func remainingRestSeconds(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> Int {
        guard session.guidedPhase == .resting,
              let target = resolvedRestTargetEndAt(
                  for: session,
                  in: context
              )
        else {
            return 0
        }
        return max(Int(ceil(target.timeIntervalSince(now()))), 0)
    }

    func remainingEffortSeconds(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> Int? {
        guard session.guidedPhase == .setInProgress,
              currentEffort(for: session, in: context)?.targetKind == .duration,
              let deadline = session.phaseDeadlineAt
        else { return nil }
        return max(Int(ceil(deadline.timeIntervalSince(now()))), 0)
    }

    func pause(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        await cancelActiveRecording()
        guard session.status == .active else { return }
        clearQueuedRecording(for: session)
        session.status = .paused
        session.phaseStartedAt = now()
        session.transitionRevision += 1
        cues.announce("训练已暂停")
        try context.save()
    }

    func resume(in context: ModelContext) throws {
        let session = try activeSession(in: context)
        guard session.status == .paused else { return }
        let resumedAt = now()
        let pauseDuration = max(
            resumedAt.timeIntervalSince(session.phaseStartedAt ?? resumedAt),
            0
        )
        if let deadline = session.phaseDeadlineAt {
            session.phaseDeadlineAt = deadline.addingTimeInterval(pauseDuration)
        }
        if let target = session.restTargetEndAt {
            session.restTargetEndAt = target.addingTimeInterval(pauseDuration)
        }
        if let started = session.restStartedAt {
            session.restStartedAt = started.addingTimeInterval(pauseDuration)
        }
        if session.guidedPhase == .setInProgress,
           let effort = currentEffort(for: session, in: context),
           let started = effort.startedAt
        {
            effort.startedAt = started.addingTimeInterval(pauseDuration)
        }
        session.status = .active
        session.phaseStartedAt = resumedAt
        session.transitionRevision += 1
        cues.announce("继续训练")
        try context.save()
    }

    func advanceTimelineIfDue(
        expectedRevision: Int,
        in context: ModelContext
    ) async throws {
        let session = try activeSession(in: context)
        guard session.status == .active,
              session.transitionRevision == expectedRevision,
              let deadline = session.phaseDeadlineAt,
              deadline <= now()
        else { return }
        switch session.guidedPhase {
        case .preSetCountdown:
            try await beginCurrentSet(in: context)
        case .resting:
            try finishRest(in: context)
        case .setInProgress:
            guard let effort = currentEffort(for: session, in: context),
                  effort.targetKind == .duration
            else { return }
            try await completeCurrentEffort(
                actualReps: nil,
                actualDurationSeconds: effort.plannedDurationSeconds,
                actualWeightKG: effort.actualWeightKG
                    ?? effort.plannedWeightKG,
                in: context
            )
        case .ready, .exerciseIntroduction, .setConfirmation,
             .sessionReview, .completed:
            return
        }
    }

    func endEarly(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        await cancelActiveRecording()
        session.status = .abandoned
        session.endedAt = now()
        session.phaseDeadlineAt = nil
        session.restTargetEndAt = nil
        session.autoRecordingPolicy = .cancelled
        clearQueuedRecording(for: session)
        for performance in performances(for: session, in: context) {
            _ = try? materializePerformance(performance, session, context)
        }
        activeSessionID = nil
        activeSessionReference = nil
        activeContext = nil
        cues.announce("训练已提前结束")
        try context.save()
    }

    func complete(in context: ModelContext) throws {
        let session = try activeSession(in: context)
        guard session.guidedPhase == .sessionReview else {
            throw GuidedWorkoutError.sessionNotReadyForCompletion
        }
        let sessionPerformances = performances(for: session, in: context)
        let sessionSets = sessionPerformances.flatMap {
            sets(for: $0, in: context)
        }
        let sessionEfforts = sessionSets.flatMap {
            efforts(for: $0, in: context)
        }
        guard sessionPerformances.allSatisfy({
            $0.status == .completed || $0.status == .skipped
        }), sessionSets.allSatisfy({
            $0.status == .completed
                || $0.status == .partial
                || $0.status == .skipped
                || $0.status == .failed
        }), sessionEfforts.allSatisfy({
            $0.status == .completed
                || $0.status == .skipped
                || $0.status == .failed
        }) else {
            throw GuidedWorkoutError.sessionNotReadyForCompletion
        }

        for performance in sessionPerformances {
            let projection = try materializePerformance(
                performance,
                session,
                context
            )
            if performance.status == .completed, projection == nil {
                throw GuidedWorkoutError.missingWorkoutProjection
            }
        }
        try context.save()

        session.status = .completed
        session.guidedPhase = .completed
        session.endedAt = now()
        session.currentEffortID = nil
        session.queuedRecordingEffortID = nil
        session.automaticRecordingPaused = false
        session.phaseDeadlineAt = nil
        session.restTargetEndAt = nil
        do {
            try context.save()
            activeSessionID = nil
            activeSessionReference = nil
            activeContext = nil
        } catch {
            session.status = .active
            session.guidedPhase = .sessionReview
            session.endedAt = nil
            try? context.save()
            throw error
        }
    }

    func setRecordingPolicy(
        _ policy: AutoRecordingPolicy,
        in context: ModelContext
    ) async throws {
        let session = try activeSession(in: context)
        session.autoRecordingPolicy = policy
        if !policy.usesAutomaticRecording {
            await cancelActiveRecording()
        }
        try context.save()
    }
}

extension GuidedWorkoutCoordinator {
    private func recover(
        _ session: WorkoutSession,
        in context: ModelContext
    ) {
        guard session.status == .active || session.status == .paused else {
            return
        }
        if session.currentEffortID == nil,
           let set = currentSet(for: session, in: context)
        {
            session.currentEffortID = firstPendingEffort(
                for: set,
                in: context
            )?.id
        }
        if session.guidedPhase == .setInProgress,
           let effort = currentEffort(for: session, in: context),
           effort.status == .inProgress
        {
            if effort.targetKind == .duration {
                if session.phaseDeadlineAt == nil,
                   let started = effort.startedAt
                {
                    session.phaseDeadlineAt = started.addingTimeInterval(
                        TimeInterval(effort.plannedDurationSeconds ?? 0)
                    )
                }
            } else if session.status == .active {
                setPhase(.setConfirmation, for: session)
            }
        } else if session.guidedPhase == .preSetCountdown,
                  session.phaseDeadlineAt == nil
        {
            session.phaseDeadlineAt = now().addingTimeInterval(
                GuidedSetCountdownClock.duration
            )
            session.transitionRevision += 1
        } else if session.guidedPhase == .resting,
                  session.phaseDeadlineAt == nil
        {
            session.phaseDeadlineAt = resolvedRestTargetEndAt(
                for: session,
                in: context
            )
            session.transitionRevision += 1
        }
        try? context.save()
    }

    private func advanceAfterEffort(
        _ effort: WorkoutEffort,
        set: WorkoutSet,
        performance: ExercisePerformance,
        session: WorkoutSession,
        in context: ModelContext
    ) throws {
        aggregate(set: set, in: context)
        if let nextEffort = efforts(for: set, in: context).first(where: {
            $0.status == .pending
        }) {
            session.currentSetID = set.id
            session.currentEffortID = nextEffort.id
            startRestOrCountdown(
                seconds: set.restBetweenSidesSeconds ?? 0,
                session: session,
                nextSet: set,
                nextEffort: nextEffort,
                completionMessage: effort.status == .skipped
                    ? "已跳过\(WorkoutPrescriptionFormatter.sideName(effort.side))，准备换侧"
                    : "\(WorkoutPrescriptionFormatter.sideName(effort.side))完成，准备换侧"
            )
            return
        }

        aggregate(set: set, in: context)
        let nextSet = sets(for: performance, in: context).first {
            $0.status == .pending
        }
        if let nextSet,
           let nextEffort = firstPendingEffort(for: nextSet, in: context)
        {
            session.currentSetID = nextSet.id
            session.currentEffortID = nextEffort.id
            startRestOrCountdown(
                seconds: set.plannedRestSeconds ?? 0,
                session: session,
                nextSet: nextSet,
                nextEffort: nextEffort,
                completionMessage: set.status == .skipped
                    ? "已跳过第 \(set.order) 组"
                    : "第 \(set.order) 组完成"
            )
            return
        }

        performance.status = sets(for: performance, in: context).contains {
            $0.status == .completed || $0.status == .partial
        } ? .completed : .skipped
        _ = try materializePerformance(performance, session, context)
        try advanceAfterPerformance(session, in: context)
    }

    private func advanceAfterPerformance(
        _ session: WorkoutSession,
        in context: ModelContext
    ) throws {
        let values = performances(for: session, in: context)
        let next = values.first {
            $0.status == .pending || $0.status == .active
        }
        if let next {
            session.currentPerformanceID = next.id
            session.currentSetID = nil
            session.currentEffortID = nil
            session.restStartedAt = nil
            session.restTargetEndAt = nil
            setPhase(.exerciseIntroduction, for: session)
            if let prescription = next.prescriptionSnapshot {
                cues.announce(WorkoutPrescriptionFormatter.exerciseAnnouncement(
                    name: next.exerciseName,
                    prescription: prescription
                ))
            } else {
                cues.announce("接下来，\(next.exerciseName)，请按状态完成")
            }
        } else {
            session.currentPerformanceID = nil
            session.currentSetID = nil
            session.currentEffortID = nil
            session.restStartedAt = nil
            session.restTargetEndAt = nil
            setPhase(.sessionReview, for: session)
            let completedCount = allSets(for: session, in: context)
                .count { $0.status == .completed }
            cues.announce("训练完成，共完成 \(completedCount) 组")
        }
    }

    private func activeSession(
        in context: ModelContext
    ) throws -> WorkoutSession {
        guard let activeSessionID else {
            throw GuidedWorkoutError.missingSession
        }
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == activeSessionID }
        )
        descriptor.fetchLimit = 1
        guard let session = try? context.fetch(descriptor).first,
              session.status == .active || session.status == .paused
        else {
            throw GuidedWorkoutError.missingSession
        }
        return session
    }

    private func currentPerformance(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> ExercisePerformance? {
        guard let id = session.currentPerformanceID else { return nil }
        var descriptor = FetchDescriptor<ExercisePerformance>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func currentSet(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> WorkoutSet? {
        guard let id = session.currentSetID else { return nil }
        var descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func currentEffort(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> WorkoutEffort? {
        guard let id = session.currentEffortID else { return nil }
        var descriptor = FetchDescriptor<WorkoutEffort>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func firstPendingSet(
        for performance: ExercisePerformance,
        in context: ModelContext
    ) -> WorkoutSet? {
        sets(for: performance, in: context).first { $0.status == .pending }
    }

    private func performances(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> [ExercisePerformance] {
        let sessionID = session.id
        let descriptor = FetchDescriptor<ExercisePerformance>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.order)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func sets(
        for performance: ExercisePerformance,
        in context: ModelContext
    ) -> [WorkoutSet] {
        let performanceID = performance.id
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.performanceID == performanceID },
            sortBy: [SortDescriptor(\.order)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func efforts(
        for set: WorkoutSet,
        in context: ModelContext
    ) -> [WorkoutEffort] {
        let setID = set.id
        let descriptor = FetchDescriptor<WorkoutEffort>(
            predicate: #Predicate { $0.workoutSetID == setID },
            sortBy: [SortDescriptor(\.order)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func firstPendingEffort(
        for set: WorkoutSet,
        in context: ModelContext
    ) -> WorkoutEffort? {
        efforts(for: set, in: context).first { $0.status == .pending }
    }

    private func queueableEffort(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> WorkoutEffort? {
        if let current = currentEffort(for: session, in: context),
           current.status == .pending
        {
            return current
        }
        if session.guidedPhase == .setInProgress,
           let current = currentEffort(for: session, in: context),
           current.status == .inProgress
        {
            return current
        }
        for performance in performances(for: session, in: context) {
            for set in sets(for: performance, in: context) {
                if let effort = firstPendingEffort(for: set, in: context) {
                    return effort
                }
            }
        }
        return nil
    }

    private func normalizeQueuedRecording(
        for session: WorkoutSession,
        in context: ModelContext
    ) {
        guard session.queuedRecordingEffortID != nil else {
            manualRecordingQueued = false
            return
        }
        let canonical = canonicalPendingRecordingEffort(
            for: session,
            in: context
        )
        session.queuedRecordingEffortID = canonical?.id
        manualRecordingQueued = canonical != nil
        if canonical == nil, !automaticRecordingPaused {
            recordingStatusMessage = nil
        }
        try? context.save()
    }

    private func canonicalPendingRecordingEffort(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> WorkoutEffort? {
        if let current = currentEffort(for: session, in: context),
           current.status == .pending
        {
            return current
        }
        for performance in performances(for: session, in: context)
            where performance.status == .pending || performance.status == .active
        {
            for set in sets(for: performance, in: context)
                where set.status == .pending || set.status == .inProgress
            {
                if let effort = efforts(for: set, in: context).first(where: {
                    $0.status == .pending
                }) {
                    return effort
                }
            }
        }
        return nil
    }

    private func clearQueuedRecording(for session: WorkoutSession) {
        session.queuedRecordingEffortID = nil
        manualRecordingQueued = false
    }

    private func prepareQueuedRecording(for effortID: UUID) async {
        let requestID = UUID()
        recordingRequestID = requestID
        isStartingRecording = true
        recordingErrorMessage = nil
        recordingStatusMessage = "正在启动相机，为下一组录像做准备…"
        do {
            try await recorder.prepare()
            guard recordingRequestID == requestID else { return }
            guard activeSessionReference?.queuedRecordingEffortID == effortID else {
                clearRecordingState()
                return
            }
            recordingStatusMessage = automaticRecordingPaused
                ? "相机已就绪，下一组将手动录像；保存后会恢复自动录像。"
                : "相机已就绪，下一组将自动开始录像。"
        } catch {
            guard recordingRequestID == requestID else { return }
            activeSessionReference?.queuedRecordingEffortID = nil
            manualRecordingQueued = false
            try? activeContext?.save()
            reportRecordingFailure(
                error,
                stage: "prepare-queued",
                attemptID: requestID
            )
            recordingStatusMessage = "相机未能就绪。点击录像可重试，训练仍可继续。"
        }
        if recordingRequestID == requestID {
            recordingRequestID = nil
            isStartingRecording = false
        }
    }

    private func prepareAutomaticRecording() async {
        let requestID = UUID()
        recordingRequestID = requestID
        isStartingRecording = true
        recordingErrorMessage = nil
        recordingStatusMessage = "正在启动相机，为自动录像做准备…"
        do {
            try await recorder.prepare()
            guard recordingRequestID == requestID else { return }
            recordingStatusMessage = "相机已就绪，目标组开始时会自动录像。"
        } catch {
            guard recordingRequestID == requestID else { return }
            pauseAutomaticRecording(for: error)
            reportRecordingFailure(
                error,
                stage: "prepare-automatic",
                attemptID: requestID
            )
        }
        if recordingRequestID == requestID {
            recordingRequestID = nil
            isStartingRecording = false
        }
    }

    private func nextAutomaticRecordingEffortID(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> UUID? {
        guard let performance = currentPerformance(for: session, in: context)
        else { return nil }
        for set in sets(for: performance, in: context) {
            for effort in efforts(for: set, in: context)
                where effort.status == .pending || effort.status == .inProgress
            {
                if shouldRecord(
                    set: set,
                    effort: effort,
                    performance: performance,
                    session: session
                ) {
                    return effort.id
                }
            }
        }
        return nil
    }

    private func updateAutomaticRecordingPaused(
        _ value: Bool,
        code: WorkoutRecordingPauseCode? = nil,
        reason: String? = nil
    ) {
        automaticRecordingPaused = value
        activeSessionReference?.automaticRecordingPaused = value
        if value {
            activeSessionReference?.automaticRecordingPauseCode = code ?? .unknown
            activeSessionReference?.automaticRecordingPauseReason = reason
            recordingStatusMessage = activeSessionReference.map(
                Self.pausedRecordingStatus(for:)
            )
        } else {
            activeSessionReference?.automaticRecordingPauseCode = nil
            activeSessionReference?.automaticRecordingPauseReason = nil
        }
        try? activeContext?.save()
    }

    private func pauseAutomaticRecording(for error: Error) {
        updateAutomaticRecordingPaused(
            true,
            code: Self.pauseCode(for: error),
            reason: Self.friendlyRecordingError(error)
        )
    }

    private func beginCountdown(
        for session: WorkoutSession,
        set: WorkoutSet,
        effort: WorkoutEffort
    ) {
        session.restStartedAt = nil
        session.restTargetEndAt = nil
        setPhase(
            .preSetCountdown,
            deadline: now().addingTimeInterval(GuidedSetCountdownClock.duration),
            for: session
        )
        announcedCountdownValues = []
        cues.announce(
            "准备，" + WorkoutPrescriptionFormatter.effortAnnouncement(
                set: set,
                effort: effort.side == .none ? nil : effort
            )
        )
    }

    private func startRestOrCountdown(
        seconds: Int,
        session: WorkoutSession,
        nextSet: WorkoutSet,
        nextEffort: WorkoutEffort,
        completionMessage: String
    ) {
        guard seconds > 0 else {
            beginCountdown(
                for: session,
                set: nextSet,
                effort: nextEffort
            )
            return
        }
        let startedAt = now()
        let deadline = startedAt.addingTimeInterval(TimeInterval(seconds))
        session.restStartedAt = startedAt
        session.restTargetEndAt = deadline
        setPhase(.resting, deadline: deadline, for: session)
        announcedCountdownValues = []
        cues.announce("\(completionMessage)，休息 \(seconds) 秒")
    }

    private func persistCompletedRest(
        for session: WorkoutSession,
        in context: ModelContext
    ) {
        guard let startedAt = session.restStartedAt else { return }
        let elapsed = max(Int(now().timeIntervalSince(startedAt)), 0)
        guard let set = currentSet(for: session, in: context),
              let effort = currentEffort(for: session, in: context)
        else { return }
        if let previousEffort = efforts(for: set, in: context)
            .last(where: { $0.order < effort.order && $0.status != .pending })
        {
            previousEffort.actualRestSeconds = elapsed
            return
        }
        guard let performance = currentPerformance(for: session, in: context),
              let previousSet = sets(for: performance, in: context)
              .last(where: { $0.order < set.order })
        else { return }
        previousSet.actualRestSeconds = elapsed
    }

    private func aggregate(
        set: WorkoutSet,
        in context: ModelContext
    ) {
        let values = efforts(for: set, in: context)
        guard !values.isEmpty else { return }
        let hasNonterminal = values.contains {
            $0.status == .pending || $0.status == .inProgress
        }
        if hasNonterminal {
            set.status = values.contains { $0.status == .inProgress }
                || values.contains { $0.status == .completed }
                ? .inProgress
                : .pending
            set.completedAt = nil
        } else {
            set.status = Self.terminalSetStatus(
                for: values.map(\.status)
            ) ?? .failed
            set.completedAt = values.compactMap(\.completedAt).max() ?? now()
        }

        let completed = values.filter { $0.status == .completed }
        let reps = completed.compactMap(\.actualReps)
        let durations = completed.compactMap(\.actualDurationSeconds)
        let weights = completed.compactMap(\.actualWeightKG)
        set.actualReps = reps.isEmpty ? nil : reps.reduce(0, +)
        set.actualDurationSeconds = durations.isEmpty
            ? nil
            : durations.reduce(0, +)
        set.actualWeightKG = Set(weights).count == 1 ? weights.first : nil
        set.startedAt = values.compactMap(\.startedAt).min()
        if set.recordedVideoPath == nil,
           let source = completed.first(where: { $0.recordedVideoPath != nil })
        {
            set.recordedVideoPath = source.recordedVideoPath
            set.recordedVideoKind = source.recordedVideoKind
        }
    }

    private func elapsedDuration(for effort: WorkoutEffort) -> Int? {
        guard let startedAt = effort.startedAt else {
            return effort.plannedDurationSeconds
        }
        return max(Int(now().timeIntervalSince(startedAt).rounded()), 0)
    }

    private func shouldRecord(
        set: WorkoutSet,
        effort: WorkoutEffort,
        performance: ExercisePerformance,
        session: WorkoutSession
    ) -> Bool {
        guard !automaticRecordingPaused,
              effort.recordedVideoPath == nil
        else { return false }
        if session.autoRecordingPolicy == .everySet {
            return true
        }
        guard session.autoRecordingPolicy == .enabled,
              let prescription = performance.prescriptionSnapshot
        else { return false }
        let firstWorkingOrder = prescription.plannedSets
            .filter { $0.kind == .working }
            .min { $0.order < $1.order }?.order
        return set.kind == .working
            && set.order == (
                firstWorkingOrder
                    ?? (prescription.firstSetIsWarmup ? 2 : 1)
            )
    }

    private func releaseCameraIfNotNeeded(in context: ModelContext) async {
        guard recordingSetID == nil, !isStartingRecording else { return }
        guard !shouldCaptureCurrentEffort(in: context) else { return }
        recordingStatusMessage = nil
        await recorder.idlePreviewKeepingSessionOwner()
    }

    private func startRecording(
        for performance: ExercisePerformance,
        set: WorkoutSet,
        effortID: UUID?,
        automatic: Bool
    ) async {
        if isStartingRecording, activeRecordingAttempt == nil {
            recordingRequestID = nil
            isStartingRecording = false
        }
        guard recordingSetID == nil, !isStartingRecording else { return }
        let attempt = WorkoutRecordingAttempt(
            performanceID: performance.id,
            setID: set.id,
            effortID: effortID
        )
        recordingRequestID = attempt.id
        activeRecordingAttempt = attempt
        if automatic {
            automaticRecordingAttemptIDs.insert(attempt.id)
        }
        isStartingRecording = true
        recordingErrorMessage = nil
        recordingStatusMessage = "正在启动相机并开启录像…"
        do {
            try await recorder.startRecording(attempt: attempt)
            guard recordingRequestID == attempt.id else {
                return
            }
            guard !terminalRecordingAttemptIDs.contains(attempt.id) else {
                return
            }
            recordingSetID = set.id
            recordingErrorMessage = nil
            recordingStatusMessage = "正在录像。"
        } catch {
            if recordingRequestID == attempt.id {
                if automaticRecordingAttemptIDs.contains(attempt.id) {
                    pauseAutomaticRecording(for: error)
                }
                finishRecordingState(for: attempt)
                reportRecordingFailure(
                    error,
                    stage: "start",
                    attemptID: attempt.id
                )
            }
        }
        if recordingRequestID == attempt.id {
            recordingRequestID = nil
            isStartingRecording = false
        }
    }

    private func cancelActiveRecording() async {
        let attempt = activeRecordingAttempt
        if let attempt {
            finishRecordingState(for: attempt)
        } else {
            clearRecordingState()
        }
        await recorder.cancelRecording(attemptID: attempt?.id)
    }

    private func finishActiveRecording(
        for performance: ExercisePerformance,
        set: WorkoutSet,
        in context: ModelContext
    ) async {
        applyPendingRecordings(
            to: set,
            in: context
        )
        guard let attempt = activeRecordingAttempt,
              attempt.setID == set.id
        else {
            recordingSetID = nil
            return
        }
        do {
            if let path = try await recorder.stopRecording(
                attemptID: attempt.id
            ) {
                guard !terminalRecordingAttemptIDs.contains(attempt.id) else {
                    applyPendingRecordings(to: set, in: context)
                    return
                }
                let didBind = persistSavedRecording(
                    path,
                    attempt: attempt
                )
                if !automaticRecordingAttemptIDs.contains(attempt.id) {
                    updateAutomaticRecordingPaused(false)
                }
                if didBind {
                    clearRecordingFailure(for: attempt.id)
                }
                recordingStatusMessage = nil
            }
        } catch {
            if automaticRecordingAttemptIDs.contains(attempt.id) {
                pauseAutomaticRecording(for: error)
            }
            reportRecordingFailure(
                error,
                stage: "stop",
                attemptID: attempt.id
            )
        }
        finishRecordingState(for: attempt)
        applyPendingRecordings(
            to: set,
            in: context
        )
    }

    private func handleRecordingEvent(_ event: WorkoutRecordingAttemptEvent) {
        switch event {
        case let .started(attempt):
            guard activeRecordingAttempt?.id == attempt.id,
                  !terminalRecordingAttemptIDs.contains(attempt.id)
            else { return }
            recordingSetID = attempt.setID
            isStartingRecording = false
            recordingErrorMessage = nil
            recordingStatusMessage = "正在录像。"
        case let .saved(attempt, path):
            guard !terminalRecordingAttemptIDs.contains(attempt.id) else {
                return
            }
            if persistSavedRecording(path, attempt: attempt) {
                clearRecordingFailure(for: attempt.id)
            }
            if !automaticRecordingAttemptIDs.contains(attempt.id) {
                updateAutomaticRecordingPaused(false)
            }
            recordingStatusMessage = nil
            finishRecordingState(for: attempt)
        case let .savedPartial(attempt, path, message):
            guard !terminalRecordingAttemptIDs.contains(attempt.id) else {
                return
            }
            _ = persistSavedRecording(
                path,
                attempt: attempt,
                kind: .partial
            )
            if automaticRecordingAttemptIDs.contains(attempt.id) {
                updateAutomaticRecordingPaused(
                    true,
                    code: .interrupted,
                    reason: message
                )
            } else if automaticRecordingPaused {
                updateAutomaticRecordingPaused(
                    true,
                    code: .interrupted,
                    reason: message
                )
            }
            finishRecordingState(for: attempt)
            reportRecordingFailure(
                WorkoutCameraError.recordingFailed(message),
                stage: "finish-partial",
                attemptID: attempt.id,
                logsDiagnostics: false,
                userMessage: message
            )
        case let .failed(attempt, error):
            guard !terminalRecordingAttemptIDs.contains(attempt.id) else {
                return
            }
            if automaticRecordingAttemptIDs.contains(attempt.id) {
                pauseAutomaticRecording(for: error)
            }
            finishRecordingState(for: attempt)
            recordingStatusMessage = "录像失败。点击录像可重试，训练仍可继续。"
            reportRecordingFailure(
                error,
                stage: "finish",
                attemptID: attempt.id,
                logsDiagnostics: false
            )
        case let .cancelled(attempt):
            guard !terminalRecordingAttemptIDs.contains(attempt.id) else {
                return
            }
            finishRecordingState(for: attempt)
            recordingStatusMessage = automaticRecordingPaused
                ? activeSessionReference.map(Self.pausedRecordingStatus(for:))
                : nil
        }
    }

    private func finishRecordingState(for attempt: WorkoutRecordingAttempt) {
        terminalRecordingAttemptIDs.insert(attempt.id)
        if activeRecordingAttempt?.id == attempt.id {
            activeRecordingAttempt = nil
        }
        if recordingRequestID == attempt.id {
            recordingRequestID = nil
            isStartingRecording = false
        }
        if recordingSetID == attempt.setID {
            recordingSetID = nil
        }
    }

    private func clearRecordingState() {
        recordingSetID = nil
        isStartingRecording = false
        recordingRequestID = nil
        activeRecordingAttempt = nil
        recordingStatusMessage = automaticRecordingPaused
            ? activeSessionReference.map(Self.pausedRecordingStatus(for:))
            : nil
    }

    private func applyPendingRecordings(
        to set: WorkoutSet,
        in context: ModelContext
    ) {
        let matching = pendingRecordings.values.filter {
            $0.attempt.setID == set.id
        }
        for recording in matching {
            _ = bindPendingRecording(
                recording,
                sessionID: activeSessionID,
                in: context
            )
        }
    }

    private func persistRecordingPath(
        _ path: String,
        attempt: WorkoutRecordingAttempt,
        kind: WorkoutRecordingEvidenceKind,
        to set: WorkoutSet,
        performance: ExercisePerformance,
        in context: ModelContext
    ) {
        var effort: WorkoutEffort?
        if let effortID = attempt.effortID {
            var descriptor = FetchDescriptor<WorkoutEffort>(
                predicate: #Predicate { $0.id == effortID }
            )
            descriptor.fetchLimit = 1
            effort = try? context.fetch(descriptor).first
        }
        if let effort {
            effort.recordedVideoPath = path
            effort.recordedVideoKind = kind
            if set.recordedVideoPath == nil {
                set.recordedVideoPath = path
                set.recordedVideoKind = kind
            } else if set.recordedVideoPath == path {
                set.recordedVideoKind = kind
            }
        } else {
            set.recordedVideoPath = path
            set.recordedVideoKind = kind
        }
        if performance.activeVideoPath == nil {
            performance.activeVideoPath = path
            performance.activeVideoKind = kind
        } else if performance.activeVideoPath == path {
            performance.activeVideoKind = kind
        }
    }

    private func persistSavedRecording(
        _ path: String,
        attempt: WorkoutRecordingAttempt,
        kind: WorkoutRecordingEvidenceKind = .complete
    ) -> Bool {
        guard let sessionID = activeSessionID else { return false }
        let fact = WorkoutRecordingBindingFact(
            sessionID: sessionID,
            attempt: attempt,
            path: path,
            kind: kind
        )
        recordingBindingInbox.upsert(fact)
        pendingRecordings[fact.id] = fact
        guard let context = activeContext else { return false }
        return bindPendingRecording(
            fact,
            sessionID: sessionID,
            in: context
        )
    }

    private func replayPendingRecordingBindings(
        for session: WorkoutSession,
        in context: ModelContext
    ) {
        for fact in Array(pendingRecordings.values)
            where fact.sessionID == session.id
        {
            _ = bindPendingRecording(
                fact,
                sessionID: session.id,
                in: context
            )
        }
    }

    private func bindPendingRecording(
        _ fact: WorkoutRecordingBindingFact,
        sessionID: UUID?,
        in context: ModelContext
    ) -> Bool {
        guard let sessionID, fact.sessionID == sessionID else { return false }
        let factSessionID = fact.sessionID
        let factPerformanceID = fact.attempt.performanceID
        let factSetID = fact.attempt.setID
        var sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == factSessionID }
        )
        sessionDescriptor.fetchLimit = 1
        var performanceDescriptor = FetchDescriptor<ExercisePerformance>(
            predicate: #Predicate { $0.id == factPerformanceID }
        )
        performanceDescriptor.fetchLimit = 1
        var setDescriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.id == factSetID }
        )
        setDescriptor.fetchLimit = 1
        guard let session = try? context.fetch(sessionDescriptor).first,
              let performance = try? context.fetch(performanceDescriptor).first,
              performance.sessionID == session.id,
              performance.session?.id == session.id,
              let set = try? context.fetch(setDescriptor).first,
              set.performanceID == performance.id,
              set.performance?.id == performance.id
        else { return false }
        if let effortID = fact.attempt.effortID {
            var effortDescriptor = FetchDescriptor<WorkoutEffort>(
                predicate: #Predicate { $0.id == effortID }
            )
            effortDescriptor.fetchLimit = 1
            guard let effort = try? context.fetch(effortDescriptor).first,
                  effort.workoutSetID == set.id,
                  effort.workoutSet?.id == set.id
            else { return false }
        }
        persistRecordingPath(
            fact.path,
            attempt: fact.attempt,
            kind: fact.kind,
            to: set,
            performance: performance,
            in: context
        )
        do {
            try saveRecordingBinding(context)
            recordingBindingInbox.remove(attemptID: fact.id)
            pendingRecordings.removeValue(forKey: fact.id)
            clearRecordingFailure(for: fact.id)
            return true
        } catch {
            context.rollback()
            reportRecordingFailure(
                error,
                stage: "bind-saved-video",
                attemptID: fact.id,
                userMessage: "视频已经保存，但尚未绑定到训练记录；Soma 会在下次进入训练时重试。"
            )
            return false
        }
    }

    private func clearRecordingFailure(for _: UUID) {
        recordingErrorMessage = nil
        recordingFailure = nil
    }

    private func reportRecordingFailure(
        _ error: Error,
        stage: String,
        attemptID: UUID,
        logsDiagnostics: Bool = true,
        userMessage: String? = nil
    ) {
        guard reportedRecordingAttemptIDs.insert(attemptID).inserted else {
            return
        }
        let message = userMessage ?? Self.friendlyRecordingError(error)
        recordingErrorMessage = message
        recordingStatusMessage = message
        recordingFailure = WorkoutRecordingFailure(
            id: attemptID,
            message: message
        )
        if logsDiagnostics {
            WorkoutRecordingDiagnostics.failure(
                stage: stage,
                attemptID: attemptID,
                error: error
            )
        }
    }

    private func allSets(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> [WorkoutSet] {
        performances(for: session, in: context).flatMap {
            sets(for: $0, in: context)
        }
    }

    private func resolvedRestTargetEndAt(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> Date? {
        if let target = session.restTargetEndAt {
            return target
        }
        guard let started = session.restStartedAt,
              let set = currentSet(for: session, in: context)
        else {
            return nil
        }
        return started.addingTimeInterval(
            TimeInterval(set.plannedRestSeconds ?? 0)
        )
    }

    private func setPhase(
        _ phase: GuidedWorkoutPhase,
        deadline: Date? = nil,
        for session: WorkoutSession
    ) {
        session.guidedPhase = phase
        session.phaseStartedAt = now()
        session.phaseDeadlineAt = deadline
        session.transitionRevision += 1
    }

    private static func pausedRecordingStatus(
        for session: WorkoutSession
    ) -> String {
        let reason = session.automaticRecordingPauseReason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = reason.flatMap { $0.isEmpty ? nil : $0 }
            .map { "：\($0)" } ?? "。"
        return "自动录像已暂停\(detail) 点击录像可手动重试；成功保存后会恢复自动录像。"
    }

    private static func pauseCode(
        for error: Error
    ) -> WorkoutRecordingPauseCode {
        guard let cameraError = error as? WorkoutCameraError else {
            let nsError = error as NSError
            return nsError.domain == AVFoundationErrorDomain
                ? .interrupted
                : .unknown
        }
        return switch cameraError {
        case .permissionDenied:
            .permissionDenied
        case .frontCameraUnavailable:
            .cameraUnavailable
        case .configurationFailed:
            .configurationFailed
        case .activationTimedOut, .activationSuperseded:
            .activationTimedOut
        case .recordingConnectionUnavailable:
            .connectionUnavailable
        case .insufficientStorage:
            .insufficientStorage
        case .recordingFailed:
            .recordingFailed
        }
    }
}
