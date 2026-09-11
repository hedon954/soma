import SwiftUI

struct ProgressEnergyBalanceCaption: View {
    let summary: ProgressEnergyDeficit

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.energyRemainingText)
                .accessibilityHidden(true)
            caption
                .font(.caption.monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(AppTheme.mealSoftTint, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前热量缺口")
        .accessibilityValue(summary.accessibilityValue)
        .accessibilityIdentifier("progress-energy-balance-caption")
    }

    private var caption: Text {
        let deficit = Text("当前热量缺口 ")
            + Text(summary.valueText).foregroundColor(summary.kilocalories == nil ? AppTheme.accent : AppTheme.energyDeficitText)
            + Text(summary.kilocalories == nil ? "" : " kcal")
        guard let remaining = summary.remainingIntakeText else { return deficit }
        return deficit + Text("，仍可摄入 ")
            + Text(remaining).foregroundColor(AppTheme.energyRemainingText)
            + Text(" kcal")
    }
}
