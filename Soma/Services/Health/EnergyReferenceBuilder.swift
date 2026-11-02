import Foundation

struct EnergyWalkingReferenceSample: Codable, Equatable, Sendable {
    let date: Date
    let kilometers: Double?
    let steps: Double?
    let coverageConfirmed: Bool
    let trainingExcluded: Bool
    /// The adapter's consistent merged-statistics policy, not a guessed vendor name.
    let basisID: String
}

enum EnergyReferenceBuilder {
    static func initial(_ facts: EnergyLifestyleFacts) throws -> EnergyReferenceDay {
        for (value, maximum) in [(facts.workHours, 24.0), (facts.commutingWalkMinutes, 1440), (facts.houseworkMinutes, 1440)] {
            if let value, !value.isFinite || !(0 ... maximum).contains(value) {
                throw EnergyCalculationError.invalidInput
            }
        }
        if let days = facts.workDaysPerWeek, !(0 ... 7).contains(days) {
            throw EnergyCalculationError.invalidInput
        }
        let allocations = facts.allocations
        let factor: Double
        let reason: String
        if !allocations.isEmpty {
            guard allocations.allSatisfy({ $0.hours.isFinite && $0.hours >= 0 && $0.physicalActivityRatio.isFinite && $0.physicalActivityRatio >= 0 }),
                  abs(allocations.reduce(0) { $0 + $1.hours } - 24) < 0.001
            else { throw EnergyCalculationError.invalidInput }
            factor = allocations.reduce(0) { $0 + $1.hours * $1.physicalActivityRatio } / 24
            reason = "按已确认的 24 小时参考活动分配估算；PAR 是群体参考，未包含专门训练"
        } else {
            var seed = switch facts.workPosture {
            case .sitting, nil: 1.4
            case .standing: 1.5
            case .walking: 1.6
            }
            var knownHours = 0.0
            var adjustment = 0.0
            if let work = facts.workHours, let days = facts.workDaysPerWeek {
                guard work.isFinite, (0 ... 24).contains(work), (0 ... 7).contains(days) else { throw EnergyCalculationError.invalidInput }
                seed = 1.4
                let hours = work * Double(days) / 7
                knownHours += hours
                if let posture = facts.workPosture {
                    let ratio = switch posture {
                    case .sitting: 1.3
                    case .standing: 1.5
                    case .walking: 2.2
                    }
                    adjustment += (ratio - seed) * hours / 24
                }
            }
            if let minutes = facts.commutingWalkMinutes, let days = facts.workDaysPerWeek {
                guard minutes.isFinite, (0 ... 1440).contains(minutes), (0 ... 7).contains(days) else { throw EnergyCalculationError.invalidInput }
                let hours = minutes / 60 * Double(days) / 7
                knownHours += hours
                adjustment += (3.2 - seed) * hours / 24
            }
            if let minutes = facts.houseworkMinutes {
                guard minutes.isFinite, (0 ... 1440).contains(minutes) else { throw EnergyCalculationError.invalidInput }
                let hours = minutes / 60
                knownHours += hours
                adjustment += (2.8 - seed) * hours / 24
            }
            guard knownHours <= 24 else { throw EnergyCalculationError.inconsistentReference }
            factor = seed + adjustment
            reason = knownHours > 0 ? "按明确工作、通勤和家务时长替换参考时段；未知时段保留模型先验，不代表个人实测"
                : facts.workPosture == nil ? "生活事实不足，暂用未校准参考 1.4；不代表个人实测"
                : "按主要工作姿势采用暂定先验；不代表个人实测"
        }
        guard (1 ... 4).contains(factor) else { throw EnergyCalculationError.inconsistentReference }
        return try .init(id: facts.id, effectiveFrom: facts.effectiveFrom, factor: factor, walkingKilometers: nil, reason: reason,
                         sourceFactsFingerprint: EnergyInputCoding.digest(EnergyInputCoding.encode(facts)))
    }

    static func walkingDistance(
        _ samples: [EnergyWalkingReferenceSample], before date: Date, basisID: String,
        calendar: Calendar = .current
    ) -> Double? {
        let end = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -14, to: end) else { return nil }
        let eligible = samples.filter {
            $0.date >= start && $0.date < end && $0.coverageConfirmed && $0.trainingExcluded && $0.basisID == basisID
                && ($0.kilometers.map { $0.isFinite && $0 >= 0 } ?? false)
        }
        // Duplicate observations do not create extra qualifying days.
        let grouped = Dictionary(grouping: eligible, by: { calendar.startOfDay(for: $0.date) })
        guard grouped.count >= 10 else { return nil }
        let distances = grouped.values.compactMap { rows -> Double? in
            let values = Set(rows.compactMap(\.kilometers))
            return values.count == 1 ? values.first : nil
        }
        guard distances.count >= 10 else { return nil }
        return EnergyCalibration.median(distances)
    }

    static func stepLengthMeters(_ samples: [EnergyWalkingReferenceSample], basisID: String, calendar: Calendar = .current) -> Double? {
        let eligible = samples.filter { $0.coverageConfirmed && $0.trainingExcluded && $0.basisID == basisID }
        let grouped = Dictionary(grouping: eligible, by: { calendar.startOfDay(for: $0.date) })
        let values = grouped.values.compactMap { rows -> Double? in
            let ratios = rows.compactMap { row -> Double? in
                guard let km = row.kilometers, km.isFinite, km > 0,
                      let steps = row.steps, steps.isFinite, steps > 0 else { return nil }
                return km * 1000 / steps
            }
            let unique = Set(ratios)
            return unique.count == 1 ? unique.first : nil
        }
        return values.count >= 7 ? EnergyCalibration.median(values) : nil
    }

    static func habitualFactor(_ days: [EnergyDayCalculation], before date: Date, calendar: Calendar = .current) -> Double? {
        let end = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -28, to: end) else { return nil }
        let eligible = days.filter { $0.canCalibrate && $0.input.date >= start && $0.input.date < end }
        let uniqueDates = Set(eligible.map { calendar.startOfDay(for: $0.input.date) })
        guard eligible.count >= 21, uniqueDates.count == eligible.count else { return nil }
        for week in 0 ..< 4 {
            guard let weekStart = calendar.date(byAdding: .day, value: week * 7, to: start),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart),
                  eligible.count(where: { $0.input.date >= weekStart && $0.input.date < weekEnd }) >= 3
            else { return nil }
        }
        let resting = eligible.reduce(0) { $0 + $1.input.resting }
        return resting > 0 ? eligible.reduce(0) { $0 + $1.total } / resting : nil
    }
}
