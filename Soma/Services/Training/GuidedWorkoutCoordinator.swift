import AVFoundation
import Observation
import SwiftData

@MainActor
@Observable
final class GuidedWorkoutCoordinator {
    struct EffortCompletionLease: Equatable {
        let id: UUID
        let sessionID: UUID
        let effortID: UUID
        let phase: GuidedWorkoutPhase
        let transitionRevision: Int
    }

    var activeSessionID: UUID?
    var activeSessionOwner: WorkoutCameraSessionOwnerToken?
    var lastErrorMessage: String?
    var recordingErrorMessage: String?
    var recordingFailure: WorkoutRecordingFailure?
    var recordingStatusMessage: String?
    var recordingSetID: UUID?
    var isStartingRecording = false
    var manualRecordingQueued = false
    var automaticRecordingPaused = false
    var isCompletingCurrentEffort = false

    @ObservationIgnored let recorder: WorkoutRecordingControlling
    @ObservationIgnored let cues: WorkoutCueProviding
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let recordingBindingInbox:
        WorkoutRecordingBindingInbox
    @ObservationIgnored let saveRecordingBinding:
        @MainActor (ModelContext) throws -> Void
    @ObservationIgnored let materializePerformance:
        @MainActor (
            ExercisePerformance,
            WorkoutSession,
            ModelContext
        ) throws -> WorkoutEntry?
    @ObservationIgnored var activeSessionReference: WorkoutSession?
    @ObservationIgnored var activeContext: ModelContext?
    @ObservationIgnored var recordingRequestID: UUID?
    @ObservationIgnored var activeRecordingAttempt:
        WorkoutRecordingAttempt?
    @ObservationIgnored var pendingRecordings:
        [UUID: WorkoutRecordingBindingFact] = [:]
    @ObservationIgnored var terminalRecordingAttemptIDs = Set<UUID>()
    @ObservationIgnored var reportedRecordingAttemptIDs = Set<UUID>()
    @ObservationIgnored var automaticRecordingAttemptIDs = Set<UUID>()
    @ObservationIgnored var announcedCountdownValues = Set<Int>()
    @ObservationIgnored var activeEffortCompletionLease:
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
