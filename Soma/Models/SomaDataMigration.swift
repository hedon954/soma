import Foundation
import SwiftData

protocol BusinessIdentifiedModel: AnyObject {
    var id: UUID { get }
    var businessID: Int64? { get set }
}

@Model
final class DataMigrationMarker {
    @Attribute(.unique) var key: String
    var schemaVersion: Int
    var completedAt: Date

    init(
        key: String = "soma.launch-migration",
        schemaVersion: Int,
        completedAt: Date = .now
    ) {
        self.key = key
        self.schemaVersion = schemaVersion
        self.completedAt = completedAt
    }
}

@Model
final class BusinessIDSequence {
    @Attribute(.unique) var namespace: String
    var nextValue: Int64
    var updatedAt: Date

    init(namespace: String, nextValue: Int64 = 1, updatedAt: Date = .now) {
        self.namespace = namespace
        self.nextValue = nextValue
        self.updatedAt = updatedAt
    }
}

enum SomaDataSchema {
    static var models: [any PersistentModel.Type] {
        [
            ExternalSyncCursor.self,
            UserProfile.self,
            GymProfile.self,
            GymEquipment.self,
            GymMedia.self,
            MealEntry.self,
            BodyEntry.self,
            ExerciseDefinition.self,
            ExerciseMergeRecord.self,
            WorkoutEntry.self,
            TrainingProgram.self,
            TemplateExercise.self,
            TemplateSetPrescription.self,
            WorkoutSession.self,
            ExercisePerformance.self,
            WorkoutSet.self,
            WorkoutEffort.self,
            RecommendationSnapshot.self,
            PerformanceAnalysis.self,
            ConversationSession.self,
            CoachMessage.self,
            AgentTrace.self,
            AgentMutationReceipt.self,
            AgentJob.self,
            PersistentAgentEvent.self,
            DataMigrationMarker.self,
            BusinessIDSequence.self,
            ConversationCompactionSummary.self
        ]
    }
}

enum SomaDataMigration {
    static let currentVersion = 6

    @MainActor
    static func migrateIfNeeded(
        container: ModelContainer,
        dataSpace: DataSpace,
        now: Date = .now,
        timeZone: TimeZone = .current
    ) throws {
        let context = container.mainContext
        do {
            try assignUniqueProjectionKeys(in: context)
            if context.hasChanges {
                try context.save()
            }
        } catch {
            throw DataMigrationError.stepFailed("补齐训练投影键", error)
        }
        do {
            try ExerciseLoggingProfile.backfillIfNeeded(in: context)
            if context.hasChanges {
                try context.save()
            }
        } catch {
            throw DataMigrationError.stepFailed("回填动作侧别与完成方式", error)
        }
        do {
            try completeLaunchMigrationIfNeeded(
                context: context,
                dataSpace: dataSpace,
                now: now,
                timeZone: timeZone
            )
        } catch let error as DataMigrationError {
            throw error
        } catch {
            throw DataMigrationError.stepFailed("完成启动迁移", error)
        }
    }

