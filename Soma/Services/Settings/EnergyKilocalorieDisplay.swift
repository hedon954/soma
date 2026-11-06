import Foundation

/// 界面上的整千卡。统一用远离零的四舍五入，避免 2264.5 在标题里变成 2264、在明细里按分量加总变成 2265。
enum EnergyKilocalorieDisplay {
    struct Parts: Equatable {
        var resting: Int
        var baselineExtra: Int
        var activity: DailyEnergyTotal.Activity
        var total: Int

        var addsUp: Bool {
            resting + baselineExtra + displayedActivity == total
        }

        /// 未记录的活动不显示成 0，加总时按 0 处理，使静息和基准额外等于总量。
        var displayedActivity: Int {
            switch activity {
            case .absent:
                0
            case let .selected(value), let .recordedTraining(value):
                Self.whole(value)
            case let .disaggregated(training, remaining):
                Self.whole(training) + Self.whole(remaining)
            }
        }
    }

    static func whole(_ value: Double) -> Int {
        Int(value.rounded())
    }

    static func text(_ value: Double) -> String {
        whole(value).formatted(.number.precision(.fractionLength(0)))
    }

    static func kcal(_ value: Double) -> String {
        text(value) + " kcal"
    }

    static func text(_ value: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    static func kcal(_ value: Int) -> String {
        text(value) + " kcal"
    }

    /// 明细整数相加等于展示用的总量。基准额外吸收四舍五入的 1 kcal 尾差。
    static func parts(_ components: DailyEnergyTotal.Components) -> Parts {
        let total = whole(components.totalKilocalories)
        let resting = whole(components.restingKilocalories)
        let activity = displayedActivity(components.activity, fitting: total - resting)
        let extra = total - resting - activityKilocalories(activity)
        return Parts(resting: resting, baselineExtra: extra, activity: activity, total: total)
    }

    static func averaged(_ values: [DailyEnergyTotal.Components]) -> Parts {
        let count = Double(values.count)
        let mean = DailyEnergyTotal.Components(
            restingKilocalories: values.reduce(0) { $0 + $1.restingKilocalories } / count,
            coefficient: values.reduce(0) { $0 + $1.coefficient } / count,
            activity: .recordedTraining(values.reduce(0) { $0 + $1.activityKilocalories } / count)
        )
        var parts = parts(mean)
        if values.allSatisfy({
            if case .absent = $0.activity {
                true
            } else {
                false
            }
        }) {
            parts.activity = .absent
            parts.baselineExtra = parts.total - parts.resting
        }
        return parts
    }

    private static func displayedActivity(_ activity: DailyEnergyTotal.Activity, fitting remainder: Int) -> DailyEnergyTotal.Activity {
        switch activity {
        case .absent:
            .absent
        case let .selected(value):
            .selected(Double(min(whole(value), max(0, remainder))))
        case let .recordedTraining(value):
            .recordedTraining(Double(min(whole(value), max(0, remainder))))
        case let .disaggregated(training, remaining):
            let activity = min(whole(training + remaining), max(0, remainder))
            let train = min(whole(training), activity)
            return .disaggregated(training: Double(train), remaining: Double(activity - train))
        }
    }

    private static func activityKilocalories(_ activity: DailyEnergyTotal.Activity) -> Int {
        switch activity {
        case .absent:
            0
        case let .selected(value), let .recordedTraining(value):
            whole(value)
        case let .disaggregated(training, remaining):
            whole(training) + whole(remaining)
        }
    }
}
