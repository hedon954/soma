import SwiftUI

struct DailyTargetDeficitField: View {
    @Binding var text: String

    var body: some View {
        LabeledContent("每日目标热量缺口") {
            HStack(spacing: 5) {
                TextField("400", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("每日目标热量缺口")
                    .accessibilityIdentifier("dailyTargetDeficitField")
                Text("kcal").foregroundStyle(.secondary)
            }
        }
        Text("减脂和增肌减脂共用这一设置。默认 400 千卡，可设置为 0 或正数。推荐摄入为预估总消耗减去目标缺口，最低为 0；这不是医疗建议。")
            .font(.caption)
            .foregroundStyle(.secondary)
        if DailyTargetDeficit.parse(text) == nil {
            Text("请输入 0 或正数的有效热量缺口。")
                .foregroundStyle(.red)
        }
    }
}
