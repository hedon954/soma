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

/// 新安装与旧安装都从这一处取得模型清单，避免两个数据空间或测试容器发生漂移。
enum SomaDataSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

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
            WorkoutTemplateVersion.self,
            TemplateExercise.self,
            WorkoutSession.self,
            ExercisePerformance.self,
            WorkoutSet.self,
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

enum SomaSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SomaDataSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum SomaDataMigration {
    static let currentVersion = 4

    @MainActor
    static func migrateIfNeeded(
        container: ModelContainer,
        dataSpace: DataSpace,
        now: Date = .now,
        timeZone: TimeZone = .current
    ) throws {
        let context = container.mainContext
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

        try BusinessIDAllocator.assignMissingIDs(in: context)

        // 旧训练名称必须在 Agent Job 恢复前绑定到动作库。
        ExerciseLibraryStore.migrateLegacyWorkoutNames(in: context)
        try repairExerciseRelationships(in: context)

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
        try assignAll(WorkoutTemplateVersion.self, namespace: "template_version", in: context)
        try assignAll(TemplateExercise.self, namespace: "template_exercise", in: context)
        try assignAll(WorkoutSession.self, namespace: "workout_session", in: context)
        try assignAll(ExercisePerformance.self, namespace: "performance", in: context)
        try assignAll(WorkoutSet.self, namespace: "workout_set", in: context)
        try assignAll(RecommendationSnapshot.self, namespace: "recommendation", in: context)
        try assignAll(PerformanceAnalysis.self, namespace: "performance_analysis", in: context)
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

    var errorDescription: String? {
        switch self {
        case let .markerVerificationFailed(space):
            "\(space.title)迁移完成标记校验失败。"
        }
    }
}
