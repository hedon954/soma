import Foundation
import SwiftData

struct PersonalDataClearResult: Equatable, Sendable {
    var deletedModelCount: Int
    var deletedMediaCount: Int
}

@MainActor
enum PersonalDataStore {
    static func deleteAllModels(in context: ModelContext) throws {
        try context.delete(model: ExternalSyncCursor.self)
        try context.delete(model: UserProfile.self)
        try context.delete(model: GymProfile.self)
        try context.delete(model: GymEquipment.self)
        try context.delete(model: GymMedia.self)
        try context.delete(model: MealEntry.self)
        try context.delete(model: BodyEntry.self)
        try context.delete(model: ExerciseMergeRecord.self)
        try context.delete(model: ExerciseDefinition.self)
        try context.delete(model: WorkoutEntry.self)
        try context.delete(model: TrainingProgram.self)
        try context.delete(model: WorkoutTemplateVersion.self)
        try context.delete(model: TemplateExercise.self)
        try context.delete(model: WorkoutSession.self)
        try context.delete(model: ExercisePerformance.self)
        try context.delete(model: WorkoutSet.self)
        try context.delete(model: RecommendationSnapshot.self)
        try context.delete(model: PerformanceAnalysis.self)
        try context.delete(model: ConversationSession.self)
        try context.delete(model: CoachMessage.self)
        try context.delete(model: AgentTrace.self)
        try context.delete(model: AgentMutationReceipt.self)
        try context.delete(model: PersistentAgentEvent.self)
        try context.delete(model: AgentJob.self)
    }

    static func clear(
        personalContext: ModelContext,
        demoContext: ModelContext
    ) throws -> PersonalDataClearResult {
        let personalSnapshot = try PersonalDataSnapshot.capture(from: personalContext)
        let demoMedia = try PersonalDataSnapshot.capture(from: demoContext)
            .referencedMediaPaths
        let oldPersonalMedia = personalSnapshot.referencedMediaPaths
        let modelCount = personalSnapshot.modelCount

        try personalContext.transaction {
            try deleteAllModels(in: personalContext)
            try personalContext.save()
        }

        let deletedMediaCount = reclaimMedia(
            oldPersonalMedia.union(MediaStore.allStoredPaths()),
            excluding: demoMedia
        )
        return PersonalDataClearResult(
            deletedModelCount: modelCount,
            deletedMediaCount: deletedMediaCount
        )
    }

    static func reclaimMedia(
        _ candidates: Set<String>,
        excluding retained: Set<String>
    ) -> Int {
        let retainedIdentities = Set(retained.map(mediaIdentity))
        var count = 0
        for path in candidates
            where !retainedIdentities.contains(mediaIdentity(path))
            && MediaStore.removeStoredFile(at: path)
        {
            count += 1
        }
        return count
    }

    private static func mediaIdentity(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

extension PersonalDataSnapshot {
    var modelCount: Int {
        // Keep each sum tiny — CI's x86_64 type checker times out on long chains.
        var total = 0
        total += externalSyncCursors.count
        total += userProfiles.count
        total += gymProfiles.count
        total += gymEquipment.count
        total += gymMedia.count
        total += meals.count
        total += bodyEntries.count
        total += workouts.count
        total += exerciseDefinitions?.count ?? 0
        total += exerciseMergeRecords?.count ?? 0
        total += trainingPrograms?.count ?? 0
        total += workoutTemplateVersions?.count ?? 0
        total += templateExercises?.count ?? 0
        total += workoutSessions?.count ?? 0
        total += exercisePerformances?.count ?? 0
        total += workoutSets?.count ?? 0
        total += recommendationSnapshots?.count ?? 0
        total += performanceAnalyses?.count ?? 0
        total += sessions.count
        total += messages.count
        total += traces.count
        total += mutationReceipts.count
        total += agentJobs?.count ?? 0
        total += agentEvents?.count ?? 0
        return total
    }
}
