import AVFoundation
import Observation
import SwiftData
import UIKit

@MainActor
protocol WorkoutRecordingControlling: AnyObject {
    func prepare() async throws
    func startRecording(performanceID: UUID) async throws
    func stopRecording() async throws -> String?
    func cancelRecording() async
}

@MainActor
final class NoopWorkoutRecordingController: WorkoutRecordingControlling {
    func prepare() async throws {}
    func startRecording(performanceID _: UUID) async throws {}
    func stopRecording() async throws -> String? {
        nil
    }

    func cancelRecording() async {}
}

@MainActor
protocol WorkoutCueProviding {
    func announce(_ text: String)
    func success()
}

@MainActor
final class SystemWorkoutCueProvider: WorkoutCueProviding {
    private let synthesizer = AVSpeechSynthesizer()

    func announce(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        synthesizer.speak(utterance)
    }

    func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

@MainActor
@Observable
final class GuidedWorkoutCoordinator {
    private(set) var activeSessionID: UUID?
    private(set) var lastErrorMessage: String?
    private(set) var recordingErrorMessage: String?

    @ObservationIgnored private let recorder: WorkoutRecordingControlling
    @ObservationIgnored private let cues: WorkoutCueProviding
    @ObservationIgnored private let now: () -> Date

    init(
        recorder: WorkoutRecordingControlling,
        cues: WorkoutCueProviding,
        now: @escaping () -> Date = Date.init
    ) {
        self.recorder = recorder
        self.cues = cues
        self.now = now
    }

    convenience init() {
        self.init(
            recorder: NoopWorkoutRecordingController(),
            cues: SystemWorkoutCueProvider()
        )
    }

    func activate(
        _ session: WorkoutSession,
        in context: ModelContext
    ) async {
        activeSessionID = session.id
        recover(session, in: context)
        if session.autoRecordingPolicy == .enabled {
            do {
                try await recorder.prepare()
            } catch {
                recordingErrorMessage = error.localizedDescription
            }
        }
    }

    func introduceCurrentExercise(
        in context: ModelContext
    ) throws {
        let session = try activeSession(in: context)
        guard currentPerformance(for: session, in: context) != nil else {
            session.guidedPhase = .sessionReview
            try context.save()
            return
        }
        setPhase(.exerciseIntroduction, for: session)
        try context.save()
    }

