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
            HStack(spacing: 0) {
                Text(timestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.trailing, 8)
                    .accessibilityLabel(timestampAccessibilityLabel)

                if let traceID {
                    AssistantTraceLink(traceID: traceID)
                }

                Button {
                    isExpanded.toggle()
                    if isExpanded {
                        onExpanded(scrollTarget)
                    }
                } label: {
                    Image(systemName: isExpanded ? "xmark.circle" : "text.bubble")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.tint)
                        .frame(
                            width: AppTheme.minimumTapTarget,
                            height: AppTheme.minimumTapTarget,
                            alignment: .leading
                        )
                        .padding(.leading, 5)
                }
                .buttonStyle(.plain)
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

    init(traceID: UUID) {
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
            } else {
                icon
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("执行日志不可用")
            }
        }
        .buttonStyle(.plain)
    }

    private var icon: some View {
        Image(systemName: "point.3.connected.trianglepath.dotted")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.tint)
            .frame(
                width: AppTheme.minimumTapTarget,
                height: AppTheme.minimumTapTarget,
                alignment: .trailing
            )
            .padding(.trailing, 5)
            .accessibilityLabel("查看这条回复的执行日志")
    }
}
