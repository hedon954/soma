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
    let item: SettingsHomeItem
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsHomeIcon(item: item)
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

enum SettingsHomeIconTone: String, CaseIterable, Sendable {
    case body
    case training
    case intelligence
    case health
    case data
    case notification
    case background

    var accent: Color {
        switch self {
        case .body: AppTheme.bodyAccent
        case .training: AppTheme.trainingAccent
        case .intelligence: AppTheme.trendAccent
        case .health: AppTheme.vitalAccent
        case .data: AppTheme.consistencyAccent
        case .notification: AppTheme.warning
        case .background: AppTheme.recoveryAccent
        }
    }
}

enum SettingsHomeItem: String, CaseIterable, Sendable {
    case bodyInfo
    case gym
    case voiceCues
    case llm
    case healthDevices
    case dataBackup
    case taskProgress
    case backgroundProcessing
    case privacy
    case advanced
    case appearance

    var systemImage: String {
        switch self {
        case .bodyInfo: "person.text.rectangle"
        case .gym: "building.2"
        case .voiceCues: "speaker.wave.2"
        case .llm: "sparkles"
        case .healthDevices: "heart.text.square"
        case .dataBackup: "externaldrive"
        case .taskProgress: "waveform.path.ecg"
        case .backgroundProcessing: "server.rack"
        case .privacy: "hand.raised"
        case .advanced: "gearshape.2"
        case .appearance: "circle.lefthalf.filled"
        }
    }

    var tone: SettingsHomeIconTone {
        switch self {
        case .bodyInfo, .privacy: .body
        case .gym, .voiceCues: .training
        case .llm, .advanced: .intelligence
        case .healthDevices: .health
        case .dataBackup, .appearance: .data
        case .taskProgress: .notification
        case .backgroundProcessing: .background
        }
    }
}

struct SettingsHomeIcon: View {
    let item: SettingsHomeItem

    var body: some View {
        Image(systemName: item.systemImage)
            .foregroundStyle(item.tone.accent)
            .frame(width: 22)
            .accessibilityHidden(true)
    }
}

struct SettingsHomeRowLabel: View {
    let item: SettingsHomeItem
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsHomeIcon(item: item)
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }
}
