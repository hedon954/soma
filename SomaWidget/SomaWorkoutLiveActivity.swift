import ActivityKit
import SwiftUI
import WidgetKit

struct SomaWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        let configuration = ActivityConfiguration(for: SomaWorkoutActivityAttributes.self) { context in
            Group {
                if #available(iOS 18.0, *) {
                    SomaWorkoutLiveActivityBanner(state: context.state)
                } else {
                    SomaWorkoutLiveActivityCard(state: context.state)
                        .padding(14)
                        .activityBackgroundTint(SomaWidgetPalette.card)
                        .activitySystemActionForegroundColor(SomaWidgetPalette.ink)
                }
            }
            .widgetURL(sessionURL(context.attributes.sessionID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbolName)
                        .foregroundStyle(SomaWidgetPalette.training)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.phaseTitle)
                        .font(.headline)
                        .foregroundStyle(SomaWidgetPalette.ink)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(progressCount(context.state))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(SomaWidgetPalette.ink)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SomaWorkoutLiveActivityProgress(state: context.state, compact: true)
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(SomaWidgetPalette.training)
            } compactTrailing: {
                Text(progressCount(context.state))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(SomaWidgetPalette.ink)
            } minimal: {
                ProgressView(value: context.state.progressFraction)
                    .progressViewStyle(.circular)
                    .tint(SomaWidgetPalette.training)
                    .accessibilityLabel(progressCount(context.state))
            }
            .widgetURL(sessionURL(context.attributes.sessionID))
            .keylineTint(SomaWidgetPalette.training)
        }
        if #available(iOS 18.0, *) {
            return configuration.supplementalActivityFamilies([.small])
        }
        return configuration
    }
}

@available(iOS 18.0, *)
private struct SomaWorkoutLiveActivityBanner: View {
    let state: SomaWorkoutActivityAttributes.ContentState

    @Environment(\.activityFamily) private var activityFamily
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        Group {
            if activityFamily == .small {
                SomaWorkoutLiveActivityCompactCard(state: state)
            } else {
                SomaWorkoutLiveActivityCard(state: state)
            }
        }
        .padding(activityFamily == .small ? 10 : 14)
        .activityBackgroundTint(SomaWidgetPalette.card)
        .activitySystemActionForegroundColor(SomaWidgetPalette.ink)
        .background {
            if showsBackground {
                SomaWidgetPalette.card
            }
        }
    }
}

private struct SomaWorkoutLiveActivityCard: View {
    let state: SomaWorkoutActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: state.symbolName)
                .font(.title2)
                .foregroundStyle(SomaWidgetPalette.training)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(state.phaseTitle)
                    .font(.headline)
                    .foregroundStyle(SomaWidgetPalette.ink)
                    .lineLimit(1)
                SomaWorkoutLiveActivityProgress(state: state, compact: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.phaseTitle)，已完成 \(state.completedSetCount)/\(state.totalSetCount) 组")
    }
}

private struct SomaWorkoutLiveActivityCompactCard: View {
    let state: SomaWorkoutActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.symbolName)
                .foregroundStyle(SomaWidgetPalette.training)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(progressCount(state))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(SomaWidgetPalette.ink)
                ProgressView(value: state.progressFraction)
                    .tint(SomaWidgetPalette.training)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("已完成 \(state.completedSetCount)/\(state.totalSetCount) 组")
    }
}

private struct SomaWorkoutLiveActivityProgress: View {
    let state: SomaWorkoutActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            ProgressView(value: state.progressFraction)
                .tint(SomaWidgetPalette.training)
            HStack(spacing: 8) {
                Text("已完成 \(state.completedSetCount)/\(state.totalSetCount) 组")
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(SomaWidgetPalette.secondaryInk)
                    .monospacedDigit()
                Spacer(minLength: 0)
                if let restEndAt = state.restEndAt, restEndAt > .now {
                    Text(timerInterval: .now ... restEndAt, countsDown: true)
                        .font(compact ? .caption.monospacedDigit() : .subheadline.monospacedDigit())
                        .foregroundStyle(SomaWidgetPalette.ink)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

private func progressCount(_ state: SomaWorkoutActivityAttributes.ContentState) -> String {
    "\(state.completedSetCount)/\(state.totalSetCount)"
}

private func sessionURL(_ sessionID: UUID) -> URL {
    URL(string: "soma://workout/session/\(sessionID.uuidString)")!
}
