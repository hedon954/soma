import ActivityKit
import SwiftUI
import WidgetKit

private enum SomaCaptureAction {
    case text
    case camera
    case media

    var homeTitle: String {
        switch self {
        case .text:
            "文字"
        case .camera:
            "拍照"
        case .media:
            "照片/视频"
        }
    }

    var title: String {
        switch self {
        case .text:
            "文字记录"
        case .camera:
            "拍照记录"
        case .media:
            "照片/视频"
        }
    }

    var inlineTitle: String {
        switch self {
        case .text:
            "Soma 文字记录"
        case .camera:
            "Soma 拍照"
        case .media:
            "Soma 照片/视频"
        }
    }

    var detail: String {
        switch self {
        case .text:
            "打开教练输入"
        case .camera:
            "直接打开相机"
        case .media:
            "选择照片与视频"
        }
    }

    var configurationDisplayName: LocalizedStringKey {
        switch self {
        case .text:
            "Soma 文字记录"
        case .camera:
            "Soma 拍照记录"
        case .media:
            "Soma 照片/视频"
        }
    }

    var configurationDescription: LocalizedStringKey {
        switch self {
        case .text:
            "打开教练输入"
        case .camera:
            "直接打开相机"
        case .media:
            "选择照片与视频"
        }
    }

    var systemImage: String {
        switch self {
        case .text:
            "text.bubble.fill"
        case .camera:
            "camera.fill"
        case .media:
            "photo.stack.fill"
        }
    }

    var routeURL: URL {
        switch self {
        case .text:
            URL(string: "soma://capture/text")!
        case .camera:
            URL(string: "soma://capture/camera")!
        case .media:
            URL(string: "soma://capture/media")!
        }
    }

    var widgetKind: String {
        switch self {
        case .text:
            "SomaLockScreenTextCaptureWidget"
        case .camera:
            "SomaLockScreenCameraCaptureWidget"
        case .media:
            "SomaLockScreenMediaCaptureWidget"
        }
    }
}

private struct SomaQuickCaptureEntry: TimelineEntry {
    let date: Date
}

private struct SomaQuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> SomaQuickCaptureEntry {
        SomaQuickCaptureEntry(date: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (SomaQuickCaptureEntry) -> Void
    ) {
        completion(SomaQuickCaptureEntry(date: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<SomaQuickCaptureEntry>) -> Void
    ) {
        completion(Timeline(entries: [SomaQuickCaptureEntry(date: .now)], policy: .never))
    }
}

private struct SomaQuickCaptureEntryView: View {
    private let tint = Color(red: 0.08, green: 0.73, blue: 0.39)
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Image(systemName: "waveform.path.ecg")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Soma")
                        .font(.headline.weight(.semibold))
                    Text("快速记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Your body, understood.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                captureLink(action: .text)
                captureLink(action: .camera)
                captureLink(action: .media)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    tint.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func captureLink(action: SomaCaptureAction) -> some View {
        Link(destination: action.routeURL) {
            VStack(spacing: 7) {
                Image(systemName: action.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                Text(action.homeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color(uiColor: .secondarySystemBackground).opacity(0.9),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("用 Soma \(action.title)")
    }
}

struct SomaQuickCaptureWidget: Widget {
    let kind = "SomaQuickCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: SomaQuickCaptureProvider()
        ) { _ in
            SomaQuickCaptureEntryView()
        }
        .configurationDisplayName("Soma 快速记录")
        .description("一步开始文字、拍照或照片与视频记录。")
        .supportedFamilies([.systemMedium])
    }
}

private struct SomaAgentJobLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SomaAgentJobAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.symbolName)
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.phaseTitle)
                        .font(.headline)
                    Text(statusDetail(context.state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .widgetURL(
                URL(string: "soma://agent/turn/\(context.attributes.turnID.uuidString)")
            )
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbolName)
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.phaseTitle)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(statusDetail(context.state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text("\(context.state.operationCount)")
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(.green)
            }
            .widgetURL(
                URL(string: "soma://agent/turn/\(context.attributes.turnID.uuidString)")
            )
        }
    }

    private func statusDetail(
        _ state: SomaAgentJobAttributes.ContentState
    ) -> String {
        if state.isStale {
            return "状态可能已过期，打开 Soma 同步"
        }
        var values = ["已完成 \(state.operationCount) 项操作"]
        if state.queuedCount > 0 {
            values.append("另有 \(state.queuedCount) 项等待")
        }
        return values.joined(separator: " · ")
    }
}

private struct SomaWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SomaWorkoutActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.symbolName)
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.phaseTitle)
                        .font(.headline)
                    workoutStatus(context.state)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .widgetURL(
                URL(string: "soma://workout/session/\(context.attributes.sessionID.uuidString)")
            )
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbolName)
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.phaseTitle)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    workoutStatus(context.state)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text("\(context.state.completedSetCount)/\(context.state.totalSetCount)")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(.green)
            }
            .widgetURL(
                URL(string: "soma://workout/session/\(context.attributes.sessionID.uuidString)")
            )
        }
    }

    @ViewBuilder
    private func workoutStatus(
        _ state: SomaWorkoutActivityAttributes.ContentState
    ) -> some View {
        if let restEndAt = state.restEndAt, restEndAt > .now {
            Text(timerInterval: .now ... restEndAt, countsDown: true)
                .monospacedDigit()
        } else {
            Text("已完成 \(state.completedSetCount)/\(state.totalSetCount) 组")
                .monospacedDigit()
        }
    }
}

private struct SomaLockScreenCaptureEntryView: View {
    let action: SomaCaptureAction

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label(action.inlineTitle, systemImage: action.systemImage)
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: action.systemImage)
                        .font(.title3.weight(.semibold))
                        .widgetAccentable()
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: action.systemImage)
                        .font(.title3.weight(.semibold))
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(action.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(action.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            default:
                EmptyView()
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
        .widgetURL(action.routeURL)
        .accessibilityLabel("用 Soma \(action.title)")
    }
}

private func lockScreenConfiguration(
    for action: SomaCaptureAction
) -> some WidgetConfiguration {
    StaticConfiguration(
        kind: action.widgetKind,
        provider: SomaQuickCaptureProvider()
    ) { _ in
        SomaLockScreenCaptureEntryView(action: action)
    }
    .configurationDisplayName(action.configurationDisplayName)
    .description(action.configurationDescription)
    .supportedFamilies([
        .accessoryInline,
        .accessoryCircular,
        .accessoryRectangular
    ])
}

private struct SomaLockScreenTextCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        lockScreenConfiguration(for: .text)
    }
}

private struct SomaLockScreenCameraCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        lockScreenConfiguration(for: .camera)
    }
}

private struct SomaLockScreenMediaCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        lockScreenConfiguration(for: .media)
    }
}

@main
struct SomaWidgetBundle: WidgetBundle {
    var body: some Widget {
        SomaQuickCaptureWidget()
        SomaLockScreenTextCaptureWidget()
        SomaLockScreenCameraCaptureWidget()
        SomaLockScreenMediaCaptureWidget()
        SomaAgentJobLiveActivity()
        SomaWorkoutLiveActivity()
    }
}
