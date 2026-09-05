import Foundation

/// Product policy, not a physiological constant. Only completed, sufficiently covered days qualify.
struct AdaptiveEnergyPolicy: Equatable, Sendable {
    var lookbackDays = 30
    var minimumDays = 21
    var minimumWeekendDays = 4
    var minimumCoverage = 0.9
}

struct EnergyHistoryDay: Equatable, Sendable {
    let date: Date
    let restingKilocalories: Double?
    let activeKilocalories: Double?
    let sourceID: String
    let sourceName: String
    /// Union of this source's resting sample intervals; a coverage proxy, not proof of device wear.
    let coverage: Double
}

struct EnergyLifestyleBaseline: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = .init()
    var effectiveFrom: Date
    var factor: Double
    var label: String
}

struct AdaptiveEnergyEstimate: Equatable, Sendable {
    enum Method: String, Sendable {
        case deviceHistory
        case confirmedLifestyle
        case defaultReference
    }

    let method: Method
    let restingKilocalories: Double
    let factor: Double
    let sourceName: String
    let evidenceDays: [Date]
    let effectiveFrom: Date
    var restingSourceName = "个人静息公式"
    var totalKilocalories: Double {
        restingKilocalories * factor
    }
}

struct AdaptiveEnergyOutcome: Equatable, Sendable {
    let estimate: AdaptiveEnergyEstimate?
    let eligibleDayCount: Int
    let missingReason: String?
}

enum AdaptiveEnergyEstimator {
    static func estimate(
        for targetDate: Date,
        now: Date = .now,
        history: [EnergyHistoryDay],
        restingEstimate: Double?,
        baselines: [EnergyLifestyleBaseline] = [],
        calendar: Calendar = .current,
        policy: AdaptiveEnergyPolicy = .init()
    ) -> AdaptiveEnergyOutcome {
        let targetDay = calendar.startOfDay(for: targetDate)
        guard targetDay <= calendar.startOfDay(for: now) else {
            return .init(estimate: nil, eligibleDayCount: 0, missingReason: "尚未发生")
        }
        guard policy.lookbackDays > 0, policy.minimumDays > 0,
              policy.minimumWeekendDays >= 0,
              (0 ... 1).contains(policy.minimumCoverage),
              let lowerBound = calendar.date(byAdding: .day, value: -policy.lookbackDays, to: targetDay)
        else {
            return .init(estimate: nil, eligibleDayCount: 0, missingReason: "估算策略不可用")
        }

        let candidates = history.filter { day in
            let date = calendar.startOfDay(for: day.date)
            guard date >= lowerBound, date < targetDay,
                  day.coverage.isFinite, day.coverage >= policy.minimumCoverage, day.coverage <= 1,
                  let resting = day.restingKilocalories, let active = day.activeKilocalories,
                  validEnergy(resting), resting > 0, validEnergy(active), !day.sourceID.isEmpty
            else { return false }
            return true
        }
        // Sources never add together. Conflicting duplicate daily observations are excluded.
        let sourceDays = Dictionary(grouping: candidates, by: \.sourceID).values.map { days in
            Dictionary(grouping: days, by: { calendar.startOfDay(for: $0.date) }).values.compactMap { duplicates in
                guard let first = duplicates.first,
                      duplicates.allSatisfy({
                          $0.restingKilocalories == first.restingKilocalories &&
                              $0.activeKilocalories == first.activeKilocalories
                      })
                else { return nil as EnergyHistoryDay? }
                return first
            }.sorted { $0.date < $1.date }
        }.sorted { left, right in
            if left.count != right.count {
                return left.count > right.count
            }
            return (left.first?.sourceID ?? "") < (right.first?.sourceID ?? "")
        }
        let eligibleCount = sourceDays.first?.count ?? 0
        let qualifying = sourceDays.first { days in
            days.count >= policy.minimumDays && days.filter { calendar.isDateInWeekend($0.date) }.count >= policy.minimumWeekendDays
        }
        if let days = qualifying, let source = days.first,
           let resting = median(days.compactMap(\.restingKilocalories)),
           let factor = median(days.compactMap { day -> Double? in
               guard let basal = day.restingKilocalories, let active = day.activeKilocalories else { return nil }
               return (basal + active) / basal
           }), validEnergy(resting * factor)
        {
            return .init(
                estimate: .init(
                    method: .deviceHistory, restingKilocalories: resting, factor: factor,
                    sourceName: source.sourceName, evidenceDays: days.map { calendar.startOfDay(for: $0.date) },
                    effectiveFrom: lowerBound, restingSourceName: source.sourceName
                ), eligibleDayCount: days.count, missingReason: nil
            )
        }
        let baseline = baselines.filter {
            $0.effectiveFrom <= targetDay && $0.factor.isFinite && (1 ... 4).contains($0.factor)
        }.max {
            $0.effectiveFrom == $1.effectiveFrom ? $0.id.uuidString < $1.id.uuidString : $0.effectiveFrom < $1.effectiveFrom
        }
        let deviceResting = latestRestingDay(history, from: lowerBound, before: targetDay, calendar: calendar, policy: policy)
        let formulaResting = restingEstimate.flatMap { validEnergy($0) && $0 > 0 ? $0 : nil }
        let resting = formulaResting ?? deviceResting?.restingKilocalories
        // An explicit product fallback, never persisted as a user-confirmed lifestyle fact.
        let factor = baseline?.factor ?? 1.4
        guard let resting, validEnergy(resting * factor) else {
            return .init(estimate: nil, eligibleDayCount: eligibleCount, missingReason: "缺少有效静息消耗，请补充身体资料")
        }
        return .init(
            estimate: .init(
                method: baseline == nil ? .defaultReference : .confirmedLifestyle, restingKilocalories: resting, factor: factor,
                sourceName: baseline?.label ?? "默认参考", evidenceDays: [], effectiveFrom: baseline?.effectiveFrom ?? targetDay,
                restingSourceName: formulaResting != nil ? "个人静息公式" : (deviceResting?.sourceName ?? "设备静息")
            ), eligibleDayCount: eligibleCount, missingReason: nil
        )
    }

    private static func latestRestingDay(
        _ history: [EnergyHistoryDay], from lowerBound: Date, before targetDay: Date, calendar: Calendar, policy: AdaptiveEnergyPolicy
    ) -> EnergyHistoryDay? {
        let candidates = history.filter { day in
            let date = calendar.startOfDay(for: day.date)
            guard date >= lowerBound, date < targetDay, !day.sourceID.isEmpty,
                  day.coverage.isFinite, day.coverage >= policy.minimumCoverage, day.coverage <= 1,
                  let resting = day.restingKilocalories, validEnergy(resting), resting > 0
            else { return false }
            return true
        }
        let distinct = Dictionary(grouping: candidates, by: \.sourceID).values.flatMap { source in
            Dictionary(grouping: source, by: { calendar.startOfDay(for: $0.date) }).values.compactMap { duplicates in
                guard let first = duplicates.first, duplicates.allSatisfy({ $0.restingKilocalories == first.restingKilocalories }) else { return nil as EnergyHistoryDay? }
                return first
            }
        }
        return distinct.sorted {
            let left = calendar.startOfDay(for: $0.date)
            let right = calendar.startOfDay(for: $1.date)
            return left == right ? $0.sourceID < $1.sourceID : left > right
        }.first
    }

    private static func validEnergy(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value < 100_000
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
