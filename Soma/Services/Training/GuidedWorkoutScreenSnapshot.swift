import Foundation
import SwiftData

struct GuidedWorkoutSessionSnapshot: Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let statusRaw: String
    let guidedPhaseRaw: String
    let currentPerformanceID: UUID?
    let currentSetID: UUID?
    let currentEffortID: UUID?
    let phaseStartedAt: Date?
    let phaseDeadlineAt: Date?
    let transitionRevision: Int
    let restTargetEndAt: Date?
    let autoRecordingPolicyRaw: String
    let queuedRecordingEffortID: UUID?
    let automaticRecordingPaused: Bool

    var status: WorkoutSessionStatus {
        WorkoutSessionStatus(rawValue: statusRaw) ?? .draft
    }

    var guidedPhase: GuidedWorkoutPhase {
        GuidedWorkoutPhase(rawValue: guidedPhaseRaw) ?? .ready
    }

    var autoRecordingPolicy: AutoRecordingPolicy {
        AutoRecordingPolicy(rawValue: autoRecordingPolicyRaw) ?? .disabled
    }
}

struct GuidedWorkoutPerformanceSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let exerciseID: UUID
    let exerciseName: String
    let order: Int
    let statusRaw: String
    let prescription: TemplateExercisePrescription?
    let artwork: ExerciseImageReference
    let coachingNotes: String

    var status: ExercisePerformanceStatus {
        ExercisePerformanceStatus(rawValue: statusRaw) ?? .pending
    }
}

struct GuidedWorkoutSetSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let performanceID: UUID
    let order: Int
    let kindRaw: String
    let statusRaw: String
    let plannedTargetKindRaw: String
    let plannedReps: Int?
    let plannedDurationSeconds: Int?
    let plannedWeightKG: Double?
    let plannedRestSeconds: Int?
    let restBetweenSidesSeconds: Int?
    let actualReps: Int?
    let actualDurationSeconds: Int?
    let actualWeightKG: Double?
    let actualRestSeconds: Int?

    var kind: WorkoutSetKind {
        WorkoutSetKind(rawValue: kindRaw) ?? .working
    }

    var status: WorkoutSetStatus {
        WorkoutSetStatus(rawValue: statusRaw) ?? .pending
    }

    var plannedTargetKind: WorkoutTargetKind {
        WorkoutTargetKind(rawValue: plannedTargetKindRaw) ?? .repetitions
    }
}

struct GuidedWorkoutEffortSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let workoutSetID: UUID
    let order: Int
    let sideRaw: String
    let targetKindRaw: String
    let plannedReps: Int?
    let plannedDurationSeconds: Int?
    let plannedWeightKG: Double?
    let actualReps: Int?
    let actualDurationSeconds: Int?
    let actualWeightKG: Double?
    let actualRestSeconds: Int?
    let statusRaw: String
    let recordedVideoPath: String?

    var side: WorkoutEffortSide {
        WorkoutEffortSide(rawValue: sideRaw) ?? .none
    }

    var targetKind: WorkoutTargetKind {
        WorkoutTargetKind(rawValue: targetKindRaw) ?? .repetitions
    }

    var status: WorkoutEffortStatus {
        WorkoutEffortStatus(rawValue: statusRaw) ?? .pending
    }
}

struct GuidedWorkoutExerciseChoice: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let artwork: ExerciseImageReference
}

struct GuidedWorkoutScreenSnapshot: Equatable, Sendable {
    let session: GuidedWorkoutSessionSnapshot
    let performances: [GuidedWorkoutPerformanceSnapshot]
    let sets: [GuidedWorkoutSetSnapshot]
    let efforts: [GuidedWorkoutEffortSnapshot]

    var currentPerformance: GuidedWorkoutPerformanceSnapshot? {
        guard let id = session.currentPerformanceID else { return nil }
        return performances.first { $0.id == id }
    }

    var currentSet: GuidedWorkoutSetSnapshot? {
        guard let id = session.currentSetID else { return nil }
        return sets.first { $0.id == id }
    }

    var currentEffort: GuidedWorkoutEffortSnapshot? {
        guard let id = session.currentEffortID else { return nil }
        return efforts.first { $0.id == id }
    }

    var currentPerformanceSets: [GuidedWorkoutSetSnapshot] {
        guard let performanceID = session.currentPerformanceID else { return [] }
        return sets.filter { $0.performanceID == performanceID }
    }

    var completedSetCount: Int {
        sets.count { $0.status == .completed }
    }

    var completedExerciseCount: Int {
        performances.count {
            $0.status == .completed || $0.status == .skipped
        }
    }

    var progressExercises: [GuidedWorkoutProgressExercise] {
        let setsByPerformanceID = Dictionary(grouping: sets, by: \.performanceID)
        let effortsBySetID = Dictionary(grouping: efforts, by: \.workoutSetID)
        return performances.map { performance in
            GuidedWorkoutProgressExercise(
                id: performance.id,
                sets: (setsByPerformanceID[performance.id] ?? []).map { set in
                    GuidedWorkoutProgressExercise.SetSegment(
                        id: set.id,
                        state: progressState(for: set),
                        completionFraction: GuidedWorkoutProgressExercise
                            .completionFraction(
                                set: set,
                                efforts: effortsBySetID[set.id] ?? []
                            )
                    )
                }
            )
        }
    }

    private func progressState(
        for set: GuidedWorkoutSetSnapshot
    ) -> GuidedWorkoutProgressSetState {
        switch set.status {
        case .completed:
            .completed
        case .partial:
            .partial
        case .skipped:
            .skipped
        case .failed:
            .failed
        case .inProgress:
            .current
        case .pending:
            set.id == session.currentSetID ? .current : .pending
        }
    }
}

