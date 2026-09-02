import AVFoundation
import Foundation
import SwiftData
import UIKit

@MainActor
protocol WorkoutCueProviding {
    func announce(_ text: String)
    func success()
}

struct WorkoutRecordingFailure: Equatable, Identifiable, Sendable {
    let id: UUID
    let message: String

    init(id: UUID = UUID(), message: String) {
        self.id = id
        self.message = message
    }
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

struct WorkoutRecordingAttempt: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let performanceID: UUID
    let setID: UUID
    let effortID: UUID?

    init(
        id: UUID = UUID(),
        performanceID: UUID,
        setID: UUID,
        effortID: UUID? = nil
    ) {
        self.id = id
        self.performanceID = performanceID
        self.setID = setID
        self.effortID = effortID
    }
}

enum WorkoutRecordingAttemptEvent {
    case started(WorkoutRecordingAttempt)
    case saved(WorkoutRecordingAttempt, path: String)
    case savedPartial(
        WorkoutRecordingAttempt,
        path: String,
        message: String
    )
    case failed(WorkoutRecordingAttempt, Error)
    case cancelled(WorkoutRecordingAttempt)
}

struct WorkoutRecordingBindingFact: Codable, Equatable, Identifiable {
    let sessionID: UUID
    let attempt: WorkoutRecordingAttempt
    let path: String
    let kind: WorkoutRecordingEvidenceKind

    init(
        sessionID: UUID,
        attempt: WorkoutRecordingAttempt,
        path: String,
        kind: WorkoutRecordingEvidenceKind = .complete
    ) {
        self.sessionID = sessionID
        self.attempt = attempt
        self.path = path
        self.kind = kind
    }

    var id: UUID {
        attempt.id
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case attempt
        case path
        case kind
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try values.decode(UUID.self, forKey: .sessionID)
        attempt = try values.decode(WorkoutRecordingAttempt.self, forKey: .attempt)
        path = try values.decode(String.self, forKey: .path)
        kind = try values.decodeIfPresent(
            WorkoutRecordingEvidenceKind.self,
            forKey: .kind
        ) ?? .complete
    }
}

