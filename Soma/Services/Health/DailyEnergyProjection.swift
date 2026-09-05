import Foundation

struct RestingEnergyFormulaInput: Equatable, Sendable {
    let weightKG: Double
    let heightCM: Double
    let age: Int
    let biologicalSex: BiologicalSex
    let dailyKilocalories: Double

    var originalFormula: String {
        switch biologicalSex {
        case .male:
            "男：10 × 体重kg + 6.25 × 身高cm − 5 × 年龄 + 5"
        case .female:
            "女：10 × 体重kg + 6.25 × 身高cm − 5 × 年龄 − 161"
        case .unspecified, .other:
            ""
        }
    }

    var substitutedFormula: String {
        let adjustment = biologicalSex == .male ? "+ 5" : "− 161"
        return "10 × \(weightKG.formatted()) + 6.25 × \(heightCM.formatted()) − 5 × \(age) \(adjustment) = \(Int(dailyKilocalories.rounded())) kcal/天"
    }
}
