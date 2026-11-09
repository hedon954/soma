import Foundation
import HealthKit

protocol DailyActivityReading: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func updates(in window: DailyActivityWindow) async -> AsyncStream<DailyActivityUpdate>
}

actor HealthKitDailyActivityReader: DailyActivityReading {
    nonisolated var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var store: HKHealthStore?

    private func healthStore() -> HKHealthStore {
        if let store {
            return store
        }
        let result = HKHealthStore()
        store = result
        return result
    }

    static let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = Set(DailyActivityMetricKind.allCases.map { quantityType($0) })
        types.insert(HKObjectType.workoutType())
        types.insert(HKQuantityType(.bodyMass))
        types.insert(HKQuantityType(.bodyFatPercentage))
        return types
    }()

    static func quantityType(_ kind: DailyActivityMetricKind) -> HKQuantityType {
        switch kind {
        case .steps: HKQuantityType(.stepCount)
        case .walkingRunningDistance: HKQuantityType(.distanceWalkingRunning)
        case .activeEnergy: HKQuantityType(.activeEnergyBurned)
        }
    }

    private static func unit(_ kind: DailyActivityMetricKind) -> HKUnit {
        switch kind {
        case .steps: .count()
        case .walkingRunningDistance: .meter()
        case .activeEnergy: .kilocalorie()
        }
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw DailyActivityReadError.unavailable }
        try await healthStore().requestAuthorization(toShare: [], read: Self.readTypes)
    }

    func updates(in window: DailyActivityWindow) -> AsyncStream<DailyActivityUpdate> {
        guard isAvailable else {
            return AsyncStream { continuation in
                for kind in DailyActivityMetricKind.allCases {
                    continuation.yield(.failure(kind))
                }
                continuation.finish()
            }
        }
        let healthStore = healthStore()
        return AsyncStream { continuation in
            let owner = Task {
                await withTaskGroup(of: Void.self) { group in
                    for kind in DailyActivityMetricKind.allCases {
                        group.addTask {
                            await Self.observe(kind, window: window, store: healthStore, continuation: continuation)
                        }
                    }
                    group.addTask {
                        await Self.readTraining(window: window, store: healthStore, continuation: continuation)
                    }
                    await group.waitForAll()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in owner.cancel() }
        }
    }

    private static func readTraining(
        window: DailyActivityWindow, store: HKHealthStore,
        continuation: AsyncStream<DailyActivityUpdate>.Continuation
    ) async {
        guard let first = window.days.first, let last = window.days.last else { return }
        do {
            let predicate = HKQuery.predicateForSamples(withStart: first.start, end: last.end)
            let workouts = try await HKSampleQueryDescriptor(
                predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\HKWorkout.startDate)]
            ).result(for: store)
            var evidence: [HealthActivityDayEvidence] = []
            for day in window.days {
                try Task.checkCancellation()
                let matching = workouts.filter { $0.startDate < day.end && $0.endDate > day.start }
                let intervals = EnergyTimeInterval.union(matching.map { .init(start: $0.startDate, end: $0.endDate) } + window.localTrainingIntervals, within: day)
                let events = matching.map { workout in
                    let contained = workout.startDate >= day.start && workout.endDate <= day.end
                    return EnergyTrainingEvent(
                        id: "health:" + workout.uuid.uuidString, source: workout.sourceRevision.source.name,
                        activityType: workoutName(workout.workoutActivityType),
                        scope: contained ? .active : .unknown,
                        kilocalories: contained ? workout.statistics(for: quantityType(.activeEnergy))?.sumQuantity()?.doubleValue(for: .kilocalorie()) : nil,
                        met: nil, durationHours: contained ? workout.duration / 3600 : nil,
                        start: workout.startDate, end: workout.endDate
                    )
                }
                async let distance = outsideTraining(.walkingRunningDistance, day: day, intervals: intervals, store: store)
                async let steps = outsideTraining(.steps, day: day, intervals: intervals, store: store)
                let (walking, counts) = try await (distance, steps)
                try Task.checkCancellation()
                evidence.append(.init(
                    day: day, training: events.sorted { $0.id < $1.id }, excludedIntervals: intervals,
                    nonTrainingKilometers: walking.value.map { $0 / 1000 }, nonTrainingSteps: counts.value,
                    hasAmbiguousBoundarySamples: walking.ambiguous || counts.ambiguous,
                    basisID: HealthActivityDayEvidence.statisticsBasis
                ))
            }
            try Task.checkCancellation()
            continuation.yield(.trainingEvidence(evidence))
        } catch {
            guard !Task.isCancelled else { return }
            continuation.yield(.trainingFailure)
        }
    }

    private static func outsideTraining(
        _ kind: DailyActivityMetricKind, day: DailyActivityDayKey, intervals: [EnergyTimeInterval], store: HKHealthStore
    ) async throws -> (value: Double?, ambiguous: Bool) {
        let complement = EnergyTimeInterval.complement(intervals, within: day)
        guard !complement.isEmpty else { return (0, false) }
        let predicates = complement.map {
            HKQuery.predicateForSamples(withStart: $0.start, end: $0.end, options: [.strictStartDate, .strictEndDate])
        }
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        let statistics = try await HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: quantityType(kind), predicate: predicate), options: .cumulativeSum
        ).result(for: store)
        var ambiguous = false
        if !intervals.isEmpty {
            // Inspect only time bounds. Never add raw source values or prorate a crossing sample.
            let samples = try await HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: quantityType(kind), predicate: HKQuery.predicateForSamples(withStart: day.start, end: day.end))],
                sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate)]
            ).result(for: store)
            ambiguous = samples.contains { EnergyTimeInterval.crossesBoundary(start: $0.startDate, end: $0.endDate, intervals: intervals) }
        }
        return (statistics?.sumQuantity()?.doubleValue(for: unit(kind)), ambiguous)
    }

    private static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "跑步"
        case .walking: "步行训练"
        case .hiking: "徒步"
        case .cycling: "骑行"
        case .swimming: "游泳"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "力量训练"
        default: "训练"
        }
    }

    private static func descriptor(
        _ kind: DailyActivityMetricKind, window: DailyActivityWindow, sources: Bool
    ) -> HKStatisticsCollectionQueryDescriptor? {
        guard let first = window.days.first, let last = window.days.last else { return nil }
        // 持续查询预留至次日零点，不能把 predicate 固定为首次读取时的 now。
        let predicate = HKQuery.predicateForSamples(withStart: first.start, end: last.end)
        var interval = DateComponents(day: 1)
        interval.calendar = window.calendar
        interval.timeZone = window.calendar.timeZone
        return HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: quantityType(kind), predicate: predicate),
            options: sources ? [.cumulativeSum, .separateBySource] : .cumulativeSum,
            anchorDate: first.start, intervalComponents: interval
        )
    }

    private static func observe(
        _ kind: DailyActivityMetricKind, window: DailyActivityWindow, store: HKHealthStore,
        continuation: AsyncStream<DailyActivityUpdate>.Continuation
    ) async {
        guard let valuesQuery = descriptor(kind, window: window, sources: false),
              let sourceQuery = descriptor(kind, window: window, sources: true)
        else { return }
        do {
            for try await update in valuesQuery.results(for: store) {
                try Task.checkCancellation()
                let readAt = Date.now
                let values = window.days.map { day in
                    DailyActivityValue(key: day, value: update.statisticsCollection.statistics(for: day.start)?
                        .sumQuantity()?.doubleValue(for: unit(kind)))
                }
                continuation.yield(.values(kind, values, readAt))
                do {
                    let sourceCollection = try await sourceQuery.result(for: store)
                    try Task.checkCancellation()
                    let sourceReadAt = Date.now
                    let sources = window.days.map { day -> DailyActivitySources in
                        let statistics = sourceCollection.statistics(for: day.start)
                        let hkSources = statistics?.sources ?? []
                        let contributions = hkSources.map { hkSource in
                            DailyActivitySourceContribution(
                                source: HealthDataSource(
                                    name: hkSource.name,
                                    bundleIdentifier: hkSource.bundleIdentifier
                                ),
                                value: statistics?.sumQuantity(for: hkSource)?.doubleValue(for: unit(kind))
                            )
                        }
                        let entries = contributions.map(\.source)
                        return DailyActivitySources(
                            key: day,
                            source: ActivitySourceAttribution(sources: entries, readAt: sourceReadAt),
                            contributions: contributions
                        )
                    }
                    continuation.yield(.sources(kind, sources))
                } catch {
                    guard !Task.isCancelled else { return }
                    continuation.yield(.sourceFailure(kind))
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            continuation.yield(.failure(kind))
        }
    }
}

enum DailyActivityReadError: Error {
    case unavailable
}