    @MainActor
    private static func completeLaunchMigrationIfNeeded(
        context: ModelContext,
        dataSpace: DataSpace,
        now: Date,
        timeZone: TimeZone
    ) throws {
        let markers = try context.fetch(FetchDescriptor<DataMigrationMarker>())
        if markers.contains(where: { $0.schemaVersion >= currentVersion }) {
            return
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let sessions = try context.fetch(FetchDescriptor<ConversationSession>())
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        for session in sessions {
            if session.businessDate == nil {
                session.businessDate = calendar.startOfDay(for: session.startedAt)
            }
            if session.businessTimeZoneIdentifier == nil {
                session.businessTimeZoneIdentifier = timeZone.identifier
            }
        }

        let jobs = try context.fetch(FetchDescriptor<AgentJob>())
        for job in jobs {
            let sentAt = job.turnSentAt
                ?? job.contextSnapshot?.envelope?.trustedTime.turnSentAt
                ?? job.createdAt
            let session = sessionByID[job.sessionID]
            let zone = session?.businessTimeZone ?? timeZone
            let day = job.effectiveBusinessDate
                ?? session?.effectiveBusinessDate
                ?? sentAt
            job.turnSentAt = sentAt
            job.effectiveBusinessDate = BusinessDateResolver.startOfDay(day, in: zone)
            job.businessTimeZoneIdentifier = zone.identifier
            job.defaultOccurredAt = BusinessDateResolver.defaultOccurredAt(
                turnSentAt: sentAt,
                businessDate: day,
                timeZone: zone
            )
        }

        // 旧训练名称必须在 Agent Job 恢复前绑定到动作库。
        ExerciseLibraryStore.migrateLegacyWorkoutNames(in: context)
        try repairExerciseRelationships(in: context)
        try migrateTrainingDomainV5(in: context)
        try BusinessIDAllocator.repairAndAssignAllIDs(in: context)

        for oldMarker in markers {
            context.delete(oldMarker)
        }
        context.insert(DataMigrationMarker(schemaVersion: currentVersion, completedAt: now))
        try context.save()

        // 显式读取确保 marker 落在当前数据空间，而不是只留在内存事务中。
        let verified = try context.fetch(FetchDescriptor<DataMigrationMarker>())
        guard verified.contains(where: { $0.schemaVersion == currentVersion }) else {
            throw DataMigrationError.markerVerificationFailed(dataSpace)
        }
    }

    static func repairExerciseRelationships(
        in context: ModelContext
    ) throws {
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let byID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        for workout in try context.fetch(FetchDescriptor<WorkoutEntry>()) {
            workout.exerciseDefinition = workout.exerciseID.flatMap { byID[$0] }
        }
        for item in try context.fetch(FetchDescriptor<TemplateExercise>()) {
            item.exerciseDefinition = byID[item.exerciseID]
        }
        for performance in try context.fetch(FetchDescriptor<ExercisePerformance>()) {
            performance.exerciseDefinition = byID[performance.exerciseID]
        }
    }

    /// 修复备份恢复后的显式关系。只根据稳定 UUID 连接，不猜动作语义。
    static func repairTrainingRelationships(
        in context: ModelContext
    ) throws {
        let programs = try context.fetch(FetchDescriptor<TrainingProgram>())
        let programByGroupID = Dictionary(
            uniqueKeysWithValues: programs.compactMap { program in
                program.prescriptionGroupID.map { ($0, program) }
            }
        )

        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())
        let templateByID = Dictionary(
            uniqueKeysWithValues: templateExercises.map { ($0.id, $0) }
        )
        for exercise in templateExercises {
            exercise.program = programByGroupID[exercise.prescriptionGroupID]
        }
        for set in try context.fetch(FetchDescriptor<TemplateSetPrescription>()) {
            set.templateExercise = templateByID[set.templateExerciseID]
        }

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let sessionByID = Dictionary(
            uniqueKeysWithValues: sessions.map { ($0.id, $0) }
        )
        let performances = try context.fetch(FetchDescriptor<ExercisePerformance>())
        let performanceByID = Dictionary(
            uniqueKeysWithValues: performances.map { ($0.id, $0) }
        )
        for performance in performances {
            performance.session = sessionByID[performance.sessionID]
        }
        let workoutSets = try context.fetch(FetchDescriptor<WorkoutSet>())
        let workoutSetByID = Dictionary(
            uniqueKeysWithValues: workoutSets.map { ($0.id, $0) }
        )
        for set in workoutSets {
            set.performance = performanceByID[set.performanceID]
        }
        for effort in try context.fetch(FetchDescriptor<WorkoutEffort>()) {
            effort.workoutSet = workoutSetByID[effort.workoutSetID]
        }

        let workouts = try context.fetch(FetchDescriptor<WorkoutEntry>())
        let grouped = Dictionary(grouping: workouts.compactMap { workout in
            workout.sourcePerformanceID.map { ($0, workout) }
        }, by: { $0.0 })
        for (performanceID, values) in grouped {
            guard let performance = performanceByID[performanceID] else { continue }
            let ordered = values.map(\.1).sorted { $0.id.uuidString < $1.id.uuidString }
            guard let canonical = ordered.first else { continue }
            canonical.projectionKey = projectionKey(for: performanceID)
            canonical.sourcePerformance = performance
            performance.projectedWorkout = canonical
            for duplicate in ordered.dropFirst() {
                // 保留重复历史事实，但不能让它继续冒充唯一动作投影。
                duplicate.projectionKey = entryKey(for: duplicate.id)
                duplicate.sourcePerformance = nil
            }
        }
    }

