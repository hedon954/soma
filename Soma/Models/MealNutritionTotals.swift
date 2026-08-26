import Foundation

/// 菜品拆解是事实来源，汇总是纯派生。完整总值继续保持严格；同时保留已知小计，
/// 让界面能展示“至少”多少，而不是因为一项缺失就把全部已知事实隐藏掉。
struct MealNutritionTotals: Equatable, Sendable {
    var calories: Int?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var knownCalories: Int?
    var knownProtein: Double?
    var knownCarbs: Double?
    var knownFat: Double?
    var caloriesIsComplete = false
    var proteinIsComplete = false
    var carbsIsComplete = false
    var fatIsComplete = false

    static let empty = MealNutritionTotals()

    /// 精确总值只有在所有菜品都提供该字段时成立；否则只返回非空项的已知小计。
    static func derive(from items: [MealItem]) -> MealNutritionTotals {
        guard !items.isEmpty else { return .empty }
        let calories = aggregate(items.map(\.calories))
        let protein = aggregate(items.map(\.protein))
        let carbs = aggregate(items.map(\.carbs))
        let fat = aggregate(items.map(\.fat))
        return MealNutritionTotals(
            calories: calories.isComplete ? calories.known : nil,
            protein: protein.isComplete ? protein.known : nil,
            carbs: carbs.isComplete ? carbs.known : nil,
            fat: fat.isComplete ? fat.known : nil,
            knownCalories: calories.known,
            knownProtein: protein.known,
            knownCarbs: carbs.known,
            knownFat: fat.known,
            caloriesIsComplete: calories.isComplete,
            proteinIsComplete: protein.isComplete,
            carbsIsComplete: carbs.isComplete,
            fatIsComplete: fat.isComplete
        )
    }

    private static func aggregate<T: AdditiveArithmetic>(
        _ values: [T?]
    ) -> (known: T?, isComplete: Bool) {
        let knownValues = values.compactMap { $0 }
        return (
            knownValues.isEmpty ? nil : knownValues.reduce(.zero, +),
            knownValues.count == values.count
        )
    }
}
