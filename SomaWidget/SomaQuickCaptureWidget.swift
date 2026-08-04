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
    let snapshot: SomaWidgetSnapshot?
    let preferences: SomaWidgetPreferences
}

private struct SomaQuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> SomaQuickCaptureEntry {
        SomaQuickCaptureEntry(
            date: .now,
            snapshot: nil,
            preferences: SomaWidgetPreferences()
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (SomaQuickCaptureEntry) -> Void
    ) {
        completion(entry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<SomaQuickCaptureEntry>) -> Void
    ) {
        let current = entry()
        let nextDay = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: current.date)
        ) ?? current.date.addingTimeInterval(86400)
        completion(Timeline(entries: [current], policy: .after(nextDay)))
    }

    private func entry(now: Date = .now) -> SomaQuickCaptureEntry {
        SomaQuickCaptureEntry(
            date: now,
            snapshot: SomaWidgetSharedStore.loadSnapshot(),
            preferences: SomaWidgetSharedStore.loadPreferences()
        )
    }
}

private struct SomaQuickCaptureEntryView: View {
    private let tint = Color(red: 0.08, green: 0.73, blue: 0.39)
    let entry: SomaQuickCaptureEntry

    @Environment(\.widgetFamily) private var family

    private var content: SomaWidgetContent {
        SomaWidgetContentResolver.resolve(
            snapshot: entry.snapshot,
            preferences: entry.preferences,
            now: entry.date
        )
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemLarge:
                largeView
            default:
                mediumView
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

    private var smallView: some View {
        Link(destination: content.route) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: iconName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(content.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(smallDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .accessibilityLabel("\(content.title)，\(smallDetail)")
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "waveform.path.ecg")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                Text("Soma")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("今日训练")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Link(destination: content.route) {
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(content.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(content.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityLabel("\(content.title)，\(content.detail)")

            if content.kind == .quickCapture || content.kind == .firstTraining || content.kind == .rhythm {
                HStack(spacing: 8) {
                    compactLink(action: .text)
                    compactLink(action: .camera)
                    compactLink(action: .media)
                }
            } else {
                HStack(spacing: 8) {
                    compactTrainingLink
                    compactLink(action: .text)
                }
            }
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Soma 本周训练", systemImage: "waveform.path.ecg")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text(entry.snapshot?.generatedAt.formatted(date: .omitted, time: .shortened) ?? "待更新")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Link(destination: content.route) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(content.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(content.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .accessibilityLabel("\(content.title)，\(content.detail)")

            VStack(alignment: .leading, spacing: 5) {
                Text("本周节奏")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(rhythmText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
            HStack(spacing: 10) {
                compactTrainingLink
                compactLink(action: .text)
                compactLink(action: .camera)
            }
        }
    }

    private func compactLink(action: SomaCaptureAction) -> some View {
        Link(destination: action.routeURL) {
            VStack(spacing: 4) {
                Image(systemName: action.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(action.homeTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color(uiColor: .secondarySystemBackground).opacity(0.9),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("用 Soma \(action.title)")
    }

    private var compactTrainingLink: some View {
        Link(destination: SomaWidgetContentResolver.trainingRoute) {
            VStack(spacing: 4) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text("训练")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color(uiColor: .secondarySystemBackground).opacity(0.9),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开训练")
    }

    private var iconName: String {
        switch content.kind {
        case .resume: "play.circle.fill"
        case .fixedPlan: "list.bullet.clipboard.fill"
        case .rhythm: "chart.line.uptrend.xyaxis"
        case .firstTraining: "figure.strengthtraining.traditional"
        case .quickCapture: "square.and.pencil"
        case .unavailable: "arrow.clockwise"
        }
    }

    private var smallDetail: String {
        guard let snapshot = entry.snapshot else { return "打开更新" }
        if content.kind == .rhythm {
            return "本周 \(snapshot.weekWorkoutCount) 次"
        }
        return content.detail
    }

    private var rhythmText: String {
        guard let snapshot = entry.snapshot else { return "打开 Soma 更新训练状态" }
        if snapshot.weekWorkoutCount > 0 {
            return "本周已训练 \(snapshot.weekWorkoutCount) 次"
        }
        if let days = snapshot.daysSinceLastWorkout {
            return days == 0 ? "今天已经训练过" : "距上次训练 \(days) 天"
        }
        return "开始记录你的第一条训练"
    }
}

struct SomaQuickCaptureWidget: Widget {
    let kind = "SomaQuickCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: SomaQuickCaptureProvider()
        ) { entry in
            SomaQuickCaptureEntryView(entry: entry)
        }
        .configurationDisplayName("Soma 今日训练")
        .description("按当前训练情境展示继续、开始或记录入口。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