    static func projectionKey(for performanceID: UUID) -> String {
        "guided-performance:\(performanceID.uuidString.lowercased())"
    }

    static func entryKey(for workoutID: UUID) -> String {
        "entry:\(workoutID.uuidString.lowercased())"
    }

    static func assignUniqueProjectionKeys(in context: ModelContext) throws {
        let workouts = try context.fetch(FetchDescriptor<WorkoutEntry>())
        var seen = Set<String>()
        for workout in workouts.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let key = workout.projectionKey.flatMap { value in
                value.isEmpty ? nil : value
            } ?? entryKey(for: workout.id)
            let resolved = seen.insert(key).inserted ? key : entryKey(for: workout.id)
            seen.insert(resolved)
            if workout.projectionKey != resolved {
                workout.projectionKey = resolved
            }
        }
    }

    private static func migrateTrainingDomainV5(
        in context: ModelContext
    ) throws {
        try validateLegacySnapshots(in: context)

        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())
        let existingPrescriptions = try context.fetch(
            FetchDescriptor<TemplateSetPrescription>()
        )
        let prescriptionsByExercise = Dictionary(
            grouping: existingPrescriptions,
            by: \.templateExerciseID
        )
        for exercise in templateExercises {
            if ExerciseLaterality(rawValue: exercise.lateralityRaw) == nil {
                exercise.laterality = .none
            }
            guard prescriptionsByExercise[exercise.id, default: []].isEmpty else {
                continue
            }
            let values = TemplateExercisePrescription.expandLegacySets(
                targetSets: exercise.targetSets,
                targetReps: exercise.targetReps,
                targetWeightKG: exercise.targetWeightKG,
                targetRestSeconds: exercise.targetRestSeconds,
                firstSetIsWarmup: exercise.firstSetIsWarmup
            )
            for value in values {
                let set = TemplateSetPrescription(
                    templateExerciseID: exercise.id,
                    value: value
                )
                set.templateExercise = exercise
                context.insert(set)
            }
        }

        let workoutSets = try context.fetch(FetchDescriptor<WorkoutSet>())
        let existingEfforts = try context.fetch(FetchDescriptor<WorkoutEffort>())
        let effortsBySet = Dictionary(grouping: existingEfforts, by: \.workoutSetID)
        let setsByPerformance = Dictionary(grouping: workoutSets, by: \.performanceID)
        for performanceSets in setsByPerformance.values {
            let ordered = performanceSets.sorted { $0.order < $1.order }
            let legacy = ordered.allSatisfy {
                effortsBySet[$0.id, default: []].isEmpty
            }
            if legacy {
                let oldPlannedRests = ordered.map(\.plannedRestSeconds)
                let oldActualRests = ordered.map(\.actualRestSeconds)
                for index in ordered.indices {
                    ordered[index].plannedRestSeconds = index + 1 < ordered.count
                        ? oldPlannedRests[index + 1]
                        : nil
                    ordered[index].actualRestSeconds = index + 1 < ordered.count
                        ? oldActualRests[index + 1]
                        : nil
                }
            }
        }
        for set in workoutSets where effortsBySet[set.id, default: []].isEmpty {
            let side = WorkoutEffortSide(rawValue: set.laterality ?? "") ?? .none
            let effort = WorkoutEffort(
                workoutSetID: set.id,
                order: 1,
                side: side,
                targetKind: set.plannedTargetKind,
                plannedReps: set.plannedReps,
                plannedDurationSeconds: set.plannedDurationSeconds,
                plannedWeightKG: set.plannedWeightKG,
                actualReps: set.actualReps,
                actualDurationSeconds: set.actualDurationSeconds,
                actualWeightKG: set.actualWeightKG,
                actualRestSeconds: set.actualRestSeconds,
                status: WorkoutEffortStatus(rawValue: set.statusRaw) ?? .pending,
                startedAt: set.startedAt,
                completedAt: set.completedAt,
                recordedVideoPath: set.recordedVideoPath
            )
            effort.workoutSet = set
            context.insert(effort)
        }

        try keepOnlyCurrentPlanPrescriptions(in: context)
        try repairTrainingRelationships(in: context)
    }

    /// 旧存储把每次编辑都保存成一组动作。迁移后只保留计划当前指向的那组，
    /// 之后编辑直接覆盖当前计划；已开始训练继续使用 Session 内的冻结处方。
    private static func keepOnlyCurrentPlanPrescriptions(
        in context: ModelContext
    ) throws {
        let programs = try context.fetch(FetchDescriptor<TrainingProgram>())
        for program in programs where program.prescriptionGroupID == nil {
            program.prescriptionGroupID = program.id
        }
        let activeGroupIDs = Set(programs.compactMap(\.prescriptionGroupID))
        let exercises = try context.fetch(FetchDescriptor<TemplateExercise>())
        let removed = exercises.filter {
            !activeGroupIDs.contains($0.prescriptionGroupID)
        }
        let removedIDs = Set(removed.map(\.id))
        for set in try context.fetch(FetchDescriptor<TemplateSetPrescription>())
            where removedIDs.contains(set.templateExerciseID)
        {
            context.delete(set)
        }
        removed.forEach(context.delete)
    }

    private static func validateLegacySnapshots(
        in context: ModelContext
    ) throws {
        for session in try context.fetch(FetchDescriptor<WorkoutSession>())
            where !session.prescriptionSnapshotData.isEmpty
            && TrainingPlanCoding.decode(
                [TemplateExercisePrescription].self,
                from: session.prescriptionSnapshotData
            ) == nil
        {
            throw DataMigrationError.invalidTrainingSnapshot("session", session.id)
        }
        for performance in try context.fetch(FetchDescriptor<ExercisePerformance>())
            where !performance.prescriptionSnapshotData.isEmpty
            && TrainingPlanCoding.decode(
                TemplateExercisePrescription.self,
                from: performance.prescriptionSnapshotData
            ) == nil
        {
            throw DataMigrationError.invalidTrainingSnapshot(
                "performance",
                performance.id
            )
        }
    }
}

