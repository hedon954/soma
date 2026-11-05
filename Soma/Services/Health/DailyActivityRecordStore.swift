import Foundation
import SwiftData

@MainActor
enum DailyActivityRecordStore {
    /// 稳定日身份：沿用既有 `appleHealth:daily:yyyy-MM-dd` projectionKey，避免换源时拆成两条。
    static func projectionKey(for externalID: String) -> String {
        "appleHealth:" + externalID
    }

    static func externalID(for key: DailyActivityDayKey) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: key.timeZoneIdentifier)
        formatter.dateFormat = "yyyy-MM-dd"
        return "daily:" + formatter.string(from: key.start)
    }

    static func replace(_ incoming: [DailyActivitySummary], in context: ModelContext) throws {
        try context.transaction {
            for summary in incoming {
                let externalID = Self.externalID(for: summary.key)
                let key = projectionKey(for: externalID)
                var query = FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.projectionKey == key })
                query.fetchLimit = 1
                let existing = try context.fetch(query).first
                var merged = DailyActivitySummary(key: summary.key, winningSource: summary.winningSource)
                for kind in DailyActivityMetricKind.allCases {
                    let metric = summary[kind]
                    merged[kind] = [.loading, .failed].contains(metric.availability)
                        ? existing?.dailyActivity?[kind] ?? DailyActivityMetric() : metric
                }
                if merged.winningSource == nil {
                    merged.winningSource = existing?.dailyActivity?.winningSource ?? .appleHealth
                }
                guard merged.metrics.values.contains(where: { $0.value != nil }) else {
                    if let existing {
                        context.delete(existing)
                    }
                    continue
                }
                let winning = merged.resolvedWinningSource
                let entry = existing ?? WorkoutEntry(
                    date: summary.key.start,
                    exercise: "日常活动",
                    externalSource: winning.externalSource,
                    externalID: externalID,
                    projectionKey: key
                )
                if existing == nil {
                    context.insert(entry)
                    try BusinessIDAllocator.assign(entry, namespace: "workout", in: context)
                }
                entry.date = summary.key.start
                entry.externalSource = winning.externalSource
                entry.externalID = externalID
                entry.dailyActivityData = try JSONEncoder().encode(merged)
                entry.estimatedCalories = merged[.activeEnergy].value.flatMap { Int(exactly: $0.rounded()) }
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }
}
