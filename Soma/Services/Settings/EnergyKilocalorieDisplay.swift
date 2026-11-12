import Foundation

/// 界面上的整千卡。统一用远离零的四舍五入，避免 2264.5 在标题里变成 2264、在明细里按分量加总变成 2265。
enum EnergyKilocalorieDisplay {
    struct Parts: Equatable {
        var resting: Int
        var baselineExtra: Int
        var activity: DailyEnergyTotal.Activity
        var training: Int
        var total: Int

        var addsUp: Bool {
            resting + baselineExtra + displayedActivity + training == total
        }

        /// 未记录的活动不显示成 0，加总时按 0 处理。
        var displayedActivity: Int {
            switch activity {
            case .absent:
                0
            case let .selected(value):
                EnergyKilocalorieDisplay.whole(value)
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
        var remainder = max(0, total - resting)
        let activity = displayedActivity(components.activity, fitting: remainder)
        remainder -= activityKilocalories(activity)
        let training = min(whole(components.trainingKilocalories), remainder)
        let extra = total - resting - activityKilocalories(activity) - training
        return Parts(resting: resting, baselineExtra: extra, activity: activity, training: training, total: total)
    }

    static func averaged(_ values: [DailyEnergyTotal.Components]) -> Parts {
        let count = Double(values.count)
        let allActivityAbsent = values.allSatisfy {
            if case .absent = $0.activity {
                true
            } else {
                false
            }
        }
        let mean = DailyEnergyTotal.Components(
            restingKilocalories: values.reduce(0) { $0 + $1.restingKilocalories } / count,
            coefficient: values.reduce(0) { $0 + $1.coefficient } / count,
            activity: allActivityAbsent
                ? .absent
                : .selected(values.reduce(0) { $0 + $1.activityKilocalories } / count),
            trainingKilocalories: values.reduce(0) { $0 + $1.trainingKilocalories } / count
        )
        return parts(mean)
    }

    private static func displayedActivity(_ activity: DailyEnergyTotal.Activity, fitting remainder: Int) -> DailyEnergyTotal.Activity {
        switch activity {
        case .absent:
            .absent
        case let .selected(value):
            .selected(Double(min(whole(value), max(0, remainder))))
        }
    }

    private static func activityKilocalories(_ activity: DailyEnergyTotal.Activity) -> Int {
        switch activity {
        case .absent:
            0
        case let .selected(value):
            whole(value)
        }
    }
}
