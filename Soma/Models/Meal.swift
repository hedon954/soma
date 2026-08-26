import Foundation
import SwiftData

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast = "早餐"
    case lunch = "午餐"
    case afternoonSnack = "下午点心"
    case dinner = "晚餐"
    case snack = "加餐"
    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .afternoonSnack: "sun.haze.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "cup.and.saucer.fill"
        }
    }
}

enum MealNutritionSource: String, Codable, CaseIterable, Sendable {
    case aiEstimate
    case derivedFromItems
    case userEdited
    case imported
}

/// 食物组成层面的定性消化吸收速度。它不是个体餐后血糖曲线或医疗结论。
enum MealGlycemicSpeed: String, Codable, CaseIterable, Identifiable, Sendable {
    case slow
    case moderate
    case fast

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .slow: "较慢"
        case .moderate: "中等"
        case .fast: "较快"
        }
    }
}

struct MealItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var portionDescription: String?
    var calories: Int?
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    init(
        id: UUID = UUID(),
        name: String,
        portionDescription: String? = nil,
        calories: Int? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.portionDescription = portionDescription
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

private enum MealItemStorage {
    static func encode(_ items: [MealItem]) -> Data {
        (try? JSONEncoder().encode(items)) ?? Data()
    }

    static func decode(_ data: Data) -> [MealItem] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([MealItem].self, from: data)) ?? []
    }
}

@Model
final class MealEntry: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var date: Date
    var mealTypeRaw: String
    var title: String
    var calories: Int?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var glycemicSpeedRaw: String?
    var glycemicAssessment: String = ""
    var itemsData: Data = Data()
    var nutritionSourceRaw: String = MealNutritionSource.aiEstimate.rawValue
    var notes: String
    var imagePath: String?
    var mediaAttachmentsData: Data = Data()
    var confidence: Double
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .lunch }
        set { mealTypeRaw = newValue.rawValue }
    }

    init(
        date: Date = .now,
        mealType: MealType,
        title: String,
        calories: Int? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        glycemicSpeed: MealGlycemicSpeed? = nil,
        glycemicAssessment: String = "",
        items: [MealItem] = [],
        nutritionSource: MealNutritionSource = .aiEstimate,
        notes: String = "",
        imagePath: String? = nil,
        mediaAttachments: [MediaAttachmentReference] = [],
        confidence: Double = 0.9,
        sourceTurnID: UUID? = nil,
        sourceSessionID: UUID? = nil
    ) {
        id = UUID()
        self.date = date
        mealTypeRaw = mealType.rawValue
        self.title = title
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        glycemicSpeedRaw = glycemicSpeed?.rawValue
        self.glycemicAssessment = glycemicAssessment
        itemsData = MealItemStorage.encode(items)
        nutritionSourceRaw = nutritionSource.rawValue
        self.notes = notes
        self.imagePath = imagePath
        mediaAttachmentsData = MediaAttachmentStorage.encode(mediaAttachments)
        self.confidence = confidence
        self.sourceTurnID = sourceTurnID
        self.sourceSessionID = sourceSessionID
    }

    var mediaAttachments: [MediaAttachmentReference] {
        get {
            MediaAttachmentStorage.decode(
                mediaAttachmentsData,
                legacyKind: imagePath == nil ? .none : .image,
                legacyPath: imagePath
            )
        }
        set {
            mediaAttachmentsData = MediaAttachmentStorage.encode(newValue)
            imagePath = newValue.first(where: { $0.kind == .image })?.path
        }
    }

    var items: [MealItem] {
        get { MealItemStorage.decode(itemsData) }
        set { itemsData = MealItemStorage.encode(newValue) }
    }

    var nutritionSource: MealNutritionSource {
        get { MealNutritionSource(rawValue: nutritionSourceRaw) ?? .aiEstimate }
        set { nutritionSourceRaw = newValue.rawValue }
    }

    var glycemicSpeed: MealGlycemicSpeed? {
        get { glycemicSpeedRaw.flatMap(MealGlycemicSpeed.init(rawValue:)) }
        set { glycemicSpeedRaw = newValue?.rawValue }
    }

    func replaceItemsAndDeriveTotals(_ newItems: [MealItem]) {
        items = newItems
        nutritionSource = .derivedFromItems
        let totals = MealNutritionTotals.derive(from: newItems)
        calories = totals.calories
        protein = totals.protein
        carbs = totals.carbs
        fat = totals.fat
        // 菜品或份量变化后，旧的定性判断不再可靠；Agent 或用户可显式重新填写。
        glycemicSpeed = nil
        glycemicAssessment = ""
    }
}
