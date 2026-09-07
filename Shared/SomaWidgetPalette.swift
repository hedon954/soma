import SwiftUI
import UIKit

/// Widget 扩展不编译 AppTheme。色值与 `AppThemePalette` 对齐，避免 systemBackground
/// 配语义字色把内容画没。
enum SomaWidgetPalette {
    static let page = adaptive(light: 0xFFFFFF, dark: 0x000000)
    static let card = adaptive(light: 0xF7F7F7, dark: 0x191919)
    static let ink = adaptive(light: 0x000000, dark: 0xFFFFFF)
    static let secondaryInk = adaptive(light: 0x5C5C5C, dark: 0xA3A3A3)
    static let meal = adaptive(light: 0x00854A, dark: 0x24D77A)
    static let training = adaptive(light: 0xC65000, dark: 0xFF922B)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traits in
                let hex = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: Double((hex >> 16) & 0xFF) / 255,
                    green: Double((hex >> 8) & 0xFF) / 255,
                    blue: Double(hex & 0xFF) / 255,
                    alpha: 1
                )
            }
        )
    }
}
