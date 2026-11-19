import Foundation
import SwiftData

@MainActor
enum LibraryAndMealTestFixture {
    static var showsBackfill: Bool {
        AppTestRuntime.isRunning && ProcessInfo.processInfo.environment["SOMA_UI_TEST_MEAL_BACKFILL"] == "1"
    }

    static var requestsPhotoSend: Bool {
        AppTestRuntime.isRunning && ProcessInfo.processInfo.environment["SOMA_UI_TEST_SEND_PHOTOS"] == "1"
    }

    static func photoSendMedia() -> [PickedMedia]? {
        guard requestsPhotoSend else { return nil }
        return ["meal-chicken-bowl", "gym-equipment", "workout-squat"].compactMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
                  let data = try? Data(contentsOf: url)
            else { return nil }
            return .image(data)
        }
    }

    static func reminderTime(_ now: Date) -> Date {
        guard showsBackfill, PerformanceTestFixture.requestedStreamScenario == .productionCompletion else { return now }
        return Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: now) ?? now
    }

    static func seedBackfillIfRequested(in context: ModelContext) {
        guard showsBackfill, context.container.configurations.allSatisfy(\.isStoredInMemoryOnly)
        else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let thirdDay = calendar.date(byAdding: .day, value: -3, to: today)
        else { return }
        for (day, types) in [(yesterday, [.breakfast, .lunch, .snack]), (thirdDay, MealCoverage.mainMeals)] {
            for type in types {
                context.insert(MealEntry(date: day, mealType: type, title: "虚构\(type.rawValue)", calories: type == .lunch ? nil : 320))
            }
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            assertionFailure("Meal backfill fixture could not save")
        }
    }

    static func seedIfRequested(in context: ModelContext) {
        guard AppTestRuntime.isRunning,
              ProcessInfo.processInfo.environment["SOMA_UI_LIBRARY_MEALS_FIXTURE"] == "1"
        else { return }
        let day = Calendar.current.startOfDay(for: .now)
        let breakfastPhoto = Bundle.main.url(forResource: "meal-chicken-bowl", withExtension: "jpg")
        for (index, type) in MealType.allCases.enumerated() {
            context.insert(MealEntry(
                date: day.addingTimeInterval(Double(index + 1)), mealType: type,
                title: index == 2 ? "虚构餐食与较长的食物组成名称，用于检查换行" : "虚构餐食 \(index)",
                calories: 200 + index * 50,
                imagePath: index == 0 ? breakfastPhoto?.path : nil
            ))
        }
        let entries: [(String, [String], [String], [String])] = [
            ("分类推举", ["胸大肌"], ["肱三头肌"], ["水平推"]),
            ("分类深蹲", ["股四头肌", "臀大肌"], ["核心"], ["蹲", "髋伸"]),
            ("分类划船", ["背阔肌"], ["肱二头肌"], ["水平拉"]),
            ("分类未标注", [], [], [])
        ]
        for (name, primary, secondary, patterns) in entries {
            let definition = ExerciseDefinition(
                canonicalName: name, primaryMuscles: primary,
                secondaryMuscles: secondary, movementPatterns: patterns
            )
            context.insert(definition)
            if name == "分类推举" {
                for offset in 1 ... 2 {
                    guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: day) else { continue }
                    context.insert(WorkoutEntry(
                        date: date, exercise: name, exerciseID: definition.id,
                        setEntries: [.init(reps: 8 + offset, externalWeightKG: 20), .init(durationSeconds: 30 + offset * 5)]
                    ))
                }
            }
        }
    }
}
