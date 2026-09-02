import AVFoundation
import Observation
import SwiftData

@MainActor
extension GuidedWorkoutCoordinator {
    func normalizeQueuedRecording(
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

    func canonicalPendingRecordingEffort(
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

    func clearQueuedRecording(for session: WorkoutSession) {
        session.queuedRecordingEffortID = nil
        manualRecordingQueued = false
    }

    func prepareQueuedRecording(for effortID: UUID) async {
        let requestID = UUID()
        recordingRequestID = requestID
        isStartingRecording = true
        recordingErrorMessage = nil
        recordingStatusMessage = "正在启动相机，为下一组录像做准备…"
        do {
            try await recorder.prepare()
            guard recordingRequestID == requestID else { return }
            guard let context = activeContext,
                  let session = try? activeSession(in: context),
                  session.queuedRecordingEffortID == effortID
            else {
                clearRecordingState()
                return
            }
            recordingStatusMessage = automaticRecordingPaused
                ? "相机已就绪，下一组将手动录像；保存后会恢复自动录像。"
                : "相机已就绪，下一组将自动开始录像。"
        } catch {
            guard recordingRequestID == requestID else { return }
            if let context = activeContext,
               let session = try? activeSession(in: context)
            {
                session.queuedRecordingEffortID = nil
                try? context.save()
            }
            manualRecordingQueued = false
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

    func prepareAutomaticRecording() async {
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

    func nextAutomaticRecordingEffortID(
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

    func updateAutomaticRecordingPaused(
        _ value: Bool,
        code: WorkoutRecordingPauseCode? = nil,
        reason: String? = nil
    ) {
        automaticRecordingPaused = value
        let session = activeContext.flatMap { try? activeSession(in: $0) }
        session?.automaticRecordingPaused = value
        if value {
            session?.automaticRecordingPauseCode = code ?? .unknown
            session?.automaticRecordingPauseReason = reason
            recordingStatusMessage = session.map(
                Self.pausedRecordingStatus(for:)
            )
        } else {
            session?.automaticRecordingPauseCode = nil
            session?.automaticRecordingPauseReason = nil
        }
        try? activeContext?.save()
    }

    func pauseAutomaticRecording(for error: Error) {
        updateAutomaticRecordingPaused(
            true,
            code: Self.pauseCode(for: error),
            reason: Self.friendlyRecordingError(error)
        )
    }

    func beginCountdown(
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

    func startRestOrCountdown(
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

    func persistCompletedRest(
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

    func aggregate(
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

    func elapsedDuration(for effort: WorkoutEffort) -> Int? {
        guard let startedAt = effort.startedAt else {
            return effort.plannedDurationSeconds
        }
        return max(Int(now().timeIntervalSince(startedAt).rounded()), 0)
    }

    func shouldRecord(
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

    func releaseCameraIfNotNeeded(in context: ModelContext) async {
        guard recordingSetID == nil, !isStartingRecording else { return }
        guard !shouldCaptureCurrentEffort(in: context) else { return }
        recordingStatusMessage = nil
        await recorder.idlePreviewKeepingSessionOwner()
    }

    /// 快照从倒计时切换到执行态时，SwiftUI 会取消原倒计时 `.task`。
    /// 录像启动必须由协调器独立持有，否则父任务的取消会触发相机服务的
    /// cancellation handler，导致第一组只显示取景却没有真正开始写文件。
    func startRecordingAfterPhaseTransition(
        sessionID: UUID,
        performanceID: UUID,
        setID: UUID,
        effortID: UUID,
        previousPreviewHostID: UUID?,
        automatic: Bool
    ) async {
        cancelPendingPhaseRecordingStart()
        let requestID = UUID()
        phaseRecordingStartID = requestID
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await recorder.waitUntilPreviewHostSettled(
                from: previousPreviewHostID
            )
            guard !Task.isCancelled,
                  phaseRecordingStartID == requestID,
                  activeSessionID == sessionID,
                  let context = activeContext,
                  let session = try? activeSession(in: context),
                  session.id == sessionID,
                  session.status == .active,
                  session.guidedPhase == .setInProgress,
                  let performance = currentPerformance(
                      for: session,
                      in: context
                  ),
                  performance.id == performanceID,
                  let set = currentSet(for: session, in: context),
                  set.id == setID,
                  set.status == .inProgress,
                  let effort = currentEffort(for: session, in: context),
                  effort.id == effortID,
                  effort.status == .inProgress
            else { return }
            await startRecording(
                for: performance,
                set: set,
                effortID: effortID,
                automatic: automatic
            )
        }
        phaseRecordingStartTask = task
        await task.value
        if phaseRecordingStartID == requestID {
            phaseRecordingStartTask = nil
            phaseRecordingStartID = nil
        }
    }

    func cancelPendingPhaseRecordingStart() {
        phaseRecordingStartTask?.cancel()
        phaseRecordingStartTask = nil
        phaseRecordingStartID = nil
    }

    func startRecording(
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

    func cancelActiveRecording() async {
        cancelPendingPhaseRecordingStart()
        let attempt = activeRecordingAttempt
        if let attempt {
            finishRecordingState(for: attempt)
        } else {
            clearRecordingState()
        }
        await recorder.cancelRecording(attemptID: attempt?.id)
    }

    func finishActiveRecording(
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

    func handleRecordingEvent(_ event: WorkoutRecordingAttemptEvent) {
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
                ? activeContext
                .flatMap { try? activeSession(in: $0) }
                .map(Self.pausedRecordingStatus(for:))
                : nil
        }
    }

    func finishRecordingState(for attempt: WorkoutRecordingAttempt) {
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

    func clearRecordingState() {
        recordingSetID = nil
        isStartingRecording = false
        recordingRequestID = nil
        activeRecordingAttempt = nil
        recordingStatusMessage = automaticRecordingPaused
            ? activeContext
            .flatMap { try? activeSession(in: $0) }
            .map(Self.pausedRecordingStatus(for:))
            : nil
    }

    func applyPendingRecordings(
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

    func persistRecordingPath(
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

    func persistSavedRecording(
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

    func replayPendingRecordingBindings(
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

    func bindPendingRecording(
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

    func clearRecordingFailure(for _: UUID) {
        recordingErrorMessage = nil
        recordingFailure = nil
    }

    func reportRecordingFailure(
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
}
