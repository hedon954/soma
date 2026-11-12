import Foundation

/// 残差系数：把「静息 + 所选日活动能量没有覆盖的估算消耗」写成静息的倍率。
///
/// 这不是传统全天体力活动水平（PAL）。所选日活动能量已经单独相加，系数不再代表一整天的活动。
/// 当前没有经个体体重或饮食验证的残差算法，`current()` 只返回仓库既有默认数值。
/// 以后的动态校准只替换这个提供方的内部取值；总消耗的消费方继续使用
/// 「静息 × 系数 + 所选日活动能量 + Soma 已记录训练消耗」，不要在公式里写死倍率。
struct ResidualEnergyCoefficient: Equatable, Sendable {
    /// 与原先未校准参考相同的数值。它现在只是初始回退，不是已验证的个人残差系数。
    static let initialFallback = 1.4

    var value: Double

    static func current() -> Self {
        .init(value: initialFallback)
    }

    var isUsable: Bool {
        value.isFinite && (1 ... 4).contains(value)
    }
}
