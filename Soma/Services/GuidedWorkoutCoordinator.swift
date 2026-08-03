import AVFoundation
import Observation
import SwiftData
import UIKit

@MainActor
protocol WorkoutRecordingControlling: AnyObject {
    func prepare() async throws
    func startRecording(performanceID: UUID, setID: UUID) async throws
    func stopRecording() async throws -> String?
    func cancelRecording() async
}

@MainActor
final class NoopWorkoutRecordingController: WorkoutRecordingControlling {
    func prepare() async throws {}
    func startRecording(performanceID _: UUID, setID _: UUID) async throws {}
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
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func announce(_ text: String) {
        let isEnabled = defaults.object(
            forKey: "workout.voiceCuesEnabled"
        ) as? Bool ?? true
        guard isEnabled else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.5
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
    private(set) var recordingSetID: UUID?
    private(set) var isStartingRecording = false

    @ObservationIgnored private let recorder: WorkoutRecordingControlling
    @ObservationIgnored private let cues: WorkoutCueProviding
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var recordingRequestID: UUID?
    @ObservationIgnored private var announcedCountdownValues = Set<Int>()

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
        recordingSetID = nil
        isStartingRecording = false
        recordingRequestID = nil
        recordingErrorMessage = nil
        announcedCountdownValues = []
        recover(session, in: context)
    }

    func introduceCurrentExercise(
        in context: ModelContext
    ) throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context) else {
            session.guidedPhase = .sessionReview
            try context.save()
            return
        }
        setPhase(.exerciseIntroduction, for: session)
        cues.announce("接下来，\(performance.exerciseName)")
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
        announcedCountdownValues = []
        cues.announce("准备第 \(set.order) 组")
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
        guard let performance = currentPerformance(for: session, in: context),
              let set = currentSet(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingSet
        }
        set.status = .inProgress
        set.startedAt = now()
        setPhase(.setInProgress, for: session)
        cues.announce("开始第 \(set.order) 组")
        try context.save()

        if shouldRecord(
            set: set,
            performance: performance,
            session: session
        ) {
            await startRecording(for: performance, set: set)
        }
    }

    func startManualRecording(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        guard session.guidedPhase == .setInProgress,
              let performance = currentPerformance(for: session, in: context),
              let set = currentSet(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingSet
        }
        guard recordingSetID == nil, !isStartingRecording else { return }
        await startRecording(for: performance, set: set)
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
        if isStartingRecording {
            clearRecordingState()
            await recorder.cancelRecording()
        }
        if recordingSetID == set.id {
            do {
                if let path = try await recorder.stopRecording() {
                    set.recordedVideoPath = path
                    if performance.activeVideoPath == nil {
                        performance.activeVideoPath = path
                    }
                }
                recordingErrorMessage = nil
            } catch {
                recordingErrorMessage = error.localizedDescription
            }
            recordingSetID = nil
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
        clearRecordingState()
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

    func redoCurrentSet(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        guard let set = currentSet(for: session, in: context) else {
            throw GuidedWorkoutError.missingSet
        }
        await recorder.cancelRecording()
        clearRecordingState()
        set.status = .pending
        set.startedAt = nil
        set.completedAt = nil
        set.actualReps = nil
        set.actualWeightKG = nil
        set.actualRestSeconds = nil
        setPhase(.preSetCountdown, for: session)
        try context.save()
    }

    func skipCurrentExercise(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context)
        else {
            throw GuidedWorkoutError.missingPerformance
        }
        await recorder.cancelRecording()
        clearRecordingState()
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
        session.restTargetEndAt = nil
        setPhase(.preSetCountdown, for: session)
        announcedCountdownValues = []
        if let set = currentSet(for: session, in: context) {
            cues.announce("准备第 \(set.order) 组")
        }
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

    func pause(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        await recorder.cancelRecording()
        clearRecordingState()
        session.status = .paused
        cues.announce("训练已暂停")
        try context.save()
    }

    func resume(in context: ModelContext) throws {
        let session = try activeSession(in: context)
        session.status = .active
        recover(session, in: context)
        cues.announce("继续训练")
    }

    func endEarly(in context: ModelContext) async throws {
        let session = try activeSession(in: context)
        await recorder.cancelRecording()
        clearRecordingState()
        session.status = .abandoned
        session.endedAt = now()
        session.restTargetEndAt = nil
        session.autoRecordingPolicy = .cancelled
        activeSessionID = nil
        cues.announce("训练已提前结束")
        try context.save()
    }

    func complete(in context: ModelContext) throws {
        let session = try activeSession(in: context)
        session.status = .completed
        session.guidedPhase = .completed
        session.endedAt = now()
        session.restTargetEndAt = nil
        activeSessionID = nil
        try context.save()
    }

    func setRecordingPolicy(
        _ policy: AutoRecordingPolicy,
        in context: ModelContext
    ) async throws {
        let session = try activeSession(in: context)
        session.autoRecordingPolicy = policy
        if !policy.usesAutomaticRecording {
            await recorder.cancelRecording()
            clearRecordingState()
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
            session.restTargetEndAt = now().addingTimeInterval(
                TimeInterval(pending.plannedRestSeconds ?? 0)
            )
            setPhase(.resting, for: session)
            announcedCountdownValues = []
            cues.announce(
                set.status == .skipped
                    ? "已跳过第 \(set.order) 组，休息 \(pending.plannedRestSeconds ?? 0) 秒"
                    : "第 \(set.order) 组完成，休息 \(pending.plannedRestSeconds ?? 0) 秒"
            )
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
            session.restTargetEndAt = nil
            setPhase(.exerciseIntroduction, for: session)
            cues.announce("接下来，\(next.exerciseName)")
        } else {
            session.currentPerformanceID = nil
            session.currentSetID = nil
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
        guard set.recordedVideoPath == nil else { return false }
        if session.autoRecordingPolicy == .everySet {
            return true
        }
        guard session.autoRecordingPolicy == .enabled,
              let prescription = performance.prescriptionSnapshot
        else { return false }
        let target = prescription.firstSetIsWarmup ? 2 : 1
        return set.order == target
    }

    private func startRecording(
        for performance: ExercisePerformance,
        set: WorkoutSet
    ) async {
        guard recordingSetID == nil, !isStartingRecording else { return }
        let requestID = UUID()
        recordingRequestID = requestID
        isStartingRecording = true
        do {
            try await recorder.prepare()
            guard recordingRequestID == requestID else { return }
            try await recorder.startRecording(
                performanceID: performance.id,
                setID: set.id
            )
            guard recordingRequestID == requestID else {
                await recorder.cancelRecording()
                return
            }
            recordingSetID = set.id
            recordingErrorMessage = nil
        } catch {
            if recordingRequestID == requestID {
                recordingSetID = nil
                recordingErrorMessage = error.localizedDescription
            }
        }
        if recordingRequestID == requestID {
            recordingRequestID = nil
            isStartingRecording = false
        }
    }

    private func clearRecordingState() {
        recordingSetID = nil
        isStartingRecording = false
        recordingRequestID = nil
    }

    private func allSets(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> [WorkoutSet] {
        let performanceIDs = Set(
            performances(for: session, in: context).map(\.id)
        )
        return ((try? context.fetch(FetchDescriptor<WorkoutSet>())) ?? [])
            .filter { performanceIDs.contains($0.performanceID) }
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
