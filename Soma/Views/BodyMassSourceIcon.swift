import SwiftUI

/// 体重记录行统一来源图标容器：与手动 `MediaThumbnail` 同尺寸/圆角。
/// Keep 使用 App Store 官方发行页图标原色，不拉伸染色；其它来源用语义软底 + SF Symbol。
struct BodyMassSourceIcon: View {
    let source: BodyMassKnownSource
    /// 与 `MediaThumbnail` 默认宽高对齐。
    var size: CGFloat = 58

    var body: some View {
        Group {
            switch source {
            case .keep:
                Image("KeepLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            case .appleHealth, .unknown:
                ZStack {
                    AppSemanticRole.body.softTint
                    glyph
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .accessibilityLabel(source.accessibilityLabel)
        .accessibilityIdentifier("body-history-source-icon-\(source.accessibilityIdentifierSuffix)")
    }

    @ViewBuilder
    private var glyph: some View {
        switch source {
        case .keep:
            EmptyView()
        case .appleHealth:
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.pink)
        case .unknown:
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(AppSemanticRole.body.accent)
        }
    }
}
