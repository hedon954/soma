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
        try context.delete(model: WorkoutEntry.self)
        try context.delete(model: ConversationSession.self)
        try context.delete(model: CoachMessage.self)
        try context.delete(model: AgentTrace.self)
        try context.delete(model: AgentMutationReceipt.self)
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
        externalSyncCursors.count
            + userProfiles.count
            + gymProfiles.count
            + gymEquipment.count
            + gymMedia.count
            + meals.count
            + bodyEntries.count
            + workouts.count
            + sessions.count
            + messages.count
            + traces.count
            + mutationReceipts.count
    }
}
