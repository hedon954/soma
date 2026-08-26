import Foundation

/// 编辑草稿保持字符串，空字符串代表“用户没有提供”，保存时写回 nil 而不是 0。
struct MealItemDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var portion: String
    var calories: String
    var protein: String
    var carbs: String
    var fat: String

    init(
        id: UUID = UUID(),
        name: String = "",
        portion: String = "",
        calories: String = "",
        protein: String = "",
        carbs: String = "",
        fat: String = ""
    ) {
        self.id = id
        self.name = name
        self.portion = portion
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    init(item: MealItem) {
        id = item.id
        name = item.name
        portion = item.portionDescription ?? ""
        calories = item.calories.map(String.init) ?? ""
        protein = item.protein.map { $0.formatted() } ?? ""
        carbs = item.carbs.map { $0.formatted() } ?? ""
        fat = item.fat.map { $0.formatted() } ?? ""
    }

    /// 只有份量开头的正数发生变化、且单位/描述完全相同时才联动营养值。
    /// 用户直接修改热量或宏量时不会反向改份量，也不会改动其他字段。
    mutating func updatePortion(_ newValue: String) {
        defer { portion = newValue }
        guard let oldPortion = ParsedMealPortion(portion),
              let newPortion = ParsedMealPortion(newValue),
              oldPortion.unit == newPortion.unit,
              oldPortion.quantity != newPortion.quantity
        else {
            return
        }
        let factor = newPortion.quantity / oldPortion.quantity
        calories = scaledInteger(calories, by: factor)
        protein = scaledDecimal(protein, by: factor)
        carbs = scaledDecimal(carbs, by: factor)
        fat = scaledDecimal(fat, by: factor)
    }

    /// 名称为空的行视为未填写，不写入记录。
    var item: MealItem? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let trimmedPortion = portion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return MealItem(
            id: id,
            name: trimmedName,
            portionDescription: trimmedPortion.isEmpty ? nil : trimmedPortion,
            calories: Int(calories),
            protein: Double(protein),
            carbs: Double(carbs),
            fat: Double(fat)
        )
    }

    static func drafts(for meal: MealEntry) -> [MealItemDraft] {
        guard !meal.items.isEmpty else {
            // 旧记录只有整餐汇总时，把它转成一行菜品，用户可以继续拆解。
            return [MealItemDraft(
                name: meal.title,
                calories: meal.calories.map(String.init) ?? "",
                protein: meal.protein.map { $0.formatted() } ?? "",
                carbs: meal.carbs.map { $0.formatted() } ?? "",
                fat: meal.fat.map { $0.formatted() } ?? ""
            )]
        }
        return meal.items.map(MealItemDraft.init(item:))
    }

    static func title(for items: [MealItem]) -> String {
        let names = items.map(\.name)
        guard names.count > 2 else {
            return names.joined(separator: "、")
        }
        return names.prefix(2).joined(separator: "、") + " 等 \(names.count) 项"
    }

    static func summary(for items: [MealItem]) -> String {
        items
            .map { item in
                let calories = item.calories.map { "\($0)kcal" } ?? "kcal未填写"
                return "\(item.name) \(calories)"
            }
            .joined(separator: "；")
    }

    private func scaledInteger(_ value: String, by factor: Double) -> String {
        guard let number = Double(normalizedNumber(value)) else { return value }
        return String(Int((number * factor).rounded()))
    }

    private func scaledDecimal(_ value: String, by factor: Double) -> String {
        guard let number = Double(normalizedNumber(value)) else { return value }
        return (number * factor).formatted(
            .number.precision(.fractionLength(0 ... 3))
        )
    }

    private func normalizedNumber(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
    }
}

private struct ParsedMealPortion {
    let quantity: Double
    let unit: String

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("约") {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let numberText = String(value.prefix { character in
            character.isNumber || character == "." || character == ","
        })
        guard !numberText.isEmpty,
              let quantity = Double(numberText.replacingOccurrences(of: ",", with: ".")),
              quantity > 0
        else {
            return nil
        }
        let suffix = value.dropFirst(numberText.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty, !suffix.contains(where: \.isNumber) else {
            return nil
        }
        self.quantity = quantity
        unit = suffix.replacingOccurrences(of: " ", with: "")
    }
}
