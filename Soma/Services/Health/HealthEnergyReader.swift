import Foundation
import HealthKit

struct HealthEnergySnapshot: Equatable, Sendable {
    var activeKilocalories: Int?
    var restingKilocalories: Int?

    static let empty = HealthEnergySnapshot()
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
        async let active = cumulativeKilocalories(
            type: activeType,
            start: start,
            end: now
        )
        async let resting = cumulativeKilocalories(
            type: restingType,
            start: start,
            end: now
        )
        return await HealthEnergySnapshot(
            activeKilocalories: active,
            restingKilocalories: resting
        )
    }

    private static func cumulativeKilocalories(
        type: HKQuantityType,
        start: Date,
        end: Date
    ) async -> Int? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: [.strictStartDate, .strictEndDate]
            )
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?
                    .doubleValue(for: .kilocalorie())
                continuation.resume(returning: value.map { Int($0.rounded()) })
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
