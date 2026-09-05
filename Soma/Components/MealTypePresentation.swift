import SwiftUI

/// A meal keeps the same category color regardless of its position in the breakdown.
enum MealTypePresentation {
    static func accent(_ type: MealType) -> Color {
        let colors = palette(type)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? colors.dark.uiColor : colors.light.uiColor
        })
    }

    static func palette(_ type: MealType) -> (light: AppThemeRGB, dark: AppThemeRGB) {
        switch type {
        case .breakfast: (AppThemeRGB(hex: 0xBF4B00), AppThemePalette.darkTraining)
        case .lunch: (AppThemeRGB(hex: 0x008047), AppThemePalette.darkMeal)
        case .afternoonSnack: (AppThemeRGB(hex: 0x007C84), AppThemePalette.darkConsistency)
        case .dinner: (AppThemePalette.lightTrend, AppThemePalette.darkTrend)
        case .snack: (AppThemePalette.lightVital, AppThemePalette.darkVital)
        }
    }
}
