import Foundation

/// 预估总消耗 = 当日静息 × 残差系数 + 进入总量的活动能量。
///
/// 活动能量只取已经择优的一份日活动读数。HealthKit `activeEnergyBurned` 不含静息。
/// 重叠的 COROS / Apple 日活动能量不能相加。训练只有在能证明已经包含在这份读数里时才拆开展示，
/// 并且拆开后的两项之和仍等于所选日活动能量，不能再加到总量上。
/// 没有日活动读数时不编造；已记录、且未包含在日读数里的训练能量可以单独进入总量。
enum DailyEnergyTotal {
    enum Activity: Codable, Equatable, Sendable {
        /// 一份所选日活动能量，未能可靠拆开。
        case selected(Double)
        /// 训练活动能量已包含在所选日活动能量中；其余 = 所选 − 训练。
        case disaggregated(training: Double, remaining: Double)
        /// 没有所选日活动读数。这里只是已知训练的活动能量，不是补出来的全天活动。
        case recordedTraining(Double)
        /// 没有所选日活动读数，也没有已知训练能量。
        case absent

        var kilocalories: Double {
            switch self {
            case let .selected(value), let .recordedTraining(value):
                value
            case let .disaggregated(training, remaining):
                training + remaining
            case .absent:
                0
            }
        }
    }

    struct Components: Codable, Equatable, Sendable {
        var restingKilocalories: Double
        var coefficient: Double
        var activity: Activity

        /// 静息 ×（系数 − 1）。这是系数里、所选活动能量没有覆盖的那一部分。
        var baselineExtraKilocalories: Double {
            restingKilocalories * (coefficient - 1)
        }

        var activityKilocalories: Double {
            activity.kilocalories
        }

        var totalKilocalories: Double {
            restingKilocalories * coefficient + activityKilocalories
        }

        var componentsAddUp: Bool {
            abs(restingKilocalories + baselineExtraKilocalories + activityKilocalories - totalKilocalories) < 0.000_001
        }
    }

    static func isUsableActive(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value < 100_000
    }

    /// `selectedActiveKilocalories == nil` 表示没有读数。非 nil 的 0 是有效读数。
    /// 无效读数不当成 0，也不改用训练能量顶上。
    static func compose(
        restingKilocalories: Double,
        coefficient: ResidualEnergyCoefficient,
        selectedActiveKilocalories: Double?,
        includedTrainingKilocalories: Double? = nil,
        recordedTrainingKilocalories: Double? = nil
    ) -> Components? {
        guard restingKilocalories.isFinite, restingKilocalories > 0, restingKilocalories < 100_000,
              coefficient.isUsable
        else { return nil }
        let activity: Activity
        if let selected = selectedActiveKilocalories {
            guard isUsableActive(selected) else { return nil }
            if let training = includedTrainingKilocalories, isUsableActive(training), training <= selected {
                activity = .disaggregated(training: training, remaining: selected - training)
            } else {
                activity = .selected(selected)
            }
        } else if let training = recordedTrainingKilocalories, isUsableActive(training) {
            activity = .recordedTraining(training)
        } else if recordedTrainingKilocalories != nil {
            return nil
        } else {
            activity = .absent
        }
        let components = Components(
            restingKilocalories: restingKilocalories, coefficient: coefficient.value, activity: activity
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

    /// 没有所选日活动读数时，汇总去重后已知的训练活动能量。未知口径保持未知，不补 0。
    static func recordedTrainingKilocalories(_ events: [EnergyTrainingEvent], resting: Double) -> Double? {
        let preferred = EnergyDayCalculator.preferredEvents(events, resting: resting)
        let known = preferred.compactMap { $0.netEnergy(resting: resting) }
        guard !known.isEmpty else { return nil }
        let total = known.reduce(0, +)
        return isUsableActive(total) ? total : nil
    }

    /// 只有这些训练的活动能量能被证明包含在同一份获胜日活动能量里时，才返回可拆出的训练部分。
    /// Apple 健康汇总只拆 `health:` 且口径为活动能量的训练；COROS 整包只拆来源属于 COROS 的训练。
    /// 夹杂 Soma 本地记录、未知口径或其他来源时不拆，调用方也不得把它们再加到日活动能量上。
    static func includedTrainingKilocalories(
        selectedActive: Double,
        winningSource: DailyActivityWinningSource,
        events: [EnergyTrainingEvent],
        resting: Double
    ) -> Double? {
        guard isUsableActive(selectedActive) else { return nil }
        let preferred = EnergyDayCalculator.preferredEvents(events, resting: resting)
        guard !preferred.isEmpty else { return nil }
        let included = preferred.filter { event in
            event.scope == .active && event.id.hasPrefix("health:") && source(event, matches: winningSource)
        }
        guard included.count == preferred.count else { return nil }
        let values = included.compactMap { $0.netEnergy(resting: resting) }
        guard values.count == included.count else { return nil }
        let sum = values.reduce(0, +)
        guard isUsableActive(sum), sum <= selectedActive else { return nil }
        return sum
    }

    private static func source(_ event: EnergyTrainingEvent, matches winningSource: DailyActivityWinningSource) -> Bool {
        switch winningSource {
        case .appleHealth:
            true
        case .coros:
            DailyActivitySourceMatcher.isCOROS(name: event.source, bundleIdentifier: "")
        }
    }
}
