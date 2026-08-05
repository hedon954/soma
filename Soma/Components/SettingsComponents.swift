import SwiftUI

enum SettingsRoute: Hashable {
    case llm
}

struct AIConfigurationReminder: View {
    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("请先配置标准模型的 API Key")
                        .font(.headline)
                    Text("配置完成后，刚才暂存的消息会按发送顺序自动继续处理。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "key.fill")
                    .foregroundStyle(AppTheme.warning)
            }
        }
    }
}

struct SettingsSummaryRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
