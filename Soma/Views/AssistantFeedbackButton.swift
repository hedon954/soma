import SwiftData
import SwiftUI

struct AssistantFeedbackScrollTarget: Hashable {
    let messageID: UUID
}

/// BUG 0031：逐回复反馈在消息叶子节点原位展开，不做页面切换，也不改变 CoachView 根状态。
struct AssistantFeedbackButton: View {
    let messageID: UUID
    let traceID: UUID?
    let timestamp: String
    let timestampAccessibilityLabel: String
    var onExpanded: (AssistantFeedbackScrollTarget) -> Void = { _ in }
    @State private var isExpanded = false

    private var scrollTarget: AssistantFeedbackScrollTarget {
        AssistantFeedbackScrollTarget(messageID: messageID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 时间和图标的可见间距保持 12pt；每个按钮仍有互不重叠的 44pt 触达框。
            HStack(spacing: 0) {
                Text(timestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .accessibilityIdentifier("assistant-message-timestamp")
                    .accessibilityLabel(timestampAccessibilityLabel)

                if let traceID {
                    AssistantTraceLink(traceID: traceID, placement: .first)
                }

                Button {
                    isExpanded.toggle()
                    if isExpanded {
                        onExpanded(scrollTarget)
                    }
                } label: {
                    CompactActionLabel(
                        placement: traceID == nil ? .first : .following
                    ) {
                        Image(systemName: isExpanded ? "xmark.circle" : "text.bubble")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.tint)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .frame(
                    width: AppTheme.minimumTapTarget,
                    height: AppTheme.minimumTapTarget
                )
                .contentShape(Rectangle())
                .accessibilityLabel(isExpanded ? "收起反馈" : "反馈这条 AI 回复")
                .accessibilityHint(
                    isExpanded
                        ? "收起当前反馈输入"
                        : "可以写字、添加图片或视频，并给这条回复评分"
                )
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
            }

            if isExpanded {
                VStack(spacing: 0) {
                    FeedbackView(
                        isEmbedded: true,
                        assistantMessageID: messageID,
                        isCompact: true,
                        onSubmitted: {
                            isExpanded = false
                        }
                    )
                    .padding(.bottom, 4)

                    Color.clear
                        .frame(height: 1)
                        .id(scrollTarget)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssistantTraceLink: View {
    @Query private var traces: [AgentTrace]

    let placement: CompactActionVisualPlacement

    init(traceID: UUID, placement: CompactActionVisualPlacement) {
        self.placement = placement
        var descriptor = FetchDescriptor<AgentTrace>(
            predicate: #Predicate { $0.id == traceID }
        )
        descriptor.fetchLimit = 1
        _traces = Query(descriptor)
    }

    var body: some View {
        Group {
            if let trace = traces.first {
                NavigationLink {
                    AgentTraceDetailView(trace: trace)
                } label: {
                    icon
                }
                .frame(
                    width: AppTheme.minimumTapTarget,
                    height: AppTheme.minimumTapTarget
                )
                .contentShape(Rectangle())
                .accessibilityLabel("查看这条回复的执行日志")
            } else {
                icon
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("执行日志不可用")
            }
        }
        .buttonStyle(.plain)
    }

    private var icon: some View {
        CompactActionLabel(placement: placement) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.tint)
                .accessibilityHidden(true)
        }
    }
}
