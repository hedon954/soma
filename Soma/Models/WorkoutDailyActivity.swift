import Foundation

extension WorkoutEntry {
    /// 日常活动以 `externalID` 的 `daily:` 前缀识别（ADR 0146）。
    /// 旧记录同样使用 `daily:yyyy-MM-dd`，无需依赖 externalSource。
    var isDailyActivity: Bool {
        externalID?.hasPrefix("daily:") == true
    }

    var dailyActivity: DailyActivitySummary? {
        guard let dailyActivityData else { return nil }
        return try? JSONDecoder().decode(DailyActivitySummary.self, from: dailyActivityData)
    }

    var dailyActivityWinningSource: DailyActivityWinningSource {
        dailyActivity?.resolvedWinningSource ?? .appleHealth
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
