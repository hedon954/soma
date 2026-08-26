import Foundation
import SwiftData

/// 把用户已经完成的原始动作记录组装为一次已完成的计划执行。原记录仍是事实本体，
/// Session/Performance 只建立执行语义与逐组快照，不复制第二份 WorkoutEntry。
@MainActor
enum CompletedTrainingSessionMaterializer {
    static func materialize(
        program: TrainingProgram,
        sourceWorkouts: [WorkoutEntry],
        in context: ModelContext
    ) throws -> WorkoutSession {
        guard !sourceWorkouts.isEmpty else { throw TrainingPlanError.emptyTemplate }
        let orderedWorkouts = sourceWorkouts.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return (lhs.businessID ?? 0) < (rhs.businessID ?? 0)
            }
            return lhs.date < rhs.date
        }
        try validate(orderedWorkouts)
        let prescriptions = TrainingPlanStore.prescriptions(for: program, in: context)
        let prescriptionByExerciseID = Dictionary(grouping: prescriptions, by: \.exerciseID)
        guard orderedWorkouts.allSatisfy({ workout in
            workout.exerciseID.map { prescriptionByExerciseID[$0] != nil } ?? false
        }) else {
            throw TrainingPlanError.invalidValue("原始训练动作必须全部包含在新计划中")
        }

        let startedAt = orderedWorkouts.map(\.date).min() ?? .now
        let endedAt = orderedWorkouts.map { workout in
            workout.date.addingTimeInterval(TimeInterval((workout.durationMinutes ?? 0) * 60))
        }.max() ?? startedAt
        let session = WorkoutSession(
            startedAt: startedAt,
            endedAt: max(endedAt, startedAt),
            programID: program.id,
            programNameSnapshot: program.name,
            prescriptionSnapshot: prescriptions,
            status: .completed,
            guidedPhase: .completed
        )
        context.insert(session)

        var exerciseUseCount: [UUID: Int] = [:]
        for (index, workout) in orderedWorkouts.enumerated() {
            guard let exerciseID = workout.exerciseID,
                  let candidates = prescriptionByExerciseID[exerciseID],
                  !candidates.isEmpty
            else {
                throw TrainingPlanError.missingExercise(workout.exerciseID ?? UUID())
            }
            let useIndex = exerciseUseCount[exerciseID, default: 0]
            let prescription = candidates[min(useIndex, candidates.count - 1)]
            exerciseUseCount[exerciseID] = useIndex + 1
            let performance = insertPerformance(
                workout: workout,
                prescription: prescription,
                order: index + 1,
                session: session,
                in: context
            )
            workout.sourceWorkoutSessionID = session.id
            workout.sourcePerformanceID = performance.id
            workout.sourcePerformance = performance
        }
        try BusinessIDAllocator.assignMissingIDs(in: context)
        try context.save()
        return session
    }

    private static func validate(_ workouts: [WorkoutEntry]) throws {
        let businessDay = Calendar.current.startOfDay(for: workouts[0].date)
        guard workouts.allSatisfy({
            Calendar.current.startOfDay(for: $0.date) == businessDay
                && $0.exerciseID != nil
                && $0.sourceWorkoutSessionID == nil
        }) else {
            throw TrainingPlanError.invalidValue("原始训练必须来自同一天且尚未归入其他 Session")
        }
    }

    private static func insertPerformance(
        workout: WorkoutEntry,
        prescription: TemplateExercisePrescription,
        order: Int,
        session: WorkoutSession,
        in context: ModelContext
    ) -> ExercisePerformance {
        let performance = ExercisePerformance(
            sessionID: session.id,
            exerciseID: prescription.exerciseID,
            exerciseName: workout.exercise,
            order: order,
            prescriptionSnapshot: prescription,
            status: .completed,
            notes: workout.notes
        )
        performance.session = session
        performance.exerciseDefinition = workout.exerciseDefinition
        performance.projectedWorkout = workout
        context.insert(performance)
        for (index, group) in evidenceGroups(workout.setEntries).enumerated() {
            insertSet(
                evidence: group,
                index: index,
                workout: workout,
                prescription: prescription,
                performance: performance,
                in: context
            )
        }
        return performance
    }

    private static func insertSet(
        evidence: [WorkoutSetEvidence],
        index: Int,
        workout: WorkoutEntry,
        prescription: TemplateExercisePrescription,
        performance: ExercisePerformance,
        in context: ModelContext
    ) {
        let planned = prescription.plannedSets.indices.contains(index)
            ? prescription.plannedSets[index]
            : nil
        let representative = evidence[0]
        let targetKind = ExerciseLoggingProfile.resolvedTargetKind(
            exercise: workout.exerciseDefinition,
            evidenceTargetKind: representative.targetKind,
            reps: representative.reps,
            durationSeconds: representative.durationSeconds
        )
        let set = WorkoutSet(
            performanceID: performance.id,
            order: representative.logicalSetIndex ?? index + 1,
            kind: representative.kind ?? planned?.kind ?? .working,
            laterality: resolvedLaterality(evidence).rawValue,
            plannedTargetKind: targetKind,
            plannedReps: planned?.targetReps,
            plannedDurationSeconds: planned?.targetDurationSeconds,
            plannedWeightKG: planned?.targetWeightKG,
            plannedRestSeconds: planned?.restAfterSetSeconds,
            actualReps: consensus(evidence.compactMap(\.reps)),
            actualDurationSeconds: consensus(evidence.compactMap(\.durationSeconds)),
            actualWeightKG: consensus(evidence.compactMap(\.externalWeightKG)),
            actualRestSeconds: consensus(evidence.compactMap(\.restSeconds))
                ?? workout.restSeconds,
            status: .completed,
            startedAt: workout.date,
            completedAt: workout.date
        )
        set.performance = performance
        context.insert(set)
        for (effortIndex, item) in evidence.enumerated() {
            insertEffort(
                item,
                index: effortIndex,
                workout: workout,
                planned: planned,
                set: set,
                in: context
            )
        }
    }

    private static func insertEffort(
        _ evidence: WorkoutSetEvidence,
        index: Int,
        workout: WorkoutEntry,
        planned: TemplateSetPrescriptionValue?,
        set: WorkoutSet,
        in context: ModelContext
    ) {
        let targetKind = ExerciseLoggingProfile.resolvedTargetKind(
            exercise: workout.exerciseDefinition,
            evidenceTargetKind: evidence.targetKind,
            reps: evidence.reps,
            durationSeconds: evidence.durationSeconds
        )
        let effort = WorkoutEffort(
            workoutSetID: set.id,
            order: index + 1,
            side: evidence.side ?? .none,
            targetKind: targetKind,
            plannedReps: planned?.targetReps,
            plannedDurationSeconds: planned?.targetDurationSeconds,
            plannedWeightKG: planned?.weight(for: evidence.side ?? .none),
            actualReps: evidence.reps,
            actualDurationSeconds: evidence.durationSeconds,
            actualWeightKG: evidence.externalWeightKG,
            actualRestSeconds: evidence.restSeconds ?? workout.restSeconds,
            status: .completed,
            startedAt: workout.date,
            completedAt: workout.date,
            recordedVideoPath: evidence.recordedVideoPath,
            recordedVideoKind: evidence.recordedVideoKind
        )
        effort.workoutSet = set
        context.insert(effort)
    }

    private static func evidenceGroups(
        _ evidence: [WorkoutSetEvidence]
    ) -> [[WorkoutSetEvidence]] {
        var result: [[WorkoutSetEvidence]] = []
        var lastLogicalIndex: Int?
        for item in evidence {
            if let logicalIndex = item.logicalSetIndex,
               logicalIndex == lastLogicalIndex,
               !result.isEmpty
            {
                result[result.count - 1].append(item)
            } else {
                result.append([item])
                lastLogicalIndex = item.logicalSetIndex
            }
        }
        return result
    }

    private static func resolvedLaterality(
        _ evidence: [WorkoutSetEvidence]
    ) -> ExerciseLaterality {
        let sides = Set(evidence.compactMap(\.side))
        if sides.contains(.left), sides.contains(.right) {
            return .both
        }
        if sides.contains(.left) {
            return .left
        }
        if sides.contains(.right) {
            return .right
        }
        return .none
    }

    private static func consensus<T: Hashable>(_ values: [T]) -> T? {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }
}