@MainActor
final class WorkoutRecordingBindingInbox {
    private static let storageKey = "guidedWorkout.recordingBindings.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func facts(for sessionID: UUID) -> [WorkoutRecordingBindingFact] {
        allFacts().filter { $0.sessionID == sessionID }
    }

    func upsert(_ fact: WorkoutRecordingBindingFact) {
        var facts = allFacts().filter { $0.id != fact.id }
        facts.append(fact)
        persist(facts)
    }

    func remove(attemptID: UUID) {
        persist(allFacts().filter { $0.id != attemptID })
    }

    private func allFacts() -> [WorkoutRecordingBindingFact] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let facts = try? JSONDecoder().decode(
                  [WorkoutRecordingBindingFact].self,
                  from: data
              )
        else { return [] }
        return facts
    }

    private func persist(_ facts: [WorkoutRecordingBindingFact]) {
        if facts.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(facts) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

@MainActor
protocol WorkoutRecordingControlling: AnyObject {
    var recordingEventHandler: ((WorkoutRecordingAttemptEvent) -> Void)? {
        get set
    }

    func claimWorkoutSession(
        sessionID: UUID
    ) -> WorkoutCameraSessionOwnerToken
    func endWorkoutSession(owner: WorkoutCameraSessionOwnerToken) async
    func prepare() async throws
    var previewHostID: UUID? { get }
    func waitUntilPreviewHostSettled(from previousHostID: UUID?) async
    func idlePreviewKeepingSessionOwner() async
    func startRecording(attempt: WorkoutRecordingAttempt) async throws
    func stopRecording(attemptID: UUID) async throws -> String?
    func cancelRecording(attemptID: UUID?) async
}

extension WorkoutRecordingControlling {
    func claimWorkoutSession(
        sessionID: UUID
    ) -> WorkoutCameraSessionOwnerToken {
        WorkoutCameraSessionOwnerToken(
            sessionID: sessionID,
            generation: UUID()
        )
    }

    func endWorkoutSession(owner _: WorkoutCameraSessionOwnerToken) async {
        await cancelRecording(attemptID: nil)
    }

    var previewHostID: UUID? {
        nil
    }

    func waitUntilPreviewHostSettled(from _: UUID?) async {}

    func idlePreviewKeepingSessionOwner() async {}
}

@MainActor
final class NoopWorkoutRecordingController: WorkoutRecordingControlling {
    var recordingEventHandler: ((WorkoutRecordingAttemptEvent) -> Void)?

    func prepare() async throws {}
    func startRecording(attempt _: WorkoutRecordingAttempt) async throws {}
    func stopRecording(attemptID _: UUID) async throws -> String? {
        nil
    }

    func cancelRecording(attemptID _: UUID?) async {}
}

@MainActor
enum GuidedWorkoutRecordStore {
    @discardableResult
    static func materialize(
        performanceID: UUID,
        sessionID: UUID,
        in context: ModelContext
    ) throws -> WorkoutEntry? {
        var sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        sessionDescriptor.fetchLimit = 1
        guard let session = try context.fetch(sessionDescriptor).first else {
            throw GuidedWorkoutError.missingSession
        }
        var performanceDescriptor = FetchDescriptor<ExercisePerformance>(
            predicate: #Predicate { $0.id == performanceID }
        )
        performanceDescriptor.fetchLimit = 1
        guard let performance = try context.fetch(performanceDescriptor).first,
              performance.sessionID == sessionID
        else {
            throw GuidedWorkoutError.missingPerformance
        }
        return try materialize(
            performance: performance,
            session: session,
            in: context
        )
    }

    @discardableResult
    static func materialize(
        performance: ExercisePerformance,
        session: WorkoutSession,
        in context: ModelContext
    ) throws -> WorkoutEntry? {
        guard !performance.workoutProjectionSuppressed else { return nil }
        let projectionKey = SomaDataMigration.projectionKey(for: performance.id)
        let performanceID = performance.id
        var existingDescriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate {
                $0.projectionKey == projectionKey
                    || $0.sourcePerformanceID == performanceID
            }
        )
        existingDescriptor.fetchLimit = 1
        let fetchedExisting = try context.fetch(existingDescriptor).first
        let exerciseID = performance.exerciseID
        var definitionDescriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.id == exerciseID }
        )
        definitionDescriptor.fetchLimit = 1
        guard let definition = try context.fetch(definitionDescriptor).first else {
            throw TrainingPlanError.missingExercise(exerciseID)
        }
        if let existing = fetchedExisting {
            existing.projectionKey = projectionKey
            existing.exercise = performance.exerciseName
            existing.exerciseID = performance.exerciseID
            existing.exerciseDefinition = definition
            existing.sourceWorkoutSessionID = session.id
            existing.sourcePerformanceID = performance.id
            existing.sourcePerformance = performance
            performance.exerciseDefinition = definition
            performance.projectedWorkout = existing
            if existing.businessID == nil {
                try BusinessIDAllocator.assign(
                    existing,
                    namespace: "workout",
                    in: context
                )
            }
            WorkoutCalorieCalculator.refreshStoredEstimate(existing, in: context)
            return existing
        }

        let sets = try context.fetch(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.performanceID == performanceID },
            sortBy: [SortDescriptor(\.order)]
        ))
        guard !sets.isEmpty,
              sets.allSatisfy({
                  $0.status == .completed
                      || $0.status == .partial
                      || $0.status == .skipped
                      || $0.status == .failed
              })
        else {
            return nil
        }

        var efforts: [WorkoutEffort] = []
        for set in sets {
            let setID = set.id
            try efforts.append(contentsOf: context.fetch(
                FetchDescriptor<WorkoutEffort>(
                    predicate: #Predicate { $0.workoutSetID == setID },
                    sortBy: [SortDescriptor(\.order)]
                )
            ))
        }
        let usesEffortEvidence = efforts.contains { $0.status != .pending }
        if usesEffortEvidence,
           !efforts.allSatisfy({
               $0.status == .completed
                   || $0.status == .skipped
                   || $0.status == .failed
           })
        {
            return nil
        }

        let completed = sets.filter {
            $0.status == .completed || $0.status == .partial
        }
        let completedEfforts = efforts.filter { $0.status == .completed }
        guard !completed.isEmpty || !completedEfforts.isEmpty else { return nil }

        let setByID = Dictionary(uniqueKeysWithValues: sets.map { ($0.id, $0) })
        let orderedCompletedEfforts = completedEfforts
            .sorted { lhs, rhs in
                let lhsSetOrder = setByID[lhs.workoutSetID]?.order ?? .max
                let rhsSetOrder = setByID[rhs.workoutSetID]?.order ?? .max
                return lhsSetOrder == rhsSetOrder
                    ? lhs.order < rhs.order
                    : lhsSetOrder < rhsSetOrder
            }
        var effortEvidence = orderedCompletedEfforts.map { effort in
            let set = setByID[effort.workoutSetID]
            return WorkoutSetEvidence(
                logicalSetIndex: set?.order,
                side: effort.side,
                kind: set?.kind,
                targetKind: effort.targetKind,
                reps: validReps(effort.actualReps),
                durationSeconds: validDuration(effort.actualDurationSeconds),
                externalWeightKG: validWeight(effort.actualWeightKG),
                restSeconds: validRest(effort.actualRestSeconds),
                recordedVideoPath: effort.recordedVideoPath,
                recordedVideoKind: effort.recordedVideoKind
            )
        }
        // A side may be skipped or fail after the user has already rested.
        // Preserve that actual elapsed rest on the next completed side in the
        // same logical set without fabricating exercise evidence for the failed side.
        for effort in efforts where effort.status != .completed {
            guard let rest = validRest(effort.actualRestSeconds),
                  let targetIndex = orderedCompletedEfforts.firstIndex(where: {
                      $0.workoutSetID == effort.workoutSetID
                          && $0.order > effort.order
                  })
            else {
                continue
            }
            effortEvidence[targetIndex].restSeconds =
                (effortEvidence[targetIndex].restSeconds ?? 0) + rest
        }
        let legacyEvidence = completed.map { set in
            WorkoutSetEvidence(
                logicalSetIndex: set.order,
                side: WorkoutEffortSide(rawValue: set.laterality ?? "")
                    ?? WorkoutEffortSide.none,
                kind: set.kind,
                targetKind: set.plannedTargetKind,
                reps: validReps(set.actualReps),
                durationSeconds: validDuration(set.actualDurationSeconds),
                externalWeightKG: validWeight(set.actualWeightKG),
                restSeconds: validRest(set.actualRestSeconds),
                recordedVideoPath: set.recordedVideoPath,
                recordedVideoKind: set.recordedVideoKind
            )
        }
        var evidence = usesEffortEvidence ? effortEvidence : legacyEvidence
        guard !evidence.isEmpty else { return nil }
        if usesEffortEvidence {
            for set in completed {
                guard let rest = set.actualRestSeconds,
                      rest >= 0,
                      let index = evidence.lastIndex(where: {
                          $0.logicalSetIndex == set.order
                      })
                else {
                    continue
                }
                evidence[index].restSeconds = (evidence[index].restSeconds ?? 0) + rest
            }
        }
        let calorieEstimate = WorkoutCalorieCalculator.estimateGuidedWorkout(
            exercise: performance.exerciseName,
            evidence: evidence,
            weightKG: WorkoutCalorieCalculator.latestRecordedWeight(
                at: session.startedAt,
                in: context
            )
        )

        let attachments = stableVideoAttachments(
            evidence.compactMap(\.recordedVideoPath)
                + completed.compactMap(\.recordedVideoPath)
                + [performance.activeVideoPath].compactMap { $0 }
        )
        let entry = WorkoutEntry(
            date: session.startedAt,
            exercise: performance.exerciseName,
            exerciseID: performance.exerciseID,
            setEntries: evidence,
            restSeconds: uniform(evidence.compactMap(\.restSeconds), count: evidence.count),
            notes: performance.notes,
            mediaAttachments: attachments,
            estimatedCalories: calorieEstimate?.calories,
            calorieMET: calorieEstimate?.met,
            calorieDurationMinutes: calorieEstimate?.durationMinutes,
            calorieDurationEstimated: calorieEstimate?.durationWasEstimated ?? false,
            sourceWorkoutSessionID: session.id,
            sourcePerformanceID: performance.id,
            projectionKey: projectionKey
        )
        entry.exerciseDefinition = definition
        entry.sourcePerformance = performance
        performance.exerciseDefinition = definition
        performance.projectedWorkout = entry
        context.insert(entry)
        try BusinessIDAllocator.assign(entry, namespace: "workout", in: context)
        return entry
    }

    static func delete(
        _ workout: WorkoutEntry,
        in context: ModelContext
    ) throws {
        if let performanceID = workout.sourcePerformanceID {
            var descriptor = FetchDescriptor<ExercisePerformance>(
                predicate: #Predicate { $0.id == performanceID }
            )
            descriptor.fetchLimit = 1
            if let performance = try context.fetch(descriptor).first {
                performance.workoutProjectionSuppressed = true
                performance.projectedWorkout = nil
            }
        }
        workout.sourcePerformance = nil
        context.delete(workout)
        try context.save()
    }

    private static func validReps(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func validWeight(_ value: Double?) -> Double? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private static func validDuration(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func validRest(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private static func uniform<T: Hashable>(
        _ values: [T],
        count: Int
    ) -> T? {
        guard values.count == count, Set(values).count == 1 else { return nil }
        return values.first
    }

    private static func stableVideoAttachments(
        _ paths: [String]
    ) -> [MediaAttachmentReference] {
        var seen = Set<String>()
        return paths.compactMap { path in
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return MediaAttachmentReference(kind: .video, path: path)
        }
    }
}
