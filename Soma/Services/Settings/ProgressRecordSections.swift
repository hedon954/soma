import Foundation

/// 明细排序独立于时间正序的图表和能量投影。
enum ProgressRecordSections {
    struct Section: Identifiable {
        let date: Date
        let records: [ProgressHistoryRecord]
        var id: Date {
            date
        }
    }

    static func make(snapshot: ProgressHistorySnapshot, kind: ProgressRecentActivity.Kind) -> [Section] {
        let newestFirst = kind == .workout && [.month, .year].contains(snapshot.window.period)
        let sections = snapshot.days.compactMap { day -> Section? in
            let records = day.records.filter {
                $0.activity.kind == kind && (kind != .workout || !$0.isDailyActivity)
            }
            guard !records.isEmpty else { return nil }
            return Section(date: day.date, records: newestFirst ? records.sorted { $0.activity.date > $1.activity.date } : records)
        }
        return newestFirst ? sections.sorted { $0.date > $1.date } : sections
    }
}
