@testable import Soma
import XCTest

final class DailyTargetDeficitTests: XCTestCase {
    func testCalorieDeficitEligibilityIncludesRecomposition() {
        XCTAssertTrue(FitnessGoal.fatLoss.supportsCalorieDeficit)
        XCTAssertTrue(FitnessGoal.recomposition.supportsCalorieDeficit)
        XCTAssertFalse(FitnessGoal.muscleGain.supportsCalorieDeficit)
    }

    func testMissingOrInvalidStoredPreferenceKeepsDefault() {
        for value in [nil, -1, .nan, .infinity, -.infinity] as [Double?] {
            XCTAssertEqual(DailyTargetDeficit.resolve(value), 400)
        }
    }

    func testExplicitZeroAndCustomPreferenceAreNotDefaulted() {
        XCTAssertEqual(DailyTargetDeficit.resolve(0), 0)
        XCTAssertEqual(DailyTargetDeficit.resolve(625.5), 625.5)
    }

    func testInputFormattingDoesNotRoundStoredPreferencesOnReopen() {
        XCTAssertEqual(DailyTargetDeficit.inputText(for: nil), "400")
        XCTAssertEqual(DailyTargetDeficit.inputText(for: 0), "0")
        for value in [625.123456789, Double.greatestFiniteMagnitude] {
            XCTAssertEqual(DailyTargetDeficit.parse(DailyTargetDeficit.inputText(for: value)), value)
        }
    }

    func testInputAcceptsNonnegativeFiniteNumbersAndDecimalComma() {
        XCTAssertEqual(DailyTargetDeficit.parse(" 625.5 "), 625.5)
        XCTAssertEqual(DailyTargetDeficit.parse("625,5"), 625.5)
        XCTAssertEqual(DailyTargetDeficit.parse("0"), 0)
        for text in ["-1", "nan", "inf", "1e999", "abc"] {
            XCTAssertNil(DailyTargetDeficit.parse(text), text)
        }
    }

    func testClearingInputRestoresDefaultAndReminderDoesNotLimitValidValues() {
        XCTAssertEqual(DailyTargetDeficit.parse(""), 400)
        XCTAssertEqual(DailyTargetDeficit.parse("  "), 400)
        XCTAssertFalse(DailyTargetDeficit.needsReminder(800))
        XCTAssertTrue(DailyTargetDeficit.needsReminder(800.5))
        XCTAssertEqual(DailyTargetDeficit.parse("10001"), 10001)
        XCTAssertFalse(DailyTargetDeficit.needsReminder(.infinity))
    }

    @MainActor
    func testBothCoachSummariesUseTheSameGoalEligibilityAndPreference() throws {
        for goal in [FitnessGoal.fatLoss, .recomposition, .muscleGain] {
            for stored in [nil, 0, 625.5] as [Double?] {
                let profile = UserProfile(fitnessGoal: goal.rawValue)
                profile.dailyTargetDeficitKilocalories = stored
                let clause = DailyTargetDeficit.contextClause(goal: goal, stored: stored)
                let summary = ConversationRecorder.profileSummary(profile)
                if goal.supportsCalorieDeficit {
                    XCTAssertNotNil(clause)
                    XCTAssertTrue(try summary.contains(XCTUnwrap(clause)))
                    XCTAssertTrue(summary.contains("用户设置"))
                } else {
                    XCTAssertNil(clause)
                    XCTAssertFalse(summary.contains("每日目标热量缺口"))
                }
            }
        }
    }

    func testBothFatLossGoalsUseDefaultCustomAndZeroDeficits() throws {
        for goal in [FitnessGoal.fatLoss, .recomposition] {
            for (stored, expected) in [(nil, 1800.0), (0.0, 2200.0), (600.0, 1600.0)] as [(Double?, Double)] {
                let rings = try XCTUnwrap(ProgressNutritionRings.day(
                    intake: 1000, protein: 0, carbs: 0, fat: 0,
                    estimate: 2200, weightKG: 70, fitnessGoal: goal,
                    dailyTargetDeficitKilocalories: stored
                ))
                XCTAssertEqual(rings.calories.target, expected, goal.rawValue)
                XCTAssertEqual(CalorieRingStatusCopy(progress: rings.calories).remainingKilocalories, expected - 1000, goal.rawValue)
            }
        }
    }

    func testCustomDeficitChangesFatLossBudgetAndRemainingIntake() throws {
        let rings = try XCTUnwrap(ProgressNutritionRings.day(
            intake: 1000, protein: 0, carbs: 0, fat: 0,
            estimate: 2200, weightKG: 70, fitnessGoal: .fatLoss,
            dailyTargetDeficitKilocalories: 600
        ))
        XCTAssertEqual(rings.calories.target, 1600)
        XCTAssertEqual(CalorieRingStatusCopy(progress: rings.calories).remainingKilocalories, 600)
    }

    func testLargeDeficitClampsBudgetAndRemainingToZeroWithoutPercentage() throws {
        let rings = try XCTUnwrap(ProgressNutritionRings.day(
            intake: 1000, protein: 0, carbs: 0, fat: 0,
            estimate: 2200, weightKG: nil, fitnessGoal: .fatLoss,
            dailyTargetDeficitKilocalories: 3000
        ))
        XCTAssertEqual(rings.calories.target, 0)
        XCTAssertEqual(rings.calories.status, .over)
        XCTAssertEqual(NutritionRingProgress(intake: 0, target: 0).status, .onTarget)
        XCTAssertNil(rings.calories.ratio)
        let copy = CalorieRingStatusCopy(progress: rings.calories)
        XCTAssertNil(copy.remainingKilocalories)
        XCTAssertNil(copy.completedPercent)
    }

    func testCustomDeficitDoesNotChangeOtherGoals() {
        for goal in [.muscleGain, nil] as [FitnessGoal?] {
            let original = NutritionTargetCalculator.targets(weightKG: 70, fitnessGoal: goal, totalKilocalories: 2200)
            let custom = NutritionTargetCalculator.targets(
                weightKG: 70, fitnessGoal: goal, totalKilocalories: 2200, dailyTargetDeficitKilocalories: 600
            )
            XCTAssertEqual(custom, original)
        }
    }

    func testZeroDeficitUsesFullExpenditureAndMissingEstimateStaysMissing() throws {
        XCTAssertEqual(NutritionTargetCalculator.targets(
            weightKG: nil, fitnessGoal: .fatLoss, totalKilocalories: 2200, dailyTargetDeficitKilocalories: 0
        ).calories, 2200)
        let rings = try XCTUnwrap(ProgressNutritionRings.day(
            intake: 1000, protein: 0, carbs: 0, fat: 0,
            estimate: nil, weightKG: 70, fitnessGoal: .fatLoss, dailyTargetDeficitKilocalories: 600
        ))
        XCTAssertNil(rings.calories.target)
    }
}
