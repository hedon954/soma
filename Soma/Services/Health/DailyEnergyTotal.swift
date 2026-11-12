import Foundation

/// 预估总消耗 = 当日静息 × 残差系数 + 所选日活动能量 + Soma 已记录训练消耗。
///
/// 活动能量只取已经择优的一份日活动读数。HealthKit `activeEnergyBurned` 不含静息。
/// 重叠的 COROS / Apple 日活动能量不能相加。训练消耗与进展页训练列表使用同一汇总口径，
/// 作为独立加项直接加入，不从日活动能量里拆出，也不猜测扣减。
/// 没有日活动读数时不编造；没有训练记录时训练消耗为 0。
enum DailyEnergyTotal {
    enum Activity: Codable, Equatable, Sendable {
        /// 一份所选日活动能量。
        case selected(Double)
        /// 没有所选日活动读数。
        case absent

        var kilocalories: Double {
            switch self {
            case let .selected(value):
                value
            case .absent:
                0
            }
        }
    }

    struct Components: Codable, Equatable, Sendable {
        var restingKilocalories: Double
        var coefficient: Double
        var activity: Activity
        var trainingKilocalories: Double = 0

        /// 静息 ×（系数 − 1）。这是系数里、所选活动能量和训练消耗没有单独列出的那一部分。
        var baselineExtraKilocalories: Double {
            restingKilocalories * (coefficient - 1)
        }

        var activityKilocalories: Double {
            activity.kilocalories
        }

        var totalKilocalories: Double {
            restingKilocalories * coefficient + activityKilocalories + trainingKilocalories
        }

        var componentsAddUp: Bool {
            abs(
                restingKilocalories + baselineExtraKilocalories + activityKilocalories
                    + trainingKilocalories - totalKilocalories
            ) < 0.000_001
        }

        init(
            restingKilocalories: Double,
            coefficient: Double,
            activity: Activity,
            trainingKilocalories: Double = 0
        ) {
            self.restingKilocalories = restingKilocalories
            self.coefficient = coefficient
            self.activity = activity
            self.trainingKilocalories = trainingKilocalories
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DailyEnergyTotalComponentKeys.self)
            restingKilocalories = try container.decode(Double.self, forKey: .restingKilocalories)
            coefficient = try container.decode(Double.self, forKey: .coefficient)
            let legacy = try container.decode(DailyEnergyTotalLegacyActivity.self, forKey: .activity)
            let storedTraining = try container.decodeIfPresent(Double.self, forKey: .trainingKilocalories) ?? 0
            switch legacy {
            case let .selected(value):
                activity = .selected(value)
                trainingKilocalories = storedTraining
            case let .disaggregated(training, remaining):
                activity = .selected(training + remaining)
                trainingKilocalories = storedTraining
            case let .recordedTraining(value):
                activity = .absent
                trainingKilocalories = storedTraining == 0 ? value : storedTraining
            case .absent:
                activity = .absent
                trainingKilocalories = storedTraining
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DailyEnergyTotalComponentKeys.self)
            try container.encode(restingKilocalories, forKey: .restingKilocalories)
            try container.encode(coefficient, forKey: .coefficient)
            try container.encode(activity, forKey: .activity)
            try container.encode(trainingKilocalories, forKey: .trainingKilocalories)
        }
    }

    static func isUsableActive(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value < 100_000
    }

    /// `selectedActiveKilocalories == nil` 表示没有读数。非 nil 的 0 是有效读数。
    /// 无效活动读数不当成 0，也不改用训练能量顶上。无效训练加项按 0 处理，不让整份总量失败。
    static func compose(
        restingKilocalories: Double,
        coefficient: ResidualEnergyCoefficient,
        selectedActiveKilocalories: Double?,
        trainingKilocalories: Double = 0
    ) -> Components? {
        guard restingKilocalories.isFinite, restingKilocalories > 0, restingKilocalories < 100_000,
              coefficient.isUsable
        else { return nil }
        let activity: Activity
        if let selected = selectedActiveKilocalories {
            guard isUsableActive(selected) else { return nil }
            activity = .selected(selected)
        } else {
            activity = .absent
        }
        let training = isUsableActive(trainingKilocalories) ? trainingKilocalories : 0
        let components = Components(
            restingKilocalories: restingKilocalories,
            coefficient: coefficient.value,
            activity: activity,
            trainingKilocalories: training
        )
        guard components.totalKilocalories.isFinite, components.totalKilocalories > 0, components.totalKilocalories < 100_000,
              components.componentsAddUp
        else { return nil }
        return components
    }

    /// 同一天若出现多条日常活动记录，只采用最后一条，不把各来源的活动能量相加。
    static func selectedDailyActive(
        in entries: [ProgressHistoryRecord]
    ) -> (kilocalories: Double?, source: DailyActivityWinningSource?) {
        guard let record = entries.last(where: \.isDailyActivity) else { return (nil, nil) }
        return (record.activeEnergyKilocalories, record.dailyActivitySource)
    }

    /// 与进展页训练列表相同的汇总：运动记录且不是日常活动，按记录身份去重后加总列表展示的估算。
    /// `nil`、非有限、小于 0、或达到 100000 的单条不计入、不编成 0。
    static func listTrainingKilocalories(in entries: [ProgressHistoryRecord]) -> Double {
        var seen: Set<UUID> = []
        var total = 0.0
        for record in entries where isListTraining(record) {
            guard seen.insert(record.activity.id).inserted, let value = record.calories, isUsableActive(value) else { continue }
            total += value
        }
        return total
    }

    private static func isListTraining(_ record: ProgressHistoryRecord) -> Bool {
        record.activity.kind == .workout && !record.isDailyActivity
    }
}

