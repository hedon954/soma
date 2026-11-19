import Foundation
import SwiftData

struct MealCoverage: Equatable, Sendable {
    static let mainMeals: [MealType] = [.breakfast, .lunch, .dinner]
    let recorded: Set<MealType>
    let skipped: Set<MealType>
    var previouslyConfirmedDay = false

    var missing: [MealType] {
        previouslyConfirmedDay ? [] : Self.mainMeals.filter { !recorded.contains($0) && !skipped.contains($0) }
    }

    var isComplete: Bool {
        missing.isEmpty
    }

    static func due(_ meal: MealType, on day: Date, now: Date, calendar: Calendar) -> Bool {
        if !calendar.isDate(day, inSameDayAs: now) {
            return day < calendar.startOfDay(for: now)
        }
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        switch meal {
        case .breakfast: return minutes >= 630
        case .lunch: return minutes >= 900
        case .dinner: return minutes >= 1230
        default: return false
        }
    }
}

@MainActor
enum MealCoverageStore {
    static func skipped(_ entry: EnergyContextEntry?) throws -> Set<MealType> {
        guard let data = entry?.skippedMealsData else { return [] }
        return try Set(JSONDecoder().decode([MealType].self, from: data))
    }

    static func setSkipped(_ skip: Bool, meal: MealType, day: Date, in context: ModelContext,
                           calendar: Calendar = .current, now: Date = .now, save: Bool = true) throws
    {
        let start = calendar.startOfDay(for: day)
        guard start <= now, MealCoverage.mainMeals.contains(meal) else { return }
        let existing = try EnergyEvidenceStore.contextEntry(for: day, in: context, calendar: calendar)
        var meals = try skipped(existing)
        guard meals.contains(meal) != skip else { return }
        if skip {
            meals.insert(meal)
        } else {
            meals.remove(meal)
        }
        let data = try EnergyInputCoding.encode(MealCoverage.mainMeals.filter(meals.contains))
        let entry = existing ?? EnergyContextEntry(key: EnergyEvidenceStore.contextKey(for: day, calendar: calendar),
                                                   date: start, timeZoneIdentifier: calendar.timeZone.identifier)
        if existing == nil {
            context.insert(entry)
        }
        entry.skippedMealsData = meals.isEmpty ? nil : data
        entry.updatedAt = now
        if save {
            do { try context.save() } catch { context.rollback(); throw error }
        }
    }
}

struct MealBackfillTarget: Identifiable, Equatable, Sendable {
    let day: Date
    let meal: MealType

    var id: String {
        "\(day.timeIntervalSinceReferenceDate):\(meal.rawValue)"
    }

    var prompt: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return "帮我记录\(meal.rawValue)："
        }
        return "帮我记录\(year)年\(month)月\(day)日的\(meal.rawValue)："
    }

    static func parse(prompt text: String, reference: Date, calendar: Calendar = .current) -> Self? {
        guard let match = text.firstMatch(of: #/^帮我记录(\d{4})年(\d{1,2})月(\d{1,2})日的(早餐|午餐|晚餐)[：:]/#),
              let year = Int(match.1), let month = Int(match.2), let day = Int(match.3),
              let meal = MealType(rawValue: String(match.4)),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: year, month: month, day: day),
              date <= reference
        else { return nil }
        return Self(day: calendar.startOfDay(for: date), meal: meal)
    }
}
