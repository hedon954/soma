import Foundation

/// A model reference, never a fabricated activity or sleep record.
struct EnergyReferenceDay: Codable, Equatable, Sendable {
    var id: UUID = .init()
    let effectiveFrom: Date
    var factor: Double
    var walkingKilometers: Double?
    var thermicShare: Double = 0.10
    var allocationHours: Double = 16
    var reason: String
    var sourceFactsFingerprint: String?
}

struct EnergyTrainingEvent: Codable, Equatable, Sendable, Identifiable {
    typealias EnergyScope = WorkoutCalorieScope

    let id: String
    /// Only populated from original identity or an explicit user association.
    var linkedIdentity: String?
    let source: String
    var activityType: String?
    let scope: EnergyScope
    let kilocalories: Double?
    let met: Double?
    let durationHours: Double?
    let start: Date?
    let end: Date?
    var sessionIdentity: String?
    var components: [EnergyTrainingEvent]?

    var identity: String {
        linkedIdentity ?? id
    }

    func netEnergy(resting: Double) -> Double? {
        if let components, !components.isEmpty {
            let values = components.compactMap { $0.netEnergy(resting: resting) }
            return values.count == components.count ? values.reduce(0, +) : nil
        }
        guard let kilocalories, kilocalories.isFinite, (0 ..< 100_000).contains(kilocalories) else { return nil }
        switch scope {
        case .active: return kilocalories
        case .metGross:
            guard let met, met.isFinite, met > 0 else { return nil }
            return kilocalories * max(0, met - 1) / met
        case .gross:
            guard let durationHours, durationHours.isFinite, durationHours > 0 else { return nil }
            return max(0, kilocalories - resting * durationHours / 24)
        case .unknown: return nil
        }
    }
}

struct EnergyDayInput: Codable, Equatable, Sendable {
    let date: Date
    let resting: Double
    let weightKG: Double
    let reference: EnergyReferenceDay
    let nonTrainingKilometers: Double?
    let walkingCoverageConfirmed: Bool
    let isEndedDay: Bool
    let training: [EnergyTrainingEvent]
    let correction: Double
    var observedNonTrainingSteps: Double?
    var stepLengthMeters: Double?
    var restingFormula: RestingEnergyFormulaInput?
    var weightRecordID: UUID?
    var weightRecordDate: Date?
}

struct EnergyDayCalculation: Codable, Equatable, Sendable {
    static let currentAlgorithmVersion = "soma-energy-1"
    let input: EnergyDayInput
    let baseline: Double
    let walkingDelta: Double
    let trainingDelta: Double
    let displacedActivityPerHour: Double
    let adoptedTrainingIDs: [String]
    let excludedTrainingIDs: [String]
    let issues: [EnergyDayIssue]
    var algorithmVersion: String? = Self.currentAlgorithmVersion
    /// 当前展示和缺口使用的总消耗。缺省表示这份快照仍是旧的参考日差额。
    var presentedTotal: DailyEnergyTotal.Components? = nil
    /// 与 `presentedTotal` 对应的所选日活动读数。nil 表示没有读数，不是 0。
    var presentedSelectedActiveKilocalories: Double? = nil

    var reasons: [String] {
        issues.map(\.explanation)
    }

    var uncalibratedTotal: Double {
        baseline + walkingDelta + trainingDelta
    }

    var total: Double {
        uncalibratedTotal + input.correction
    }

    var factor: Double {
        total / input.resting
    }

    var canCalibrate: Bool {
        reasons.isEmpty && input.isEndedDay
    }
}

struct EnergyDayIssue: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case overlappingTraining, missingTrainingEnergy, missingTrainingInterval, incompleteWalking, unfinishedDay
    }

    let kind: Kind
    var eventID: String?

    var explanation: String {
        switch kind {
        case .overlappingTraining: "有训练时段重叠，需确认是否同一次训练"
        case .missingTrainingEnergy: "有训练时长或能量口径待确认"
        case .missingTrainingInterval: "有训练实际时段待确认"
        case .incompleteWalking: "日常步行参考、覆盖或训练区间尚不完整"
        case .unfinishedDay: "当天尚未结束，步行少于全天参考时不扣减估算"
        }
    }
}

enum EnergyCalculationError: Error {
    case invalidInput, inconsistentReference
}