@MainActor
enum BusinessIDAllocator {
    static func next(namespace: String, in context: ModelContext) throws -> Int64 {
        let sequences = try context.fetch(FetchDescriptor<BusinessIDSequence>())
        let sequence: BusinessIDSequence
        if let existing = sequences.first(where: { $0.namespace == namespace }) {
            sequence = existing
        } else {
            sequence = BusinessIDSequence(namespace: namespace)
            context.insert(sequence)
        }
        let value = sequence.nextValue
        sequence.nextValue += 1
        sequence.updatedAt = .now
        return value
    }

    static func assign(
        _ model: some PersistentModel & BusinessIdentifiedModel,
        namespace: String,
        in context: ModelContext
    ) throws {
        guard model.businessID == nil else { return }
        model.businessID = try next(namespace: namespace, in: context)
    }

    static func assignMissingIDs(in context: ModelContext) throws {
        try assignAll(UserProfile.self, namespace: "user_profile", in: context)
        try assignAll(GymProfile.self, namespace: "gym", in: context)
        try assignAll(GymEquipment.self, namespace: "gym_equipment", in: context)
        try assignAll(MealEntry.self, namespace: "meal", in: context)
        try assignAll(BodyEntry.self, namespace: "body", in: context)
        try assignAll(WorkoutEntry.self, namespace: "workout", in: context)
        try assignAll(ExerciseDefinition.self, namespace: "exercise", in: context)
        try assignAll(ExerciseMergeRecord.self, namespace: "exercise_merge", in: context)
        try assignAll(TrainingProgram.self, namespace: "training_program", in: context)
        try assignAll(TemplateExercise.self, namespace: "template_exercise", in: context)
        try assignAll(
            TemplateSetPrescription.self,
            namespace: "template_set_prescription",
            in: context
        )
        try assignAll(WorkoutSession.self, namespace: "workout_session", in: context)
        try assignAll(ExercisePerformance.self, namespace: "performance", in: context)
        try assignAll(WorkoutSet.self, namespace: "workout_set", in: context)
        try assignAll(WorkoutEffort.self, namespace: "workout_effort", in: context)
        try assignAll(RecommendationSnapshot.self, namespace: "recommendation", in: context)
        try assignAll(PerformanceAnalysis.self, namespace: "performance_analysis", in: context)
    }

