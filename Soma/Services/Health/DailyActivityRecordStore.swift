import Foundation
import SwiftData

@MainActor
enum DailyActivityRecordStore {
    static func replace(_ incoming: [DailyActivitySummary], in context: ModelContext) throws {
        try context.transaction {
            for summary in incoming {
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(identifier: summary.key.timeZoneIdentifier)
                formatter.dateFormat = "yyyy-MM-dd"
                let externalID = "daily:" + formatter.string(from: summary.key.start)
                let key = "appleHealth:" + externalID
                var query = FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.projectionKey == key })
                query.fetchLimit = 1
                let existing = try context.fetch(query).first
                var merged = DailyActivitySummary(key: summary.key)
                for kind in DailyActivityMetricKind.allCases {
                    let metric = summary[kind]
                    merged[kind] = [.loading, .failed].contains(metric.availability)
                        ? existing?.dailyActivity?[kind] ?? DailyActivityMetric() : metric
                }
                guard merged.metrics.values.contains(where: { $0.value != nil }) else {
                    if let existing {
                        context.delete(existing)
                    }
                    continue
                }
                let entry = existing ?? WorkoutEntry(date: summary.key.start, exercise: "日常活动", externalSource: "appleHealth", externalID: externalID, projectionKey: key)
                if existing == nil {
                    context.insert(entry)
                    try BusinessIDAllocator.assign(entry, namespace: "workout", in: context)
                }
                entry.date = summary.key.start
                entry.dailyActivityData = try JSONEncoder().encode(merged)
                entry.estimatedCalories = merged[.activeEnergy].value.flatMap { Int(exactly: $0.rounded()) }
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }
}
