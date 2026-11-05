import SwiftUI

/// 设置选项与日常活动列表共用的来源视觉语言（ADR 0146）。
struct DailyActivitySourceIcon: View {
    enum Kind {
        case apple
        case coros
        case maxSteps
        case winning(DailyActivityWinningSource)

        init(_ preference: DailyActivitySourcePreference) {
            switch preference {
            case .apple: self = .apple
            case .coros: self = .coros
            case .maxSteps: self = .maxSteps
            }
        }
    }

    let kind: Kind
    var size: CGFloat = 22

    var body: some View {
        switch kind {
        case .apple, .winning(.appleHealth):
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.72, weight: .semibold))
                .foregroundStyle(.pink)
                .frame(width: size, height: size)
                .accessibilityLabel("Apple 健康")
        case .coros, .winning(.coros):
            Image("CorosLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("COROS")
        case .maxSteps:
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: size * 0.9, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: size, height: size)
                .accessibilityLabel("步数更大")
        }
    }
}
