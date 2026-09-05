import Foundation
import HealthKit

struct HealthEnergyHistory: Sendable {
    var days: [EnergyHistoryDay] = []
    var isAvailable = true
    var coverageWasLimited = false
}

/// One-shot, cancellation-aware queries. A source is kept separate through aggregation and calibration.
struct HealthEnergyHistoryReader {
    private let store = HKHealthStore()

    func read(from start: Date, to end: Date, calendar: Calendar = .current) async throws -> HealthEnergyHistory {
        guard HKHealthStore.isHealthDataAvailable() else { return .init(isAvailable: false) }
        guard start < end else { return .init() }
        try Task.checkCancellation()
        async let restingResult = statistics(.basalEnergyBurned, start: start, end: end, calendar: calendar)
        async let activeResult = statistics(.activeEnergyBurned, start: start, end: end, calendar: calendar)
        let (resting, active) = try await (restingResult, activeResult)
        var result = HealthEnergyHistory()
        var cursor = start
        // Coverage samples are bounded by a week; do not retain a year's raw health samples.
        while cursor < end {
            try Task.checkCancellation()
            let weekEnd = min(calendar.date(byAdding: .day, value: 7, to: cursor) ?? end, end)
            guard weekEnd > cursor else { break }
            let sampleLimit = 10000
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(
                    type: HKQuantityType(.basalEnergyBurned),
                    predicate: predicate(start: cursor, end: weekEnd)
                )],
                sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate)],
                limit: sampleLimit
            )
            let samples = try await descriptor.result(for: store)
            try Task.checkCancellation()
            let limited = samples.count == sampleLimit
            result.coverageWasLimited = result.coverageWasLimited || limited
            let intervals = Dictionary(grouping: samples, by: { $0.sourceRevision.source.bundleIdentifier }).mapValues {
                $0.map { DateInterval(start: $0.startDate, end: $0.endDate) }
            }
            while cursor < weekEnd {
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: cursor) ?? weekEnd
                guard dayEnd > cursor else { break }
                let restingDay = resting.statistics(for: cursor)
                let activeDay = active.statistics(for: cursor)
                let sources = Set(restingDay?.sources ?? []).union(activeDay?.sources ?? [])
                for source in sources.sorted(by: { $0.bundleIdentifier < $1.bundleIdentifier }) {
                    let sourceID = source.bundleIdentifier
                    let covered = limited ? 0 : EnergySampleCoverage.fraction(
                        intervals[sourceID] ?? [], within: DateInterval(start: cursor, end: dayEnd)
                    )
                    result.days.append(.init(
                        date: cursor,
                        restingKilocalories: restingDay?.sumQuantity(for: source)?.doubleValue(for: .kilocalorie()),
                        activeKilocalories: activeDay?.sumQuantity(for: source)?.doubleValue(for: .kilocalorie()),
                        sourceID: sourceID, sourceName: source.name, coverage: covered
                    ))
                }
                cursor = dayEnd
            }
        }
        return result
    }

    private func statistics(
        _ identifier: HKQuantityTypeIdentifier, start: Date, end: Date, calendar: Calendar
    ) async throws -> HKStatisticsCollection {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate(start: start, end: end)),
            options: [.cumulativeSum, .separateBySource],
            anchorDate: start,
            intervalComponents: DateComponents(calendar: calendar, timeZone: calendar.timeZone, day: 1)
        )
        return try await descriptor.result(for: store)
    }

    private func predicate(start: Date, end: Date) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end),
            NSCompoundPredicate(notPredicateWithSubpredicate:
                HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyWasUserEntered, allowedValues: [true]))
        ])
    }
}

enum EnergySampleCoverage {
    /// Interval union: overlapping and replayed samples must never amplify coverage.
    static func fraction(_ samples: [DateInterval], within day: DateInterval) -> Double {
        guard day.duration > 0 else { return 0 }
        let clipped = samples.compactMap { sample -> DateInterval? in
            let start = max(sample.start, day.start)
            let end = min(sample.end, day.end)
            return start < end ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var covered: TimeInterval = 0
        var cursor = day.start
        for sample in clipped {
            covered += max(0, sample.end.timeIntervalSince(max(cursor, sample.start)))
            cursor = max(cursor, sample.end)
        }
        return min(1, covered / day.duration)
    }
}