    static func repairAndAssignAllIDs(in context: ModelContext) throws {
        try clearDuplicateIDs(UserProfile.self, in: context)
        try clearDuplicateIDs(GymProfile.self, in: context)
        try clearDuplicateIDs(GymEquipment.self, in: context)
        try clearDuplicateIDs(MealEntry.self, in: context)
        try clearDuplicateIDs(BodyEntry.self, in: context)
        try clearDuplicateIDs(WorkoutEntry.self, in: context)
        try clearDuplicateIDs(ExerciseDefinition.self, in: context)
        try clearDuplicateIDs(ExerciseMergeRecord.self, in: context)
        try clearDuplicateIDs(TrainingProgram.self, in: context)
        try clearDuplicateIDs(TemplateExercise.self, in: context)
        try clearDuplicateIDs(TemplateSetPrescription.self, in: context)
        try clearDuplicateIDs(WorkoutSession.self, in: context)
        try clearDuplicateIDs(ExercisePerformance.self, in: context)
        try clearDuplicateIDs(WorkoutSet.self, in: context)
        try clearDuplicateIDs(WorkoutEffort.self, in: context)
        try clearDuplicateIDs(RecommendationSnapshot.self, in: context)
        try clearDuplicateIDs(PerformanceAnalysis.self, in: context)
        try assignMissingIDs(in: context)
    }

    private static func clearDuplicateIDs<
        T: PersistentModel & BusinessIdentifiedModel
    >(
        _ type: T.Type,
        in context: ModelContext
    ) throws {
        var seen = Set<Int64>()
        for model in try context.fetch(FetchDescriptor<T>())
            .sorted(by: { $0.id.uuidString < $1.id.uuidString })
        {
            guard let businessID = model.businessID else { continue }
            if !seen.insert(businessID).inserted {
                model.businessID = nil
            }
        }
    }

    private static func assignAll<T: PersistentModel & BusinessIdentifiedModel>(
        _ type: T.Type,
        namespace: String,
        in context: ModelContext
    ) throws {
        let models = try context.fetch(FetchDescriptor<T>())
        let maximumAssignedID = models.compactMap(\.businessID).max() ?? 0
        try ensureSequence(
            namespace: namespace,
            minimumNextValue: maximumAssignedID + 1,
            in: context
        )
        for model in models
            .filter({ $0.businessID == nil })
            .sorted(by: { $0.id.uuidString < $1.id.uuidString })
        {
            model.businessID = try next(namespace: namespace, in: context)
        }
    }

    private static func ensureSequence(
        namespace: String,
        minimumNextValue: Int64,
        in context: ModelContext
    ) throws {
        let sequences = try context.fetch(FetchDescriptor<BusinessIDSequence>())
        if let sequence = sequences.first(where: { $0.namespace == namespace }) {
            if sequence.nextValue < minimumNextValue {
                sequence.nextValue = minimumNextValue
                sequence.updatedAt = .now
            }
        } else {
            context.insert(BusinessIDSequence(
                namespace: namespace,
                nextValue: max(1, minimumNextValue)
            ))
        }
    }
}

enum DataMigrationError: LocalizedError {
    case markerVerificationFailed(DataSpace)
    case invalidTrainingSnapshot(String, UUID)
    case stepFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case let .markerVerificationFailed(space):
            "\(space.title)迁移完成标记校验失败。"
        case let .invalidTrainingSnapshot(kind, id):
            "训练\(kind)快照 \(id.uuidString) 无法解码，已停止迁移以保护数据。"
        case let .stepFailed(step, error):
            "\(step)失败：\(error.localizedDescription)"
        }
    }
}
