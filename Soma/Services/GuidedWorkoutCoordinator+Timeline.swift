import AVFoundation
import Observation
import SwiftData

@MainActor
extension GuidedWorkoutCoordinator {
    func recover(
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

    func advanceAfterEffort(
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

    func advanceAfterPerformance(
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

    func activeSession(
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

    func currentPerformance(
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

    func currentSet(
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

    func currentEffort(
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

    func firstPendingSet(
        for performance: ExercisePerformance,
        in context: ModelContext
    ) -> WorkoutSet? {
        sets(for: performance, in: context).first { $0.status == .pending }
    }

    func performances(
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

    func sets(
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

    func efforts(
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

    func firstPendingEffort(
        for set: WorkoutSet,
        in context: ModelContext
    ) -> WorkoutEffort? {
        efforts(for: set, in: context).first { $0.status == .pending }
    }

    func queueableEffort(
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

    func allSets(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> [WorkoutSet] {
        performances(for: session, in: context).flatMap {
            sets(for: $0, in: context)
        }
    }

    func resolvedRestTargetEndAt(
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

    func setPhase(
        _ phase: GuidedWorkoutPhase,
        deadline: Date? = nil,
        for session: WorkoutSession
    ) {
        session.guidedPhase = phase
        session.phaseStartedAt = now()
        session.phaseDeadlineAt = deadline
        session.transitionRevision += 1
    }

    static func pausedRecordingStatus(
        for session: WorkoutSession
    ) -> String {
        let reason = session.automaticRecordingPauseReason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = reason.flatMap { $0.isEmpty ? nil : $0 }
            .map { "：\($0)" } ?? "。"
        return "自动录像已暂停\(detail) 点击录像可手动重试；成功保存后会恢复自动录像。"
    }

    static func pauseCode(
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
