import Foundation

/// A user preference, not a measured energy fact or a calibrated coefficient.
enum DailyTargetDeficit {
    static let defaultKilocalories: Double = 400
    static let reminderAbove: Double = 800

    static func isValid(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }

    static func resolve(_ storedValue: Double?) -> Double {
        guard let storedValue, isValid(storedValue) else { return defaultKilocalories }
        return storedValue
    }

    static func inputText(for storedValue: Double?) -> String {
        let text = String(resolve(storedValue))
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    static func needsReminder(_ value: Double) -> Bool {
        isValid(value) && value > reminderAbove
    }

    static func contextClause(goal: FitnessGoal?, stored: Double?) -> String? {
        guard goal?.supportsCalorieDeficit == true else { return nil }
        let deficit = resolve(stored)
        return "每日目标热量缺口 \(deficit.formatted(.number.precision(.fractionLength(0 ... 1)))) 千卡（用户设置；推荐摄入为预估总消耗减去此值，最低为 0）"
    }

    static func parse(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        if normalized.isEmpty {
            return defaultKilocalories
        }
        guard let value = Double(normalized), isValid(value) else { return nil }
        return value
    }
}
