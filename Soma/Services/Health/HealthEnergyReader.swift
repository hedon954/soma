import Foundation
import HealthKit

struct HealthEnergySnapshot: Equatable, Sendable {
    var activeKilocalories: Int?
    var restingKilocalories: Int?
    var activeComponents: [HealthEnergyComponent] = []
    var restingComponents: [HealthEnergyComponent] = []

    static let empty = HealthEnergySnapshot()
}

struct HealthEnergyComponent: Equatable, Sendable {
    let sourceName: String
    let kilocalories: Int
}

enum HealthEnergyReader {
    private static let store = HKHealthStore()

    static func today(
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> HealthEnergySnapshot {
        guard HKHealthStore.isHealthDataAvailable(),
              let activeType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let restingType = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)
        else {
            return .empty
        }
        let start = calendar.startOfDay(for: now)
        async let active = cumulativeEnergy(
            type: activeType,
            start: start,
            end: now
        )
        async let resting = cumulativeEnergy(
            type: restingType,
            start: start,
            end: now
        )
        let (activeEnergy, restingEnergy) = await (active, resting)
        return HealthEnergySnapshot(
            activeKilocalories: activeEnergy.total,
            restingKilocalories: restingEnergy.total,
            activeComponents: activeEnergy.components,
            restingComponents: restingEnergy.components
        )
    }

    private struct EnergyResult: Sendable {
        let total: Int?
        let components: [HealthEnergyComponent]
    }

    private static func cumulativeEnergy(
        type: HKQuantityType,
        start: Date,
        end: Date
    ) async -> EnergyResult {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: [.strictStartDate, .strictEndDate]
            )
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum, .separateBySource]
            ) { _, statistics, _ in
                let totalValue: Double? = if let quantity = statistics?.sumQuantity() {
                    quantity.doubleValue(for: .kilocalorie())
                } else {
                    nil
                }
                let total = totalValue.map { Int($0.rounded()) }
                let grouped = (statistics?.sources ?? []).reduce(
                    into: [String: Double]()
                ) { result, source in
                    guard let value = statistics?.sumQuantity(for: source)?
                        .doubleValue(for: .kilocalorie())
                    else { return }
                    result[source.name, default: 0] += value
                }
                let components = grouped.map {
                    HealthEnergyComponent(
                        sourceName: $0.key,
                        kilocalories: Int($0.value.rounded())
                    )
                }.sorted {
                    $0.kilocalories == $1.kilocalories
                        ? $0.sourceName < $1.sourceName
                        : $0.kilocalories > $1.kilocalories
                }
                continuation.resume(
                    returning: EnergyResult(total: total, components: components)
                )
            }
            store.execute(query)
        }
    }
}

enum RestingEnergyCalculator {
    /// Mifflin–St Jeor 静息能量公式，返回完整 24 小时 kcal/day。
    static func dailyKilocalories(
        weightKG: Double?,
        heightCM: Double?,
        age: Int?,
        biologicalSex: BiologicalSex
    ) -> Double? {
        guard let weightKG, weightKG > 0,
              let heightCM, heightCM > 0,
              let age, age > 0
        else { return nil }
        let sexAdjustment: Double
        switch biologicalSex {
        case .male: sexAdjustment = 5
        case .female: sexAdjustment = -161
        case .unspecified, .other: return nil
        }
        return 10 * weightKG + 6.25 * heightCM - 5 * Double(age) + sexAdjustment
    }

    static func elapsedTodayKilocalories(
        daily: Double?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int? {
        guard let daily, daily > 0 else { return nil }
        let elapsed = now.timeIntervalSince(calendar.startOfDay(for: now))
        return Int((daily * min(max(elapsed / 86400, 0), 1)).rounded())
    }
}
