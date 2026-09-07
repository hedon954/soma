import Foundation
import SwiftData

/// 已画过的原位记录卡按业务 ID 常驻。切 Tab／Session 只换查询窗口，
/// 命中时第一帧就用缓存，不再 1pt 占位后撑开。
@MainActor
enum ChatRecordCardCache {
    private static let countLimit = 128
    private static var workouts: [Int64: CachedWorkout] = [:]
    private static var meals: [Int64: CachedModel<MealEntry>] = [:]
    private static var bodies: [Int64: CachedModel<BodyEntry>] = [:]
    private static var gyms: [Int64: CachedModel<GymProfile>] = [:]
    private static var insertionOrder: [String] = []
    private static var missingKeys: Set<String> = []

    private struct CachedWorkout {
        let contextID: ObjectIdentifier
        let entry: WorkoutEntry
        let profile: ExerciseLoggingProfileSnapshot?
    }

    private struct CachedModel<Record> {
        let contextID: ObjectIdentifier
        let record: Record
    }

    static var cachedCount: Int {
        insertionOrder.count
    }

    static func removeAll() {
        workouts.removeAll(keepingCapacity: false)
        meals.removeAll(keepingCapacity: false)
        bodies.removeAll(keepingCapacity: false)
        gyms.removeAll(keepingCapacity: false)
        insertionOrder.removeAll(keepingCapacity: false)
        missingKeys.removeAll(keepingCapacity: false)
    }

    static func retainRecent(maxCount: Int = 64) {
        guard insertionOrder.count > maxCount else { return }
        let kept = Array(insertionOrder.suffix(maxCount))
        let keptSet = Set(kept)
        insertionOrder = kept
        workouts = workouts.filter { keptSet.contains(key(.workout, $0.key)) }
        meals = meals.filter { keptSet.contains(key(.meal, $0.key)) }
        bodies = bodies.filter { keptSet.contains(key(.body, $0.key)) }
        gyms = gyms.filter { keptSet.contains(key(.gym, $0.key)) }
    }

    static func workout(
        _ id: Int64,
        in context: ModelContext
    ) -> (WorkoutEntry, ExerciseLoggingProfileSnapshot?)? {
        guard let cached = workouts[id],
              cached.contextID == ObjectIdentifier(context)
        else {
            return nil
        }
        return (cached.entry, cached.profile)
    }

    static func meal(_ id: Int64, in context: ModelContext) -> MealEntry? {
        model(meals[id], in: context)
    }

    static func body(_ id: Int64, in context: ModelContext) -> BodyEntry? {
        model(bodies[id], in: context)
    }

    static func gym(_ id: Int64, in context: ModelContext) -> GymProfile? {
        model(gyms[id], in: context)
    }

    static func canRender(
        _ references: [AgentRecordReference],
        in context: ModelContext
    ) -> Bool {
        references.allSatisfy { reference in
            switch reference.recordType {
            case ConversationIntent.workout.rawValue:
                workout(reference.recordID, in: context) != nil
                    || missingKeys.contains(key(.workout, reference.recordID))
            case ConversationIntent.meal.rawValue:
                meal(reference.recordID, in: context) != nil
                    || missingKeys.contains(key(.meal, reference.recordID))
            case ConversationIntent.body.rawValue:
                body(reference.recordID, in: context) != nil
                    || missingKeys.contains(key(.body, reference.recordID))
            case ConversationIntent.gym.rawValue:
                gym(reference.recordID, in: context) != nil
                    || missingKeys.contains(key(.gym, reference.recordID))
            default:
                true
            }
        }
    }

    static func prefetch(
        _ references: [AgentRecordReference],
        in context: ModelContext
    ) {
        for reference in references {
            switch reference.recordType {
            case ConversationIntent.workout.rawValue:
                guard workout(reference.recordID, in: context) == nil else { continue }
                if let loaded = fetchWorkout(reference.recordID, in: context) {
                    store(
                        workout: loaded,
                        profile: linkedProfile(for: loaded, in: context),
                        in: context
                    )
                } else {
                    missingKeys.insert(key(.workout, reference.recordID))
                }
            case ConversationIntent.meal.rawValue:
                guard meal(reference.recordID, in: context) == nil else { continue }
                if let loaded = fetchMeal(reference.recordID, in: context) {
                    store(meal: loaded, in: context)
                } else {
                    missingKeys.insert(key(.meal, reference.recordID))
                }
            case ConversationIntent.body.rawValue:
                guard body(reference.recordID, in: context) == nil else { continue }
                if let loaded = fetchBody(reference.recordID, in: context) {
                    store(body: loaded, in: context)
                } else {
                    missingKeys.insert(key(.body, reference.recordID))
                }
            case ConversationIntent.gym.rawValue:
                guard gym(reference.recordID, in: context) == nil else { continue }
                if let loaded = fetchGym(reference.recordID, in: context) {
                    store(gym: loaded, in: context)
                } else {
                    missingKeys.insert(key(.gym, reference.recordID))
                }
            default:
                continue
            }
        }
    }

