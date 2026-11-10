import Foundation
import SwiftData

/// Display-layer grouping of one or two `BodyEntry` samples that represent a
/// single measurement. Persistence stays one HealthKit sample per `BodyEntry`.
struct BodyHistoryMeasurement: Identifiable, Equatable {
    /// Weight entry id when present, otherwise the only entry id.
    var id: UUID {
        weightEntry?.id ?? entries[0].id
    }

    let entries: [BodyEntry]

    var date: Date {
        primary.date
    }

    var primary: BodyEntry {
        entries[0]
    }

    var weightEntry: BodyEntry? {
        entries.first { $0.weight != nil }
    }

    var bodyFatEntry: BodyEntry? {
        entries.first { $0.bodyFat != nil }
    }

    var weight: Double? {
        entries.compactMap(\.weight).first
    }

    var bodyFat: Double? {
        entries.compactMap(\.bodyFat).first
    }

    var isHealthImported: Bool {
        entries.allSatisfy(\.isHealthImported)
    }

    var sourceName: String? {
        entries.compactMap(\.sourceName).first { !$0.isEmpty }
    }

    var sourceBundleIdentifier: String? {
        entries.compactMap(\.sourceBundleIdentifier).first { !$0.isEmpty }
    }

    var notes: String? {
        entries.compactMap(\.notes).first { !$0.isEmpty }
    }

    var imagePath: String? {
        entries.compactMap(\.imagePath).first { !$0.isEmpty }
    }

    var analysis: String? {
        entries.compactMap(\.analysis).first { !$0.isEmpty }
    }

    var hasMedia: Bool {
        entries.contains { $0.imagePath != nil || !$0.mediaAttachments.isEmpty }
    }

    var memberIDs: Set<UUID> {
        Set(entries.map(\.id))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entries.map(\.id) == rhs.entries.map(\.id)
    }
}

enum BodyMassMeasurementPairing {
    /// Unix-second bucket of a sample date. Same second is the only accepted
    /// time evidence that two imported samples belong to one measurement.
    static func sampleSecond(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.towardZero))
    }

    /// Source identity used for pairing. Prefer a non-empty bundle identifier;
    /// fall back to a non-empty source name. Missing identity cannot pair.
    static func sourceIdentity(for entry: BodyEntry) -> String? {
        if let bundle = entry.sourceBundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !bundle.isEmpty
        {
            return "bundle:\(bundle)"
        }
        if let name = entry.sourceName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty
        {
            return "name:\(name)"
        }
        return nil
    }

    /// Groups complementary HealthKit imports that share source identity and
    /// the same Unix second. Manual rows and inconclusive samples stay single.
    static func measurements(from entries: [BodyEntry]) -> [BodyHistoryMeasurement] {
        var buckets: [String: (weights: [BodyEntry], fats: [BodyEntry])] = [:]
        var leftovers: [BodyEntry] = []

        for entry in entries {
            if canPair(entry), let source = sourceIdentity(for: entry) {
                let key = "\(source)#\(sampleSecond(entry.date))"
                var bucket = buckets[key] ?? ([], [])
                if entry.weight != nil {
                    bucket.weights.append(entry)
                } else {
                    bucket.fats.append(entry)
                }
                buckets[key] = bucket
            } else {
                leftovers.append(entry)
            }
        }

        var byEntryID: [UUID: BodyHistoryMeasurement] = [:]
        for bucket in buckets.values {
            let weights = bucket.weights.sorted { $0.id.uuidString < $1.id.uuidString }
            let fats = bucket.fats.sorted { $0.id.uuidString < $1.id.uuidString }
            let pairCount = min(weights.count, fats.count)
            for index in 0 ..< pairCount {
                let members = [weights[index], fats[index]]
                    .sorted { $0.id.uuidString < $1.id.uuidString }
                let measurement = BodyHistoryMeasurement(entries: members)
                byEntryID[weights[index].id] = measurement
                byEntryID[fats[index].id] = measurement
            }
            leftovers.append(contentsOf: weights.dropFirst(pairCount))
            leftovers.append(contentsOf: fats.dropFirst(pairCount))
        }

        for entry in leftovers {
            byEntryID[entry.id] = BodyHistoryMeasurement(entries: [entry])
        }

        var seen = Set<UUID>()
        var ordered: [BodyHistoryMeasurement] = []
        for entry in entries {
            guard let measurement = byEntryID[entry.id] else { continue }
            if seen.insert(measurement.id).inserted {
                ordered.append(measurement)
            }
        }
        return ordered
    }

    static func measurement(
        for entry: BodyEntry,
        among entries: [BodyEntry]
    ) -> BodyHistoryMeasurement {
        measurements(from: entries).first { $0.memberIDs.contains(entry.id) }
            ?? BodyHistoryMeasurement(entries: [entry])
    }

    static func measurement(for entry: BodyEntry, in context: ModelContext) -> BodyHistoryMeasurement {
        measurement(for: entry, among: peers(for: entry, in: context))
    }

    private static func canPair(_ entry: BodyEntry) -> Bool {
        guard entry.isHealthImported else { return false }
        switch (entry.weight != nil, entry.bodyFat != nil) {
        case (true, false), (false, true):
            return true
        default:
            return false
        }
    }

    private static func peers(for entry: BodyEntry, in context: ModelContext) -> [BodyEntry] {
        let start = Date(timeIntervalSince1970: TimeInterval(sampleSecond(entry.date)))
        let end = start.addingTimeInterval(1)
        let predicate = #Predicate<BodyEntry> { candidate in
            candidate.date >= start && candidate.date < end
        }
        let descriptor = FetchDescriptor<BodyEntry>(predicate: predicate)
        let fetched = (try? context.fetch(descriptor)) ?? []
        if fetched.contains(where: { $0.id == entry.id }) {
            return fetched
        }
        return fetched + [entry]
    }
}
