import SwiftUI

struct EnergyEvidenceLabelStyle: LabeledContentStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    configuration.label
                    configuration.content
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    configuration.label.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    configuration.content.multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(AppTheme.accent)
    }
}
