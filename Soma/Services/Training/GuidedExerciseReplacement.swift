import Foundation
import SwiftData

struct GuidedExerciseReplacementPreview {
    let prescription: TemplateExercisePrescription
    let sourceDate: Date?
    let sourceSummary: String?

    var explanation: String {
        guard let sourceDate else {
            return "还没有这个动作的训练记录。请填写这次的目标；重量和间歇可以留空。"
        }
        return "已载入 \(sourceDate.formatted(date: .abbreviated, time: .omitted)) 的实际记录。请确认各组目标；无法直接套用的值留空，原记录保持不变。"
    }
}

enum GuidedExerciseReplacementError: LocalizedError {
    case alreadyStarted
    case invalidPrescription

    var errorDescription: String? {
        switch self {
        case .alreadyStarted:
            "当前动作已经开始，不能替换已产生的记录。请完成或跳过当前动作，在下一个动作开始前更换。"
        case .invalidPrescription:
            "替换参数与动作设定不一致。请重新选择动作，并填写每组的目标次数或时长后确认。"
        }
    }
}

@MainActor
enum GuidedExerciseReplacementResolver {
    static func preview(
        exercise: ExerciseDefinition,
        excluding sessionID: UUID,
        in context: ModelContext
    ) throws -> GuidedExerciseReplacementPreview {
        let exerciseID = exercise.id
        var descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate {
                $0.exerciseID == exerciseID
                    && ($0.sourceSessionID == nil || $0.sourceSessionID != sessionID)
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let record = try context.fetch(descriptor).first
        let groups = WorkoutRecordDraft(
            evidence: record?.setEntries ?? [],
            loggingProfile: ExerciseLoggingProfileSnapshot(exercise)
        ).groups.sorted { $0.sourceOrder < $1.sourceOrder }
        var plannedSets = groups.enumerated().map { index, group in
            plannedSet(group, order: index + 1, exercise: exercise)
        }
        if plannedSets.isEmpty {
            plannedSets = [.init(order: 1, targetKind: exercise.targetKind)]
        }
        let rests = groups.dropLast().map {
            $0.restPresentation.afterGroupSeconds ?? record?.restSeconds
        }
        let sideRests = groups.map(\.restPresentation.betweenSidesSeconds)
        let prescription = TemplateExercisePrescription(
            exerciseID: exercise.id, exerciseName: exercise.canonicalName, order: 1,
            targetSets: plannedSets.count,
            targetRestSeconds: consensus(rests),
            restBetweenSidesSeconds: exercise.laterality == .both ? consensus(sideRests) : nil,
            firstSetIsWarmup: plannedSets.first?.kind == .warmup,
            laterality: exercise.laterality, plannedSets: plannedSets
        )
        return GuidedExerciseReplacementPreview(
            prescription: prescription, sourceDate: record?.date,
            sourceSummary: record.map { WorkoutHistoryFormatter.text(for: $0) }
        )
    }

    private static func plannedSet(
        _ group: LogicalWorkoutGroupDraft,
        order: Int,
        exercise: ExerciseDefinition
    ) -> TemplateSetPrescriptionValue {
        let efforts = group.efforts.filter { effort in
            switch exercise.laterality {
            case .left: effort.side == .left
            case .right: effort.side == .right
            case .none, .both: true
            }
        }
        let hasBothSides = efforts.contains { $0.side == .left }
            && efforts.contains { $0.side == .right }
        let complete = exercise.laterality != .both || hasBothSides
        let matching = complete && efforts.allSatisfy { $0.targetKind == exercise.targetKind }
        let sharedWeight = complete ? consensus(efforts.map(\.externalWeightKG)) : nil
        return TemplateSetPrescriptionValue(
            order: order, kind: consensus(efforts.map(\.kind)) ?? .working,
            targetKind: exercise.targetKind,
            targetReps: matching && exercise.targetKind == .repetitions
                ? consensus(efforts.map(\.reps)) : nil,
            targetDurationSeconds: matching && exercise.targetKind == .duration
                ? consensus(efforts.map(\.durationSeconds)) : nil,
            targetWeightKG: sharedWeight,
            leftWeightKG: exercise.laterality == .both || exercise.laterality == .left
                ? consensus(efforts.filter { $0.side == .left }.map(\.externalWeightKG)) : nil,
            rightWeightKG: exercise.laterality == .both || exercise.laterality == .right
                ? consensus(efforts.filter { $0.side == .right }.map(\.externalWeightKG)) : nil
        )
    }

    private static func consensus<T: Equatable>(_ values: [T?]) -> T? {
        guard let first = values.first ?? nil,
              values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}

@MainActor
extension GuidedWorkoutCoordinator {
    func replaceCurrentExercise(
        with exercise: ExerciseDefinition,
        prescription confirmed: TemplateExercisePrescription,
        in context: ModelContext
    ) throws {
        let session = try activeSession(in: context)
        guard let performance = currentPerformance(for: session, in: context) else {
            throw GuidedWorkoutError.missingPerformance
        }
        let oldSets = sets(for: performance, in: context)
        let oldEfforts = oldSets.flatMap { efforts(for: $0, in: context) }
        guard session.status == .active, session.guidedPhase == .exerciseIntroduction,
              performance.activeVideoPath == nil, performance.projectedWorkout == nil,
              oldSets.allSatisfy({ $0.status == .pending && $0.startedAt == nil && $0.completedAt == nil
                      && $0.actualReps == nil && $0.actualDurationSeconds == nil
                      && $0.actualWeightKG == nil && $0.actualRestSeconds == nil
                      && $0.recordedVideoPath == nil }),
              oldEfforts.allSatisfy({ $0.status == .pending && $0.startedAt == nil && $0.completedAt == nil
                      && $0.actualReps == nil && $0.actualDurationSeconds == nil
                      && $0.actualWeightKG == nil && $0.actualRestSeconds == nil
                      && $0.recordedVideoPath == nil })
        else {
            throw GuidedExerciseReplacementError.alreadyStarted
        }
        guard confirmed.exerciseID == exercise.id,
              confirmed.laterality == exercise.laterality,
              confirmed.plannedSets.allSatisfy({ $0.targetKind == exercise.targetKind }),
              !TrainingPlanStore.readiness(
                  prescriptions: [confirmed], autoRecordingPolicy: session.autoRecordingPolicy,
                  in: context
              ).contains(where: { $0.severity == .blocking })
        else {
            throw GuidedExerciseReplacementError.invalidPrescription
        }
        var prescription = confirmed
        prescription.id = performance.prescriptionSnapshot?.id ?? confirmed.id
        prescription.order = performance.order
        prescription.exerciseName = exercise.canonicalName
        try context.transaction {
            for effort in oldEfforts {
                context.delete(effort)
            }
            for set in oldSets {
                context.delete(set)
            }
            performance.exerciseID = exercise.id
            performance.exerciseDefinition = exercise
            performance.exerciseName = exercise.canonicalName
            performance.prescriptionSnapshotData = TrainingPlanCoding.encode(prescription)
            var snapshot = session.prescriptionSnapshot
            if let index = snapshot.firstIndex(where: { $0.order == performance.order }) {
                snapshot[index] = prescription
            }
            session.prescriptionSnapshotData = TrainingPlanCoding.encode(snapshot)
            let runtime = WorkoutRuntimePrescriptionBuilder.build(
                prescription: prescription, performance: performance, in: context
            )
            session.currentSetID = runtime.sets.first?.id
            session.currentEffortID = runtime.efforts.first?.id
            setPhase(.exerciseIntroduction, for: session)
            normalizeQueuedRecording(for: session, in: context)
            try BusinessIDAllocator.assignMissingIDs(in: context)
            try context.save()
        }
    }
}