    func prepareCurrentSet(
        in context: ModelContext
    ) throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context),
              let set = firstPendingSet(
                  for: performance,
                  in: context
              )
        else {
            try advanceAfterPerformance(session, in: context)
            return
        }
        performance.status = .active
        session.currentSetID = set.id
        setPhase(.preSetCountdown, for: session)
        cues.announce("准备第 \(set.order) 组")
        try context.save()
    }

    func beginCurrentSet(
        in context: ModelContext
    ) async throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context),
              let set = currentSet(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingSet
        }
        set.status = .inProgress
        set.startedAt = now()
        setPhase(.setInProgress, for: session)
        try context.save()

        if shouldRecord(
            set: set,
            performance: performance,
            session: session
        ) {
            do {
                try await recorder.startRecording(performanceID: performance.id)
                recordingErrorMessage = nil
            } catch {
                recordingErrorMessage = error.localizedDescription
            }
        }
    }

    func requestSetConfirmation(
        in context: ModelContext
    ) throws {
        let session = try activeSession(in: context)
        guard currentSet(for: session, in: context) != nil else {
            throw GuidedWorkoutError.missingSet
        }
        setPhase(.setConfirmation, for: session)
        try context.save()
    }

    func confirmCurrentSet(
        actualReps: Int?,
        actualWeightKG: Double?,
        in context: ModelContext
    ) async throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context),
              let set = currentSet(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingSet
        }
        let wasRecording = shouldRecord(
            set: set,
            performance: performance,
            session: session
        )
        if wasRecording {
            do {
                if let path = try await recorder.stopRecording() {
                    performance.activeVideoPath = path
                }
                recordingErrorMessage = nil
            } catch {
                recordingErrorMessage = error.localizedDescription
            }
        }
        set.actualReps = actualReps
        set.actualWeightKG = actualWeightKG
        set.status = .completed
        set.completedAt = now()
        cues.success()
        try advanceAfterSet(
            set,
            performance: performance,
            session: session,
            in: context
        )
        try context.save()
    }

    func skipCurrentSet(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context),
              let set = currentSet(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingSet
        }
        await recorder.cancelRecording()
        set.status = .skipped
        set.completedAt = now()
        try advanceAfterSet(
            set,
            performance: performance,
            session: session,
            in: context
        )
        try context.save()
    }

    func skipCurrentExercise(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingPerformance
        }
        await recorder.cancelRecording()
        for set in sets(for: performance, in: context)
            where set.status == .pending || set.status == .inProgress
        {
            set.status = .skipped
            set.completedAt = now()
        }
        performance.status = .skipped
        try advanceAfterPerformance(session, in: context)
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
        if let startedAt = session.restStartedAt,
           let set = currentSet(for: session, in: context)
        {
            set.actualRestSeconds = max(
                Int(now().timeIntervalSince(startedAt)),
                0
            )
        }
        session.restStartedAt = nil
        setPhase(.preSetCountdown, for: session)
        try context.save()
    }

    func remainingRestSeconds(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> Int {
        guard session.guidedPhase == .resting,
              let started = session.restStartedAt,
              let set = currentSet(for: session, in: context)
        else {
            return 0
        }
        let planned = set.plannedRestSeconds ?? 0
        return max(planned - Int(now().timeIntervalSince(started)), 0)
    }

    func pause(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        await recorder.cancelRecording()
        session.status = .paused
        try context.save()
    }

    func resume(in context: ModelContext) throws {
        let session = try activeSession(in: context)
        session.status = .active
        recover(session, in: context)
    }

    func endEarly(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        await recorder.cancelRecording()
        session.status = .abandoned
        session.endedAt = now()
        session.autoRecordingPolicy = .cancelled
        activeSessionID = nil
        try context.save()
    }

    func complete(in context: ModelContext) throws {
        let session = try activeSession(in: context)
        session.status = .completed
        session.guidedPhase = .completed
        session.endedAt = now()
        activeSessionID = nil
        try context.save()
    }

    func setRecordingPolicy(
        _ policy: AutoRecordingPolicy,
        in context: ModelContext
    ) async throws {
        let session = try activeSession(in: context)
        session.autoRecordingPolicy = policy
        if policy != .enabled {
            await recorder.cancelRecording()
        }
        try context.save()
    }

    private func recover(
        _ session: WorkoutSession,
        in context: ModelContext
    ) {
        if let set = currentSet(for: session, in: context),
           set.status == .inProgress
        {
            session.guidedPhase = .setConfirmation
        }
        if session.status == .paused {
            session.status = .active
        }
        try? context.save()
    }

    private func advanceAfterSet(
        _ set: WorkoutSet,
        performance: ExercisePerformance,
        session: WorkoutSession,
        in context: ModelContext
    ) throws {
        let pending = sets(for: performance, in: context)
            .first { $0.status == .pending }
        if let pending {
            session.currentSetID = pending.id
            session.restStartedAt = now()
            setPhase(.resting, for: session)
        } else {
            performance.status = .completed
            try advanceAfterPerformance(session, in: context)
        }
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
            session.restStartedAt = nil
            setPhase(.exerciseIntroduction, for: session)
        } else {
            session.currentPerformanceID = nil
            session.currentSetID = nil
            setPhase(.sessionReview, for: session)
        }
    }

    private func activeSession(
        in context: ModelContext
    ) throws -> WorkoutSession {
        guard let activeSessionID,
              let session = (
                  try? context.fetch(FetchDescriptor<WorkoutSession>())
              )?.first(where: { $0.id == activeSessionID }),
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
        return performances(for: session, in: context).first { $0.id == id }
    }

    private func currentSet(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> WorkoutSet? {
        guard let id = session.currentSetID else { return nil }
        return (
            try? context.fetch(FetchDescriptor<WorkoutSet>())
        )?.first { $0.id == id }
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
        (
            try? context.fetch(FetchDescriptor<ExercisePerformance>())
        )?.filter { $0.sessionID == session.id }
            .sorted { $0.order < $1.order } ?? []
    }

    private func sets(
        for performance: ExercisePerformance,
        in context: ModelContext
    ) -> [WorkoutSet] {
        (
            try? context.fetch(FetchDescriptor<WorkoutSet>())
        )?.filter { $0.performanceID == performance.id }
            .sorted { $0.order < $1.order } ?? []
    }

    private func shouldRecord(
        set: WorkoutSet,
        performance: ExercisePerformance,
        session: WorkoutSession
    ) -> Bool {
        guard session.autoRecordingPolicy == .enabled,
              performance.activeVideoPath == nil,
              let prescription = performance.prescriptionSnapshot
        else {
            return false
        }
        let target = prescription.firstSetIsWarmup ? 2 : 1
        return set.order == target
    }

    private func setPhase(
        _ phase: GuidedWorkoutPhase,
        for session: WorkoutSession
    ) {
        session.guidedPhase = phase
        session.phaseStartedAt = now()
    }
}

enum GuidedWorkoutError: LocalizedError {
    case missingSession
    case missingPerformance
    case missingSet

    var errorDescription: String? {
        switch self {
        case .missingSession:
            "没有可继续的训练。"
        case .missingPerformance:
            "当前动作不存在。"
        case .missingSet:
            "当前训练组不存在。"
        }
    }
}
