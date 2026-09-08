import Foundation
import Observation
import SwiftData

struct InsightsSnapshotCacheKey: Hashable, Sendable {
    let day: Date
    let timeZoneIdentifier: String
    let dataRevision: Int
}

/// 只管理快照版本，不持有 SwiftData 模型或 SwiftUI 状态。View 用返回的 key
/// 启动可取消任务；旧请求完成时必须先通过 `acceptsCompletion`，不能覆盖新 revision。
@Observable
@MainActor
final class InsightsSnapshotRevisionState {
    private(set) var dataRevision = 0
    private(set) var loadedKey: InsightsSnapshotCacheKey?

    func markDataChanged() {
        dataRevision &+= 1
    }

    func requestKey(
        excluding requestedKey: InsightsSnapshotCacheKey?,
        force: Bool = false,
        now: Date = .now,
        calendar sourceCalendar: Calendar = .current
    ) -> InsightsSnapshotCacheKey? {
        let key = currentKey(now: now, calendar: sourceCalendar)
        guard force || (loadedKey != key && requestedKey != key) else {
            return nil
        }
        return key
    }

    func acceptsCompletion(
        for key: InsightsSnapshotCacheKey,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard key == currentKey(now: now, calendar: calendar) else {
            return false
        }
        loadedKey = key
        return true
    }

    func currentKey(
        now: Date = .now,
        calendar sourceCalendar: Calendar = .current
    ) -> InsightsSnapshotCacheKey {
        var calendar = sourceCalendar
        calendar.timeZone = sourceCalendar.timeZone
        return InsightsSnapshotCacheKey(
            day: calendar.startOfDay(for: now),
            timeZoneIdentifier: calendar.timeZone.identifier,
            dataRevision: dataRevision
        )
    }
}

enum InsightsSnapshotLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

enum InsightsCountQueries {
    static func recordCounts(in modelContext: ModelContext) throws -> InsightsRecordCounts {
        try InsightsRecordCounts(
            workouts: modelContext.fetchCount(FetchDescriptor<WorkoutEntry>()),
            meals: modelContext.fetchCount(FetchDescriptor<MealEntry>()),
            bodyEntries: modelContext.fetchCount(FetchDescriptor<BodyEntry>())
        )
    }

    static func successfulFootprintCount(in modelContext: ModelContext) throws -> Int {
        let succeeded = AgentTraceStatus.succeeded.rawValue
        return try modelContext.fetchCount(FetchDescriptor<CoachMessage>(
            predicate: #Predicate {
                $0.isFromCoach
                    && $0.agentStatusRaw == succeeded
                    && $0.turnID != nil
            }
        ))
    }
}
