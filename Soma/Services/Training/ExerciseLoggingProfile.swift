import Foundation
import SwiftData

enum ExerciseLoggingProfile {
    static func resolvedTargetKind(
        exercise: ExerciseDefinition?,
        evidenceTargetKind: WorkoutTargetKind? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil
    ) -> WorkoutTargetKind {
        if let exercise, exercise.hasExplicitTargetKind {
            return exercise.targetKind
        }
        if evidenceTargetKind == .duration {
            return .duration
        }
        if durationSeconds != nil, reps == nil {
            return .duration
        }
        return evidenceTargetKind ?? .repetitions
    }

    static func setTitle(
        displayIndex: Int,
        logicalSetIndex: Int?,
        side: WorkoutEffortSide?
    ) -> String {
        let group = logicalSetIndex ?? displayIndex
        switch side {
        case .some(.left):
            return "第 \(group) 组 · 左侧"
        case .some(.right):
            return "第 \(group) 组 · 右侧"
        default:
            return "第 \(group) 组"
        }
    }

    static func nextLogicalSetIndex(existing: [Int?]) -> Int {
        (existing.compactMap { $0 }.max() ?? 0) + 1
    }

    static func adoptIfUnset(
        _ exercise: ExerciseDefinition,
        laterality: ExerciseLaterality? = nil,
        targetKind: WorkoutTargetKind? = nil
    ) {
        if !exercise.hasExplicitLaterality, let laterality, laterality != .none {
            exercise.laterality = laterality
        }
        if !exercise.hasExplicitTargetKind, let targetKind, targetKind != .repetitions {
            exercise.targetKind = targetKind
        }
    }

    static func backfillIfNeeded(in context: ModelContext) throws {
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let templates = try context.fetch(FetchDescriptor<TemplateExercise>())
        let prescriptions = try context.fetch(FetchDescriptor<TemplateSetPrescription>())
        let workouts = try context.fetch(FetchDescriptor<WorkoutEntry>())
        let templatesByExercise = Dictionary(grouping: templates, by: \.exerciseID)
        let prescriptionsByTemplate = Dictionary(
            grouping: prescriptions,
            by: \.templateExerciseID
        )
        let workoutsByExercise = Dictionary(
            grouping: workouts.filter { $0.exerciseID != nil },
            by: { $0.exerciseID! }
        )

        for definition in definitions {
            if !definition.hasExplicitLaterality,
               let laterality = inferredLaterality(
                   templates: templatesByExercise[definition.id, default: []],
                   workouts: workoutsByExercise[definition.id, default: []]
               )
            {
                definition.laterality = laterality
            }
            if !definition.hasExplicitTargetKind,
               let targetKind = inferredTargetKind(
                   templates: templatesByExercise[definition.id, default: []],
                   prescriptionsByTemplate: prescriptionsByTemplate,
                   workouts: workoutsByExercise[definition.id, default: []]
               )
            {
                definition.targetKind = targetKind
            }
        }
    }

    private static func inferredLaterality(
        templates: [TemplateExercise],
        workouts: [WorkoutEntry]
    ) -> ExerciseLaterality? {
        let fromPlans = templates.map(\.laterality).filter { $0 != .none }
        let fromEvidence = workouts.flatMap(\.setEntries).compactMap(\.side)
        if fromPlans.contains(.both)
            || (fromEvidence.contains(.left) && fromEvidence.contains(.right))
        {
            return .both
        }
        if fromPlans.contains(.left) || fromEvidence.contains(.left) {
            return .left
        }
        if fromPlans.contains(.right) || fromEvidence.contains(.right) {
            return .right
        }
        return nil
    }

    private static func inferredTargetKind(
        templates: [TemplateExercise],
        prescriptionsByTemplate: [UUID: [TemplateSetPrescription]],
        workouts: [WorkoutEntry]
    ) -> WorkoutTargetKind? {
        let fromPlans = templates.contains { template in
            prescriptionsByTemplate[template.id, default: []].contains {
                $0.targetKind == .duration
            }
        }
        let fromEvidence = workouts.flatMap(\.setEntries).contains { evidence in
            evidence.targetKind == .duration
                || (evidence.durationSeconds != nil && evidence.reps == nil)
        }
        if fromPlans || fromEvidence {
            return .duration
        }
        return nil
    }
}
