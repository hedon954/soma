@testable import Soma
import XCTest

/// 菜品拆解是事实来源；完整总值和可解释的已知小计必须同时保留。
final class MealNutritionTotalsTests: XCTestCase {
    func testCompleteItemsSumEveryMacro() {
        let totals = MealNutritionTotals.derive(from: [
            MealItem(
                name: "虚构鸡胸",
                calories: 165,
                protein: 31,
                carbs: 0,
                fat: 3.6
            ),
            MealItem(
                name: "虚构米饭",
                calories: 210,
                protein: 4.5,
                carbs: 46,
                fat: 0.4
            )
        ])

        XCTAssertEqual(totals.calories, 375)
        XCTAssertEqual(try XCTUnwrap(totals.protein), 35.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(totals.carbs), 46, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(totals.fat), 4, accuracy: 0.001)
    }

    func testMissingFieldKeepsExactTotalEmptyButStillProvidesKnownSubtotal() {
        let totals = MealNutritionTotals.derive(from: [
            MealItem(name: "鸡胸", calories: 165, protein: 31, carbs: 0, fat: 3.6),
            MealItem(name: "沙拉", calories: 90, carbs: 8, fat: 5)
        ])

        XCTAssertEqual(totals.calories, 255)
        XCTAssertNil(totals.protein)
        XCTAssertEqual(try XCTUnwrap(totals.knownProtein), 31, accuracy: 0.001)
        XCTAssertFalse(totals.proteinIsComplete)
        XCTAssertEqual(try XCTUnwrap(totals.carbs), 8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(totals.knownCarbs), 8, accuracy: 0.001)
        XCTAssertTrue(totals.carbsIsComplete)
    }

    func testEmptyItemsProduceEmptyTotalsInsteadOfZero() {
        XCTAssertEqual(MealNutritionTotals.derive(from: []), .empty)
        XCTAssertNil(MealNutritionTotals.derive(from: []).calories)
    }

    @MainActor
    func testReplaceItemsAndDeriveTotalsUsesTheSharedRule() {
        let meal = MealEntry(
            mealType: .lunch,
            title: "午餐",
            calories: 999,
            protein: 9
        )
        let items = [
            MealItem(name: "鸡胸", calories: 165, protein: 31),
            MealItem(name: "米饭", calories: 210)
        ]

        meal.replaceItemsAndDeriveTotals(items)

        let totals = MealNutritionTotals.derive(from: items)
        XCTAssertEqual(meal.calories, totals.calories)
        XCTAssertNil(meal.protein)
        XCTAssertEqual(meal.nutritionSource, MealNutritionSource.derivedFromItems)
    }

    func testDraftsKeepBlankFieldsNilAndDropUnnamedRows() {
        let named = MealItemDraft(
            name: " 鸡胸 ",
            portion: " 150g ",
            calories: "165",
            protein: "",
            carbs: "0",
            fat: "3.6"
        )
        let unnamed = MealItemDraft(name: "  ", calories: "120")

        let item = try? XCTUnwrap(named.item)
        XCTAssertEqual(item?.name, "鸡胸")
        XCTAssertEqual(item?.portionDescription, "150g")
        XCTAssertEqual(item?.calories, 165)
        XCTAssertNil(item?.protein)
        XCTAssertEqual(item?.carbs, 0)
        XCTAssertNil(unnamed.item)
    }

    func testChangingOnlyPortionCountScalesExistingNutritionFields() {
        var draft = MealItemDraft(
            name: "黑布林",
            portion: "1 颗",
            calories: "20",
            protein: "0.4",
            carbs: "5",
            fat: "0.1"
        )

        draft.updatePortion("2 颗")

        XCTAssertEqual(draft.portion, "2 颗")
        XCTAssertEqual(draft.calories, "40")
        XCTAssertEqual(draft.protein, "0.8")
        XCTAssertEqual(draft.carbs, "10")
        XCTAssertEqual(draft.fat, "0.2")
    }

    func testPortionScalingPreservesMissingFactsAndRejectsAmbiguousChanges() {
        var draft = MealItemDraft(
            name: "虚构水果",
            portion: "1 颗",
            calories: "20",
            protein: "",
            carbs: "5",
            fat: ""
        )

        draft.updatePortion("2 碗")
        XCTAssertEqual(draft.calories, "20")
        XCTAssertEqual(draft.carbs, "5")

        draft.updatePortion("3 碗")
        XCTAssertEqual(draft.calories, "30")
        XCTAssertEqual(draft.carbs, "7.5")
        XCTAssertEqual(draft.protein, "")
        XCTAssertEqual(draft.fat, "")
    }

    func testEditingNutritionDirectlyDoesNotChangePortionOrSiblingFields() {
        var draft = MealItemDraft(
            name: "虚构水果",
            portion: "2 颗",
            calories: "40",
            protein: "0.8",
            carbs: "10",
            fat: "0.2"
        )

        draft.carbs = "12"

        XCTAssertEqual(draft.portion, "2 颗")
        XCTAssertEqual(draft.calories, "40")
        XCTAssertEqual(draft.protein, "0.8")
        XCTAssertEqual(draft.fat, "0.2")
    }

    @MainActor
    func testDraftsFallBackToSingleRowForLegacyMealsWithoutItems() {
        let meal = MealEntry(mealType: .lunch, title: "牛肉面", calories: 620)

        let drafts = MealItemDraft.drafts(for: meal)

        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.name, "牛肉面")
        XCTAssertEqual(drafts.first?.calories, "620")
    }

    func testTitleSummarizesMoreThanTwoDishes() {
        XCTAssertEqual(
            MealItemDraft.title(for: [
                MealItem(name: "鸡胸"), MealItem(name: "米饭")
            ]),
            "鸡胸、米饭"
        )
        XCTAssertEqual(
            MealItemDraft.title(for: [
                MealItem(name: "鸡胸"),
                MealItem(name: "米饭"),
                MealItem(name: "沙拉")
            ]),
            "鸡胸、米饭 等 3 项"
        )
    }
}
