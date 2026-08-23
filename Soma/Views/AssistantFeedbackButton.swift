import SwiftUI

struct AssistantFeedbackScrollTarget: Hashable {
    let messageID: UUID
}

/// BUG 0031：逐回复反馈在消息叶子节点原位展开，不做页面切换，也不改变 CoachView 根状态。
struct AssistantFeedbackButton: View {
    let messageID: UUID
    let timestamp: String
    let timestampAccessibilityLabel: String
    var onExpanded: (AssistantFeedbackScrollTarget) -> Void = { _ in }
    @State private var isExpanded = false

    private var scrollTarget: AssistantFeedbackScrollTarget {
        AssistantFeedbackScrollTarget(messageID: messageID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(timestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel(timestampAccessibilityLabel)

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
