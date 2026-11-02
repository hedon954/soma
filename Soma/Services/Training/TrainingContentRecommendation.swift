import Foundation
import SwiftData

struct TrainingContentRecommendation {
    var sourceDate: Date
    var prescription: TemplateExercisePrescription
}

@MainActor
enum TrainingContentRecommendations {
    static func latest(for exercise: ExerciseDefinition, in context: ModelContext) throws -> TrainingContentRecommendation? {
        let id = exercise.id
        var descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.exerciseID == id },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.id, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let entry = try context.fetch(descriptor).first, !entry.setEntries.isEmpty else { return nil }
        return TrainingContentRecommendation(
            sourceDate: entry.date,
            prescription: prescription(for: exercise, evidence: entry.setEntries)
        )
    }

    static func prescription(
        for exercise: ExerciseDefinition, evidence: [WorkoutSetEvidence]
    ) -> TemplateExercisePrescription {
        let groups = WorkoutRecordDraft(evidence: evidence).groups
        let sets = groups.enumerated().map { index, group in
            let efforts = group.efforts
            let first = efforts.first
            let left = efforts.first { $0.side == .left }
            let right = efforts.first { $0.side == .right }
            return TemplateSetPrescriptionValue(
                order: index + 1,
                kind: first?.kind ?? .working,
                targetKind: exercise.targetKind,
                targetReps: exercise.targetKind == .repetitions ? consensus(efforts.map(\.reps)) : nil,
                targetDurationSeconds: exercise.targetKind == .duration ? consensus(efforts.map(\.durationSeconds)) : nil,
                targetWeightKG: exercise.laterality == .none ? first?.externalWeightKG : nil,
                leftWeightKG: left?.externalWeightKG,
                rightWeightKG: right?.externalWeightKG,
                restBetweenSidesSeconds: group.restPresentation.betweenSidesSeconds,
                restAfterSetSeconds: group.restPresentation.afterGroupSeconds
            )
        }
        return TemplateExercisePrescription(
            exerciseID: exercise.id, exerciseName: exercise.canonicalName, order: 1,
            targetRestSeconds: consensus(Array(sets.dropLast()).map(\.restAfterSetSeconds)),
            restBetweenSidesSeconds: consensus(sets.map(\.restBetweenSidesSeconds)),
            laterality: exercise.laterality, plannedSets: sets
        )
    }

    private static func consensus<T: Equatable>(_ values: [T?]) -> T? {
        guard let first = values.first ?? nil, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}
