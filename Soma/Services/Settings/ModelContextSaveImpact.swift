import Foundation
import SwiftData

/// SwiftData 的保存通知包含精确 PersistentIdentifier。只在相关业务模型变化时
/// 让派生快照变脏，避免聊天 token、Agent Event 等高频保存触发训练聚合。
enum ModelContextSaveImpact {
    private static let coachSuggestionEntities: Set<String> = entityNames([
        WorkoutEntry.self,
        ExerciseDefinition.self,
        ExercisePerformance.self,
        WorkoutSession.self,
        WorkoutSet.self
    ])
    private static let insightsEntities: Set<String> = entityNames([
        WorkoutEntry.self,
        MealEntry.self,
        BodyEntry.self,
        GymProfile.self,
        GymEquipment.self,
        UserProfile.self,
        ExerciseDefinition.self,
        ExercisePerformance.self,
        WorkoutSession.self,
        WorkoutSet.self,
        WorkoutEffort.self
    ])
    private static let exerciseHistoryEntities: Set<String> = entityNames([
        WorkoutEntry.self,
        ExercisePerformance.self,
        WorkoutSet.self,
        ExerciseDefinition.self,
        WorkoutSession.self
    ])
    private static let exerciseLibraryRecentEntities: Set<String> = entityNames([
        WorkoutEntry.self
    ])

    static func affectsCoachSuggestions(
        _ notification: Notification,
        in modelContext: ModelContext
    ) -> Bool {
        affects(notification, entities: coachSuggestionEntities)
    }

    static func affectsInsights(
        _ notification: Notification,
        in modelContext: ModelContext
    ) -> Bool {
        guard belongsToSameContainer(notification, as: modelContext) else {
            return false
        }
        return affects(notification, entities: insightsEntities)
    }

    static func affectsExerciseHistory(
        _ notification: Notification,
        exerciseID: UUID,
        in modelContext: ModelContext
    ) -> Bool {
        affects(
            notification,
            entities: exerciseHistoryEntities,
            in: modelContext
        ) { model in
            if let workout = model as? WorkoutEntry {
                return workout.exerciseID == exerciseID
            }
            if let performance = model as? ExercisePerformance {
                return performance.exerciseID == exerciseID
            }
            if let set = model as? WorkoutSet {
                return set.performance?.exerciseID == exerciseID
            }
            if let definition = model as? ExerciseDefinition {
                return definition.id == exerciseID
            }
            // Session time/status changes affect the presentation of its
            // exercise history, but happen far less often than chat saves.
            return model is WorkoutSession
        }
    }

    static func affectsExerciseLibraryRecents(
        _ notification: Notification,
        in modelContext: ModelContext
    ) -> Bool {
        affects(notification, entities: exerciseLibraryRecentEntities)
    }

    private static func affects(
        _ notification: Notification,
        entities: Set<String>
    ) -> Bool {
        let userInfo = notification.userInfo ?? [:]
        if userInfo[ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue] != nil {
            return true
        }
        return changedIdentifiers(in: userInfo).contains {
            entities.contains($0.entityName)
        }
    }

    private static func belongsToSameContainer(
        _ notification: Notification,
        as modelContext: ModelContext
    ) -> Bool {
        guard let sourceContext = notification.object as? ModelContext else {
            // 测试或维护路径可能手工发送不带 object 的 invalidated-all 通知；
            // 无法判定来源时保守失效，不能让页面永久显示旧数据。
            return true
        }
        return sourceContext.container === modelContext.container
    }

    private static func affects(
        _ notification: Notification,
        entities: Set<String>,
        in modelContext: ModelContext,
        where isRelevant: (any PersistentModel) -> Bool
    ) -> Bool {
        let userInfo = notification.userInfo ?? [:]
        if userInfo[ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue] != nil {
            return true
        }

        let deleted = identifiers(for: .deletedIdentifiers, in: userInfo)
        if deleted.contains(where: { entities.contains($0.entityName) }) {
            // 删除后无法可靠读取 exerciseID；只对相关实体保守失效，
            // 聊天和 Agent Event 删除不会再波及动作详情。
            return true
        }

        let changed = identifiers(for: .insertedIdentifiers, in: userInfo)
            + identifiers(for: .updatedIdentifiers, in: userInfo)
        return changed.lazy
            .filter { entities.contains($0.entityName) }
            .contains { identifier in
                isRelevant(modelContext.model(for: identifier))
            }
    }

    private static func changedIdentifiers(
        in userInfo: [AnyHashable: Any]
    ) -> [PersistentIdentifier] {
        identifiers(for: .insertedIdentifiers, in: userInfo)
            + identifiers(for: .updatedIdentifiers, in: userInfo)
            + identifiers(for: .deletedIdentifiers, in: userInfo)
    }

    private static func entityNames(
        _ types: [any PersistentModel.Type]
    ) -> Set<String> {
        // Soma 当前模型没有自定义 SwiftData entity name；类型名与
        // PersistentIdentifier.entityName 一致，且该路径保持 iOS 17 可用。
        Set(types.map { String(describing: $0) })
    }

    private static func identifiers(
        for key: ModelContext.NotificationKey,
        in userInfo: [AnyHashable: Any]
    ) -> [PersistentIdentifier] {
        if let values = userInfo[key.rawValue] as? Set<PersistentIdentifier> {
            return Array(values)
        }
        return userInfo[key.rawValue] as? [PersistentIdentifier] ?? []
    }
}
