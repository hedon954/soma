import Foundation

extension WorkoutEntry {
    var isDailyActivity: Bool {
        externalSource == "appleHealth" && externalID?.hasPrefix("daily:") == true
    }

    var dailyActivity: DailyActivitySummary? {
        guard let dailyActivityData else { return nil }
        return try? JSONDecoder().decode(DailyActivitySummary.self, from: dailyActivityData)
    }

    var source: String? {
        guard let summary = dailyActivity else { return nil }
        let names = Set(summary.metrics.values.flatMap { $0.source?.sources.map(\.name) ?? [] }).sorted()
        return names.isEmpty ? nil : names.joined(separator: "、")
    }

    var dailyActivitySummary: String? {
        guard let summary = dailyActivity else { return nil }
        return DailyActivityMetricKind.allCases.compactMap { kind in
            summary[kind].value.map { "\(kind.displayValue($0)) \(kind.unit)" }
        }.joined(separator: " · ")
    }
}
