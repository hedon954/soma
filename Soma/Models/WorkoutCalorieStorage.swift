import Foundation

extension WorkoutEntry {
    var calorieScope: WorkoutCalorieScope {
        get { calorieScopeRaw.flatMap(WorkoutCalorieScope.init(rawValue:)) ?? .unknown }
        set { calorieScopeRaw = newValue.rawValue }
    }

    /// An unrelated edit must not replace a user-provided value with a new formula estimate.
    var recordedCalorieOverride: Int? {
        calorieScope == .metGross ? nil : estimatedCalories
    }
}