    static func store(
        workout: WorkoutEntry,
        profile: ExerciseLoggingProfileSnapshot?,
        in context: ModelContext
    ) {
        guard let id = workout.businessID else { return }
        workouts[id] = CachedWorkout(
            contextID: ObjectIdentifier(context),
            entry: workout,
            profile: profile
        )
        missingKeys.remove(key(.workout, id))
        remember(key(.workout, id))
    }

    static func store(meal: MealEntry, in context: ModelContext) {
        guard let id = meal.businessID else { return }
        meals[id] = CachedModel(contextID: ObjectIdentifier(context), record: meal)
        missingKeys.remove(key(.meal, id))
        remember(key(.meal, id))
    }

    static func store(body: BodyEntry, in context: ModelContext) {
        guard let id = body.businessID else { return }
        bodies[id] = CachedModel(contextID: ObjectIdentifier(context), record: body)
        missingKeys.remove(key(.body, id))
        remember(key(.body, id))
    }

    static func store(gym: GymProfile, in context: ModelContext) {
        guard let id = gym.businessID else { return }
        gyms[id] = CachedModel(contextID: ObjectIdentifier(context), record: gym)
        missingKeys.remove(key(.gym, id))
        remember(key(.gym, id))
    }

    static func linkedProfile(
        for workout: WorkoutEntry,
        in context: ModelContext
    ) -> ExerciseLoggingProfileSnapshot? {
        let definition = try? ExerciseLibraryStore.linkedExercise(
            for: workout,
            in: context,
            persist: false,
            allowCreate: false
        )
        return definition.map(ExerciseLoggingProfileSnapshot.init)
    }

    private static func model<Record>(
        _ cached: CachedModel<Record>?,
        in context: ModelContext
    ) -> Record? {
        guard let cached, cached.contextID == ObjectIdentifier(context) else {
            return nil
        }
        return cached.record
    }

    private static func fetchWorkout(_ id: Int64, in context: ModelContext) -> WorkoutEntry? {
        var descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.businessID == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchMeal(_ id: Int64, in context: ModelContext) -> MealEntry? {
        var descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.businessID == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchBody(_ id: Int64, in context: ModelContext) -> BodyEntry? {
        var descriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.businessID == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fetchGym(_ id: Int64, in context: ModelContext) -> GymProfile? {
        var descriptor = FetchDescriptor<GymProfile>(
            predicate: #Predicate { $0.businessID == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func remember(_ key: String) {
        if let index = insertionOrder.firstIndex(of: key) {
            insertionOrder.remove(at: index)
        }
        insertionOrder.append(key)
        while insertionOrder.count > countLimit {
            evict(insertionOrder.removeFirst())
        }
    }

    private static func evict(_ key: String) {
        let parts = key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let id = Int64(parts[1]) else { return }
        switch String(parts[0]) {
        case ConversationIntent.workout.rawValue: workouts.removeValue(forKey: id)
        case ConversationIntent.meal.rawValue: meals.removeValue(forKey: id)
        case ConversationIntent.body.rawValue: bodies.removeValue(forKey: id)
        case ConversationIntent.gym.rawValue: gyms.removeValue(forKey: id)
        default: break
        }
    }

    private static func key(_ type: ConversationIntent, _ id: Int64) -> String {
        "\(type.rawValue):\(id)"
    }
}

@MainActor
enum CoachMessagePagePaint {
    static func references(in messages: [CoachMessage]) -> [AgentRecordReference] {
        var seen = Set<String>()
        var result: [AgentRecordReference] = []
        for message in messages {
            for reference in AgentTurnRecordReferences.make(
                from: CoachMessageRenderPayloadCache.payload(for: message).turnItems
            ) where seen.insert(reference.identityKey).inserted {
                result.append(reference)
            }
        }
        return result
    }

    static func settledMarkdowns(in messages: [CoachMessage], liveMessageID: UUID?) -> [String] {
        messages.compactMap { message in
            guard message.isFromCoach, message.id != liveMessageID else { return nil }
            let text = CoachMessageRenderPayloadCache.payload(for: message).visibleText
            return text.isEmpty ? nil : text
        }
    }

    static func markdownsAreWarm(_ texts: [String]) -> Bool {
        texts.allSatisfy { CoachTextRenderCache.completedText(for: $0) != nil }
    }

    static func warmMarkdown(_ texts: [String]) async {
        for text in texts {
            if CoachTextRenderCache.completedText(for: text) != nil {
                continue
            }
            let source = text
            let preparation = await Task.detached(priority: .userInitiated) {
                try? CoachTextRenderPreparation.make(for: source)
            }.value
            if let preparation {
                _ = CoachTextRenderCache.store(preparation, for: source)
            }
        }
    }
}
