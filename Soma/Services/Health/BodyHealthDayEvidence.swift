import Foundation

enum BodyMassDayKey {
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func startOfDay(for dayKey: String, calendar: Calendar = .current) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
    }

    static func endOfDay(for dayStart: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
    }
}

struct BodyHealthDayMetricEvidence: Codable, Equatable, Sendable {
    var sampleUUID: UUID
    var date: Date
    var value: Double
    var sourceName: String
    var sourceBundleIdentifier: String
}

struct BodyHealthDayEvidence: Codable, Equatable, Sendable {
    var dayKey: String
    var timeZoneIdentifier: String
    var weight: BodyHealthDayMetricEvidence?
    var bodyFat: BodyHealthDayMetricEvidence?

    static func decode(_ data: Data) -> BodyHealthDayEvidence? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(BodyHealthDayEvidence.self, from: data)
    }

    func encode() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    var hasAnyMetric: Bool {
        weight != nil || bodyFat != nil
    }

    /// 仅当已有指标来源身份完全一致时返回该来源；多来源返回 nil，避免谎称单一品牌。
    var unifiedSource: (name: String, bundle: String)? {
        let metrics = [weight, bodyFat].compactMap { $0 }
        guard let first = metrics.first else { return nil }
        func identity(_ metric: BodyHealthDayMetricEvidence) -> String? {
            let bundle = metric.sourceBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bundle.isEmpty {
                return "bundle:\(bundle)"
            }
            let name = metric.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return "name:\(name)"
            }
            return nil
        }
        guard let firstID = identity(first), metrics.allSatisfy({ identity($0) == firstID }) else { return nil }
        return (first.sourceName, first.sourceBundleIdentifier)
    }

    var sourceCaptions: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for metric in [weight, bodyFat].compactMap({ $0 }) {
            let source = BodyMassKnownSource.resolve(
                name: metric.sourceName,
                bundleIdentifier: metric.sourceBundleIdentifier
            )
            let caption = source.listCaption
            if seen.insert(caption).inserted {
                result.append(caption)
            }
        }
        return result
    }
}

enum BodyHealthDayEvidenceCodec {
    static func latestMetric<Sample>(
        in samples: [Sample],
        date: (Sample) -> Date,
        uuid: (Sample) -> UUID
    ) -> Sample? {
        samples.max { lhs, rhs in
            let leftDate = date(lhs)
            let rightDate = date(rhs)
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            return uuid(lhs).uuidString < uuid(rhs).uuidString
        }
    }

    static func isLater(date: Date, uuid: UUID, than existing: BodyHealthDayMetricEvidence) -> Bool {
        if date != existing.date {
            return date > existing.date
        }
        return uuid.uuidString >= existing.sampleUUID.uuidString
    }
}
