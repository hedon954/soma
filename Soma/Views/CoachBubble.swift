import SwiftUI

/// 气泡以 `.equatable()` 挂载：父层每次 body 重算都会带来新的回调闭包，
/// 默认逐字段比较必然失败并重排整条历史。这里只比较决定渲染结果的输入——
/// 消息对象身份与状态 flags；消息内容本身的变化由 SwiftData Observation
/// 在气泡自己的 body 依赖上精确失效，不依赖父层 diff。
struct CoachBubble: View, Equatable {
    let message: CoachMessage
    var isLatestAssistantMessage = false
    var isLive = false
    var isStaged = false
    var canRetry = false
    var onRetry: () -> Void = {}
    var onDiscardPending: (() -> Void)?
    var onFeedbackExpanded: (AssistantFeedbackScrollTarget) -> Void = { _ in }

    static func == (lhs: CoachBubble, rhs: CoachBubble) -> Bool {
        lhs.message === rhs.message
            && lhs.isLatestAssistantMessage == rhs.isLatestAssistantMessage
            && lhs.isLive == rhs.isLive
            && lhs.isStaged == rhs.isStaged
            && lhs.canRetry == rhs.canRetry
            && (lhs.onDiscardPending == nil) == (rhs.onDiscardPending == nil)
    }

    var body: some View {
        let payload = CoachMessageRenderPayloadCache.payload(for: message)

        HStack(alignment: .top, spacing: 8) {
            if !message.isFromCoach {
                Spacer(minLength: 52)
            }

            VStack(alignment: message.isFromCoach ? .leading : .trailing, spacing: 7) {
                if let label = message.recordType?.recordedLabel {
                    Label(label, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.success)
                }

                if !payload.mediaAttachments.isEmpty {
                    StoredMediaStrip(attachments: payload.mediaAttachments)
                }

                if message.isFromCoach,
                   !payload.turnItems.isEmpty || isLive
                {
                    if isLive {
                        CoachLiveAgentTurnTranscript(
                            persistedItems: payload.turnItems,
                            preparedSegments: payload.transcriptSegments,
                            persistedItemsWithoutActivity: payload.turnItemsWithoutActivity,
                            preparedSegmentsWithoutActivity: payload
                                .transcriptSegmentsWithoutActivity,
                            sourceMessage: message,
                            isEditable: isLatestAssistantMessage,
                            canRetry: canRetry,
                            onRetry: onRetry
                        )
                    } else {
                        AgentTurnTranscript(
                            items: payload.turnItems,
                            preparedSegments: payload.transcriptSegments,
                            isLive: false,
                            sourceMessage: message,
                            isEditable: isLatestAssistantMessage,
                            canRetry: canRetry,
                            onRetry: onRetry
                        )
                    }
                } else if !payload.visibleText.isEmpty, !payload.isAutomaticMediaSummary {
                    Group {
                        if message.isFromCoach {
                            CoachResponseView(payload.visibleText)
                        } else {
                            SelectableChatText(
                                content: payload.visibleText,
                                color: .label
                            )
                        }
                    }
                    .padding(.horizontal, message.isFromCoach ? 2 : 12)
                    .padding(.vertical, message.isFromCoach ? 3 : 8)
                    .background {
                        if !message.isFromCoach {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(AppTheme.insetBackground)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .stroke(AppTheme.separator, lineWidth: 0.5)
                                }
                        }
                    }
                }

                if isStaged, !message.isFromCoach {
                    HStack(spacing: 8) {
                        Label("已暂存，等待队首处理", systemImage: "tray.full")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        if let onDiscardPending {
                            Button(role: .destructive, action: onDiscardPending) {
                                Image(systemName: "trash")
                                    .frame(
                                        width: AppTheme.minimumTapTarget,
                                        height: AppTheme.minimumTapTarget
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("删除这条暂存消息")
                        }
                    }
                }

                metaLine
            }

            if message.isFromCoach {
                Spacer(minLength: 32)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// PRD 033：时间与位置合并成一行 caption，位置不再单独占一个胶囊。
    @ViewBuilder
    private var metaLine: some View {
        let content = ChatMessageMetaLine.make(
            date: message.date,
            locationName: CoachMessageRenderPayloadCache
                .payload(for: message)
                .location?
                .displayName,
            isFromCoach: message.isFromCoach
        )
        if message.isFromCoach, isLive {
            AssistantLiveMetadataLine(
                timestamp: content.text,
                timestampAccessibilityLabel: content.accessibilityLabel
            )
        } else if message.isFromCoach {
            AssistantFeedbackButton(
                messageID: message.id,
                traceID: message.agentTraceID,
                timestamp: content.text,
                timestampAccessibilityLabel: content.accessibilityLabel,
                onExpanded: onFeedbackExpanded
            )
        } else {
            Text(content.text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(content.accessibilityLabel)
                .frame(
                    maxWidth: .infinity,
                    alignment: metaLineAlignment
                )
        }
    }

    private var metaLineAlignment: Alignment {
        switch ChatMessageMetaLine.horizontalAlignment(
            isFromCoach: message.isFromCoach
        ) {
        case .leading:
            .leading
        case .trailing:
            .trailing
        }
    }
}

private struct AssistantLiveMetadataLine: View {
    let timestamp: String
    let timestampAccessibilityLabel: String

    var body: some View {
        Text(timestamp)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .accessibilityLabel(timestampAccessibilityLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
