import Foundation

/// A user preference, not a measured energy fact or a calibrated coefficient.
enum DailyTargetDeficit {
    static let defaultKilocalories: Double = 400

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

    static func parse(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), isValid(value) else { return nil }
        return value
    }
}
