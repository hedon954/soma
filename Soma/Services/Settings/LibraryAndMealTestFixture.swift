import Foundation
import SwiftData

@MainActor
enum LibraryAndMealTestFixture {
    static func seedIfRequested(in context: ModelContext) {
        guard AppTestRuntime.isRunning,
              ProcessInfo.processInfo.environment["SOMA_UI_LIBRARY_MEALS_FIXTURE"] == "1"
        else { return }
        let day = Calendar.current.startOfDay(for: .now)
        for (index, type) in MealType.allCases.enumerated() {
            context.insert(MealEntry(
                date: day.addingTimeInterval(Double(index + 1)), mealType: type,
                title: index == 2 ? "虚构餐食与较长的食物组成名称，用于检查换行" : "虚构餐食 \(index)",
                calories: 200 + index * 50
            ))
        }
        let entries: [(String, [String], [String], [String])] = [
            ("分类推举", ["胸大肌"], ["肱三头肌"], ["水平推"]),
            ("分类深蹲", ["股四头肌", "臀大肌"], ["核心"], ["蹲", "髋伸"]),
            ("分类划船", ["背阔肌"], ["肱二头肌"], ["水平拉"]),
            ("分类未标注", [], [], [])
        ]
        for (name, primary, secondary, patterns) in entries {
            context.insert(ExerciseDefinition(
                canonicalName: name, primaryMuscles: primary,
                secondaryMuscles: secondary, movementPatterns: patterns
            ))
        }
    }
}
