import SwiftUI
import WidgetKit

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
                captureLink(
                    title: "文字",
                    icon: "text.bubble.fill",
                    route: "soma://capture/text"
                )
                captureLink(
                    title: "拍照",
                    icon: "camera.fill",
                    route: "soma://capture/camera"
                )
                captureLink(
                    title: "照片/视频",
                    icon: "photo.stack.fill",
                    route: "soma://capture/media"
                )
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

    private func captureLink(
        title: String,
        icon: String,
        route: String
    ) -> some View {
        Link(destination: URL(string: route)!) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
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
        .accessibilityLabel("用 Soma \(title)记录")
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

@main
struct SomaWidgetBundle: WidgetBundle {
    var body: some Widget {
        SomaQuickCaptureWidget()
    }
}
