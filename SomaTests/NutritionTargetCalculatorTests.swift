@testable import Soma
import XCTest

final class NutritionTargetCalculatorTests: XCTestCase {
    func testMuscleGainUsesSurplusAndProteinPerKilogram() {
        let targets = NutritionTargetCalculator.targets(
            weightKG: 70,
            fitnessGoal: .muscleGain,
            totalKilocalories: 2200
        )
        XCTAssertEqual(targets.calories, 2450)
        XCTAssertEqual(targets.proteinGrams ?? -1, 126, accuracy: 0.001)
        XCTAssertEqual(targets.fatGrams ?? -1, 2450 * 0.25 / 9, accuracy: 0.001)
        let remaining = 2450 - 126 * 4 - (2450 * 0.25)
        XCTAssertEqual(targets.carbsGrams ?? -1, remaining / 4, accuracy: 0.001)
    }

    func testMissingWeightKeepsCalorieTargetOnly() {
        let targets = NutritionTargetCalculator.targets(
            weightKG: nil,
            fitnessGoal: .fatLoss,
            totalKilocalories: 2000
        )
        XCTAssertEqual(targets.calories, 1600)
        XCTAssertNil(targets.proteinGrams)
        XCTAssertNil(targets.carbsGrams)
        XCTAssertNil(targets.fatGrams)
    }

    func testIntakeStatusUsesProductThresholds() {
        XCTAssertEqual(NutritionIntakeStatus.from(ratio: 0.84), .under)
        XCTAssertEqual(NutritionIntakeStatus.from(ratio: 0.85), .onTarget)
        XCTAssertEqual(NutritionIntakeStatus.from(ratio: 1.15), .onTarget)
        XCTAssertEqual(NutritionIntakeStatus.from(ratio: 1.16), .over)
        XCTAssertEqual(NutritionIntakeStatus.from(ratio: nil), .noTarget)
    }

    func testCalorieRemainingCaptionUsesPositiveDeficitOnly() {
        let under = CalorieRingStatusCopy(
            progress: NutritionRingProgress(intake: 1429, target: 1971)
        )
        XCTAssertEqual(under.remainingKilocalories ?? -1, 542, accuracy: 0.001)
        XCTAssertEqual(under.completedPercent, 73)

        let reached = CalorieRingStatusCopy(
            progress: NutritionRingProgress(intake: 1971, target: 1971)
        )
        XCTAssertNil(reached.remainingKilocalories)
        XCTAssertEqual(reached.completedPercent, 100)

        let over = CalorieRingStatusCopy(
            progress: NutritionRingProgress(intake: 2200, target: 1971)
        )
        XCTAssertNil(over.remainingKilocalories)
        XCTAssertEqual(over.completedPercent, 112)

        let missing = CalorieRingStatusCopy(
            progress: NutritionRingProgress(intake: 860, target: nil)
        )
        XCTAssertNil(missing.remainingKilocalories)
        XCTAssertNil(missing.completedPercent)
    }
}
