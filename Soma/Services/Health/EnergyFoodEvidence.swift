import Foundation
import SwiftData

enum EnergyFoodEvidence {
    private struct Meal: Codable {
        let id: UUID
        let date: Date
        let calories: Double?
        let partial: Bool
    }

    static func fingerprint(records: [ProgressHistoryRecord]) -> String {
        let meals = records.filter { $0.activity.kind == .meal }.map {
            Meal(id: $0.activity.id, date: $0.activity.date, calories: $0.calories, partial: $0.caloriesArePartial)
        }
        return digest(meals)
    }

    static func fingerprint(on day: Date, in context: ModelContext, calendar: Calendar = .current) throws -> String {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { throw EnergyCalculationError.invalidInput }
        var query = FetchDescriptor<MealEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        query.fetchLimit = 256
        var meals: [Meal] = []
        while true {
            let page = try context.fetch(query)
            meals += page.map { meal in
                let totals = meal.items.isEmpty ? nil : MealNutritionTotals.derive(from: meal.items)
                return .init(id: meal.id, date: meal.date, calories: (totals?.knownCalories ?? meal.calories).map(Double.init),
                             partial: totals.map { !$0.caloriesIsComplete } ?? (meal.calories == nil))
            }
            if page.count < 256 {
                break
            }
            query.fetchOffset = (query.fetchOffset ?? 0) + page.count
        }
        return digest(meals)
    }

    private static func digest(_ meals: [Meal]) -> String {
        let sorted = meals.sorted { $0.id.uuidString < $1.id.uuidString }
        guard let data = try? EnergyInputCoding.encode(sorted) else { return "invalid-meal-evidence" }
        return EnergyInputCoding.digest(data)
    }
}
