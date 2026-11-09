import SwiftUI

struct BodyMassSourceIcon: View {
    let source: BodyMassKnownSource
    var size: CGFloat = 22

    var body: some View {
        switch source {
        case .keep:
            Image("KeepLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel(source.accessibilityLabel)
        case .appleHealth:
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.72, weight: .semibold))
                .foregroundStyle(.pink)
                .frame(width: size, height: size)
                .accessibilityLabel(source.accessibilityLabel)
        case .unknown:
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.72, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .accessibilityLabel(source.accessibilityLabel)
        }
    }
}