/// 参考日差额只保留给历史依据。用户可见总消耗在 `DailyEnergyTotal`：
/// 静息 × `ResidualEnergyCoefficient` + 所选日活动能量 + Soma 已记录训练消耗。不要把这里的步行差额或训练时长摊销加回总量。
enum EnergyDayCalculator {
    static func calculate(_ input: EnergyDayInput) throws -> EnergyDayCalculation {
        let ref = input.reference
        guard input.resting.isFinite, input.resting > 0, input.resting < 100_000,
              input.weightKG.isFinite, input.weightKG > 0,
              ref.factor.isFinite, (1 ... 4).contains(ref.factor),
              ref.thermicShare.isFinite, (0 ..< 1).contains(ref.thermicShare),
              ref.allocationHours.isFinite, (0 ... 24).contains(ref.allocationHours), ref.allocationHours > 0,
              input.correction.isFinite, ref.effectiveFrom <= input.date
        else { throw EnergyCalculationError.invalidInput }
        let baseline = input.resting * ref.factor
        let referenceWalk = ref.walkingKilometers.map { 0.5 * input.weightKG * $0 }
        if let distance = ref.walkingKilometers, !distance.isFinite || distance < 0 {
            throw EnergyCalculationError.invalidInput
        }
        let budget = baseline * (1 - ref.thermicShare) - input.resting - (referenceWalk ?? 0)
        guard budget >= 0 else { throw EnergyCalculationError.inconsistentReference }
        let hourly = budget / ref.allocationHours
        let candidates = preferredEvents(input.training, resting: input.resting)
        var issues: [EnergyDayIssue] = []
        var excluded = input.training.filter { event in !candidates.contains { $0.id == event.id } }.map(\.id)
        var adopted: [String] = []
        var trainingDelta = 0.0
        let ambiguous = Set(candidates.filter { event in
            candidates.contains { other in
                guard event.identity != other.identity,
                      let start = event.start, let end = event.end,
                      let otherStart = other.start, let otherEnd = other.end
                else { return false }
                return start < otherEnd && otherStart < end
            }
        }.map(\.id))
        var intervalsKnown = true
        var unresolvedTraining = false
        for event in candidates {
            let hasBounds = event.start != nil && event.end != nil
            if !hasBounds, candidates.contains(where: { $0.identity != event.identity && $0.source != event.source }) {
                unresolvedTraining = true
                excluded.append(event.id)
                issues.append(.init(kind: .missingTrainingInterval, eventID: event.id))
                continue
            }
            if ambiguous.contains(event.id) {
                unresolvedTraining = true
                excluded.append(event.id)
                issues.append(.init(kind: .overlappingTraining, eventID: event.id))
                continue
            }
            guard let hours = event.durationHours, hours.isFinite, hours > 0, hours <= 24,
                  let net = event.netEnergy(resting: input.resting)
            else {
                unresolvedTraining = true
                excluded.append(event.id)
                issues.append(.init(kind: .missingTrainingEnergy, eventID: event.id))
                continue
            }
            if let start = event.start, let end = event.end, start < end, hours <= end.timeIntervalSince(start) / 3600 + 0.001 {
                // Valid event bounds let the adapter exclude this interval from walking statistics.
            } else {
                intervalsKnown = false
                issues.append(.init(kind: .missingTrainingInterval, eventID: event.id))
            }
            adopted.append(event.id)
            trainingDelta += max(0, net - hourly * hours)
        }
        let walkDelta: Double
        if let referenceDistance = ref.walkingKilometers,
           let distance = input.nonTrainingKilometers, distance.isFinite, distance >= 0,
           input.walkingCoverageConfirmed, intervalsKnown, !unresolvedTraining
        {
            let difference = 0.5 * input.weightKG * (distance - referenceDistance)
            walkDelta = input.isEndedDay ? difference : max(0, difference)
        } else {
            walkDelta = 0
            issues.append(.init(kind: .incompleteWalking))
        }
        if !input.isEndedDay {
            issues.append(.init(kind: .unfinishedDay))
        }
        let result = EnergyDayCalculation(
            input: input, baseline: baseline, walkingDelta: walkDelta, trainingDelta: trainingDelta,
            displacedActivityPerHour: hourly, adoptedTrainingIDs: adopted.sorted(), excludedTrainingIDs: excluded.sorted(), issues: issues
        )
        guard result.total.isFinite, result.total > 0, result.total < 100_000 else { throw EnergyCalculationError.invalidInput }
        return result
    }

    /// Only original identity or explicit association determines membership.
    static func preferredEvents(_ events: [EnergyTrainingEvent], resting: Double) -> [EnergyTrainingEvent] {
        let grouped = Dictionary(grouping: events, by: \.identity)
        // Selection is deterministic; clear source scope precedes approximate MET/gross values.
        return grouped.keys.sorted().compactMap { key in
            grouped[key]?.sorted {
                let leftValid = $0.netEnergy(resting: resting) != nil && ($0.durationHours ?? 0) > 0
                let rightValid = $1.netEnergy(resting: resting) != nil && ($1.durationHours ?? 0) > 0
                if leftValid != rightValid {
                    return leftValid
                }
                let left = $0.components == nil ? rank($0.scope) : 1
                let right = $1.components == nil ? rank($1.scope) : 1
                return left == right ? $0.id < $1.id : left < right
            }.first
        }
    }

    /// Re-anchor without losing an already observed increase in routine walking.
    static func reanchor(_ reference: EnergyReferenceDay, distance: Double, resting: Double, weightKG: Double) throws -> EnergyReferenceDay {
        guard let old = reference.walkingKilometers,
              distance.isFinite, distance >= 0, resting.isFinite, resting > 0, weightKG.isFinite, weightKG > 0
        else { throw EnergyCalculationError.invalidInput }
        var updated = reference
        updated.factor += 0.5 * weightKG * (distance - old) / resting
        updated.thermicShare = reference.thermicShare * reference.factor / updated.factor
        updated.walkingKilometers = distance
        guard (1 ... 4).contains(updated.factor) else { throw EnergyCalculationError.inconsistentReference }
        return updated
    }

    private static func rank(_ scope: EnergyTrainingEvent.EnergyScope) -> Int {
        switch scope {
        case .active: 0
        case .metGross: 1
        case .gross: 2
        case .unknown: 3
        }
    }
}
