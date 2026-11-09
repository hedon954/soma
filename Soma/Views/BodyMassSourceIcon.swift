import SwiftUI

/// 体重记录行统一来源图标容器：与手动 `MediaThumbnail` 同尺寸/圆角/软底，仅字形区分。
struct BodyMassSourceIcon: View {
    let source: BodyMassKnownSource
    /// 与 `MediaThumbnail` 默认宽高对齐。
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            AppSemanticRole.body.softTint
            glyph
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(source.accessibilityLabel)
        .accessibilityIdentifier("body-history-source-icon-\(source.accessibilityIdentifierSuffix)")
    }

    @ViewBuilder
    private var glyph: some View {
        switch source {
        case .keep:
            Image("KeepLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size * 0.55, height: size * 0.55)
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
