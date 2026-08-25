import SwiftUI

struct CoachBubble: View {
    let message: CoachMessage
    var isLatestAssistantMessage = false
    var isLive = false
    var observesLiveText = true
    var isStaged = false
    var canRetry = false
    var onRetry: () -> Void = {}
    var onDiscardPending: (() -> Void)?
    var onFeedbackExpanded: (AssistantFeedbackScrollTarget) -> Void = { _ in }
    var onLiveRevision: () -> Void = {}

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
                            observesLiveText: observesLiveText,
                            sourceMessage: message,
                            isEditable: isLatestAssistantMessage,
                            canRetry: canRetry,
                            onRetry: onRetry,
                            onLiveRevision: onLiveRevision
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
        if message.isFromCoach, !isLive {
            AssistantFeedbackButton(
                messageID: message.id,
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
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