enum GuidedWorkoutSnapshotError: LocalizedError {
    case missingSession

    var errorDescription: String? {
        switch self {
        case .missingSession:
            "找不到这次训练。它可能已经被删除。"
        }
    }
}

@MainActor
enum GuidedWorkoutScreenSnapshotLoader {
    static func replacementChoices(
        from container: ModelContainer
    ) throws -> [GuidedWorkoutExerciseChoice] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.canonicalName)]
        )
        descriptor.fetchLimit = 2000
        return try context.fetch(descriptor).map { exercise in
            GuidedWorkoutExerciseChoice(
                id: exercise.id,
                name: exercise.canonicalName,
                artwork: exercise.preferredActionIllustration
            )
        }
    }

    static func load(
        sessionID: UUID,
        from container: ModelContainer
    ) throws -> GuidedWorkoutScreenSnapshot {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        sessionDescriptor.fetchLimit = 1
        guard let session = try context.fetch(sessionDescriptor).first else {
            throw GuidedWorkoutSnapshotError.missingSession
        }

        let performanceModels = try context.fetch(
            FetchDescriptor<ExercisePerformance>(
                predicate: #Predicate { $0.sessionID == sessionID },
                sortBy: [SortDescriptor(\.order)]
            )
        )

        var performances: [GuidedWorkoutPerformanceSnapshot] = []
        var sets: [GuidedWorkoutSetSnapshot] = []
        var efforts: [GuidedWorkoutEffortSnapshot] = []

        for performance in performanceModels {
            let exerciseID = performance.exerciseID
            var definitionDescriptor = FetchDescriptor<ExerciseDefinition>(
                predicate: #Predicate { $0.id == exerciseID }
            )
            definitionDescriptor.fetchLimit = 1
            let definition = try context.fetch(definitionDescriptor).first
            performances.append(GuidedWorkoutPerformanceSnapshot(
                id: performance.id,
                exerciseID: exerciseID,
                exerciseName: performance.exerciseName,
                order: performance.order,
                statusRaw: performance.statusRaw,
                prescription: performance.prescriptionSnapshot,
                artwork: definition?.preferredActionIllustration
                    ?? BundledExerciseCatalog.fallbackActionIllustration,
                coachingNotes: definition?.coachingNotes ?? ""
            ))

            let performanceID = performance.id
            let setModels = try context.fetch(FetchDescriptor<WorkoutSet>(
                predicate: #Predicate { $0.performanceID == performanceID },
                sortBy: [SortDescriptor(\.order)]
            ))
            for set in setModels {
                sets.append(GuidedWorkoutSetSnapshot(
                    id: set.id,
                    performanceID: set.performanceID,
                    order: set.order,
                    kindRaw: set.kindRaw,
                    statusRaw: set.statusRaw,
                    plannedTargetKindRaw: set.plannedTargetKindRaw,
                    plannedReps: set.plannedReps,
                    plannedDurationSeconds: set.plannedDurationSeconds,
                    plannedWeightKG: set.plannedWeightKG,
                    plannedRestSeconds: set.plannedRestSeconds,
                    restBetweenSidesSeconds: set.restBetweenSidesSeconds,
                    actualReps: set.actualReps,
                    actualDurationSeconds: set.actualDurationSeconds,
                    actualWeightKG: set.actualWeightKG,
                    actualRestSeconds: set.actualRestSeconds
                ))

                let setID = set.id
                let effortModels = try context.fetch(FetchDescriptor<WorkoutEffort>(
                    predicate: #Predicate { $0.workoutSetID == setID },
                    sortBy: [SortDescriptor(\.order)]
                ))
                efforts.append(contentsOf: effortModels.map {
                    GuidedWorkoutEffortSnapshot(
                        id: $0.id,
                        workoutSetID: $0.workoutSetID,
                        order: $0.order,
                        sideRaw: $0.sideRaw,
                        targetKindRaw: $0.targetKindRaw,
                        plannedReps: $0.plannedReps,
                        plannedDurationSeconds: $0.plannedDurationSeconds,
                        plannedWeightKG: $0.plannedWeightKG,
                        actualReps: $0.actualReps,
                        actualDurationSeconds: $0.actualDurationSeconds,
                        actualWeightKG: $0.actualWeightKG,
                        actualRestSeconds: $0.actualRestSeconds,
                        statusRaw: $0.statusRaw,
                        recordedVideoPath: $0.recordedVideoPath
                    )
                })
            }
        }

        return GuidedWorkoutScreenSnapshot(
            session: GuidedWorkoutSessionSnapshot(
                id: session.id,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                statusRaw: session.statusRaw,
                guidedPhaseRaw: session.guidedPhaseRaw,
                currentPerformanceID: session.currentPerformanceID,
                currentSetID: session.currentSetID,
                currentEffortID: session.currentEffortID,
                phaseStartedAt: session.phaseStartedAt,
                phaseDeadlineAt: session.phaseDeadlineAt,
                transitionRevision: session.transitionRevision,
                restTargetEndAt: session.restTargetEndAt,
                autoRecordingPolicyRaw: session.autoRecordingPolicyRaw,
                queuedRecordingEffortID: session.queuedRecordingEffortID,
                automaticRecordingPaused: session.automaticRecordingPaused
            ),
            performances: performances,
            sets: sets,
            efforts: efforts
        )
    }
}
