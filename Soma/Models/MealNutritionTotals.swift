import Foundation

/// ADR 0084：菜品拆解是事实来源，汇总是纯派生。缺项保持为空而不是补零，卡片和写入路径
/// 共用同一条规则，避免两处各算一套。
struct MealNutritionTotals: Equatable, Sendable {
    var calories: Int?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var totalSugar: Double?

    static let empty = MealNutritionTotals()

    /// 只有当所有菜品都提供了某个字段时才汇总；任一缺失就保持为空。
    static func derive(from items: [MealItem]) -> MealNutritionTotals {
        guard !items.isEmpty else { return .empty }
        return MealNutritionTotals(
            calories: sumIfComplete(items.map(\.calories)),
            protein: sumIfComplete(items.map(\.protein)),
            carbs: sumIfComplete(items.map(\.carbs)),
            fat: sumIfComplete(items.map(\.fat)),
            totalSugar: sumIfComplete(items.map(\.totalSugar))
        )
    }

    private static func sumIfComplete<T: AdditiveArithmetic>(_ values: [T?]) -> T? {
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }.reduce(.zero, +)
    }
}