private enum DailyEnergyTotalComponentKeys: String, CodingKey {
    case restingKilocalories, coefficient, activity, trainingKilocalories
}

private enum DailyEnergyTotalLegacyActivityKeys: String, CodingKey {
    case selected, disaggregated, recordedTraining, absent
}

private enum DailyEnergyTotalLegacyDisaggregatedKeys: String, CodingKey {
    case training, remaining
}

private enum DailyEnergyTotalLegacyAnonymousValueKey: String, CodingKey {
    case value = "_0"
}

/// 旧存档里活动项曾包含训练拆分或把训练填进活动槽位。
private enum DailyEnergyTotalLegacyActivity: Decodable, Equatable {
    case selected(Double)
    case disaggregated(training: Double, remaining: Double)
    case recordedTraining(Double)
    case absent

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DailyEnergyTotalLegacyActivityKeys.self)
        if let value = try Self.decodeSingle(container, forKey: .selected) {
            self = .selected(value)
        } else if let value = try Self.decodeSingle(container, forKey: .recordedTraining) {
            self = .recordedTraining(value)
        } else if container.contains(.disaggregated) {
            let nested = try container.nestedContainer(
                keyedBy: DailyEnergyTotalLegacyDisaggregatedKeys.self, forKey: .disaggregated
            )
            self = try .disaggregated(
                training: nested.decode(Double.self, forKey: .training),
                remaining: nested.decode(Double.self, forKey: .remaining)
            )
        } else if container.contains(.absent) {
            self = .absent
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "未知活动存档")
            )
        }
    }

    private static func decodeSingle(
        _ container: KeyedDecodingContainer<DailyEnergyTotalLegacyActivityKeys>,
        forKey key: DailyEnergyTotalLegacyActivityKeys
    ) throws -> Double? {
        if let value = try container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        guard container.contains(key) else { return nil }
        let nested = try container.nestedContainer(
            keyedBy: DailyEnergyTotalLegacyAnonymousValueKey.self, forKey: key
        )
        return try nested.decode(Double.self, forKey: .value)
    }
}
