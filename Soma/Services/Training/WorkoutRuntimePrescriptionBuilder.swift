import SwiftData

/// 计划开始与动作替换共用同一组/侧目标展开规则。
@MainActor
enum WorkoutRuntimePrescriptionBuilder {
    struct Result {
        let sets: [WorkoutSet]
        let efforts: [WorkoutEffort]
    }

    static func build(
        prescription: TemplateExercisePrescription,
        performance: ExercisePerformance,
        in context: ModelContext
    ) -> Result {
        var createdSets: [WorkoutSet] = []
        var createdEfforts: [WorkoutEffort] = []
        let laterality = performance.exerciseDefinition?.hasExplicitLaterality == true
            ? performance.exerciseDefinition?.laterality ?? prescription.laterality
            : prescription.laterality
        let orderedSets = prescription.plannedSets.sorted { $0.order < $1.order }
        for (setIndex, planned) in orderedSets.enumerated() {
            let targetKind = performance.exerciseDefinition?.hasExplicitTargetKind == true
                ? performance.exerciseDefinition?.targetKind ?? planned.targetKind
                : planned.targetKind
            let set = WorkoutSet(
                performanceID: performance.id,
                order: planned.order,
                kind: planned.kind,
                laterality: laterality.rawValue,
                plannedTargetKind: targetKind,
                plannedReps: planned.targetReps,
                plannedDurationSeconds: planned.targetDurationSeconds,
                plannedWeightKG: planned.targetWeightKG,
                plannedRestSeconds: setIndex < orderedSets.count - 1
                    ? prescription.targetRestSeconds
                    : nil,
                restBetweenSidesSeconds: laterality == .both
                    ? prescription.restBetweenSidesSeconds
                    : nil
            )
            set.performance = performance
            context.insert(set)
            createdSets.append(set)
            let sides: [WorkoutEffortSide] = switch laterality {
            case .both:
                [.left, .right]
            case .left:
                [.left]
            case .right:
                [.right]
            case .none:
                [.none]
            }
            for (index, side) in sides.enumerated() {
                let effort = WorkoutEffort(
                    workoutSetID: set.id,
                    order: index + 1,
                    side: side,
                    targetKind: targetKind,
                    plannedReps: planned.targetReps,
                    plannedDurationSeconds: planned.targetDurationSeconds,
                    plannedWeightKG: planned.weight(for: side)
                )
                effort.workoutSet = set
                context.insert(effort)
                createdEfforts.append(effort)
            }
        }
        return Result(sets: createdSets, efforts: createdEfforts)
    }
}
