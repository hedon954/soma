import Foundation

enum EnergyTrainingGrouping {
    static func sessions(_ events: [EnergyTrainingEvent]) -> [EnergyTrainingEvent] {
        let grouped = Dictionary(grouping: events, by: { $0.sessionIdentity ?? $0.id })
        return grouped.keys.sorted().compactMap { key in
            guard let items = grouped[key]?.sorted(by: { $0.id < $1.id }), let first = items.first else { return nil }
            guard first.sessionIdentity != nil else { return first }
            let start = items.compactMap(\.start).min(), end = items.compactMap(\.end).max()
            let duration: Double? = if let start, let end, end > start {
                end.timeIntervalSince(start) / 3600
            } else if items.allSatisfy({ $0.durationHours != nil }) {
                items.compactMap(\.durationHours).reduce(0, +)
            } else {
                nil
            }
            return .init(id: key, source: "Soma", activityType: "整场训练（\(items.count) 个动作）", scope: .active,
                         kilocalories: nil, met: nil, durationHours: duration, start: start, end: end,
                         sessionIdentity: key, components: items)
        }
    }
}
