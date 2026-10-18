import SwiftUI

extension CoachSessionView {
    @ViewBuilder
    func timelineRow(
        _ item: CoachTimelineItem,
        messagesByID: [UUID: CoachMessage],
        scrollProxy proxy: ScrollViewProxy,
        projection: CoachMessageRenderProjection,
        processorIsProcessing: Bool,
        processingHere: Bool,
        isTail: Bool
    ) -> some View {
        switch item.payload {
        case let .message(messageID):
            if let message = messagesByID[messageID] {
                messageBubble(
                    message,
                    scrollProxy: proxy,
                    projection: projection,
                    processorIsProcessing: processorIsProcessing,
                    processingHere: processingHere
                )
            }
        case let .records(references):
            VStack(spacing: 14) {
                ForEach(references, id: \.identityKey) { reference in
                    ChatRecordEditorCard(
                        reference: reference,
                        sourceMessage: nil,
                        isEditable: true,
                        allowsDeferredLoad: true
                    )
                }
            }
            .id(item.scrollID)
            .onAppear {
                guard isTail, !didFinishInitialScroll else { return }
                proxy.scrollTo(item.scrollID, anchor: .bottom)
            }
        }
    }

    func messageBubble(
        _ message: CoachMessage,
        scrollProxy proxy: ScrollViewProxy,
        projection: CoachMessageRenderProjection,
        processorIsProcessing: Bool,
        processingHere: Bool
    ) -> some View {
        CoachBubble(
            message: message,
            isLatestAssistantMessage: message.id
                == projection.latestAssistantMessageID,
            isLive: processingHere
                && message.agentStatus == .running,
            isStaged: message.turnID.map(
                projection.stagedTurnIDs.contains
            ) ?? false,
            canRetry: !processorIsProcessing
                && projection.retryableMessageIDs.contains(message.id),
            showsUserQuestions: message.isFromCoach && message.turnID != nil
                && message.turnID == projection.latestUserTurnID
                && message.id == projection.latestAssistantMessageID,
            onQuestionAnswer: { questionID, optionID, text in
                try submitQuestionAnswer(
                    message,
                    questionID: questionID,
                    optionID: optionID,
                    text: text
                )
            },
            onComposeAnswer: { text in
                try submitComposedAnswer(text)
            },
            onRetry: { retry(message) },
            onDiscardPending: message.turnID.map(
                projection.stagedTurnIDs.contains
            ) == true
                ? { discardPending(message) }
                : nil,
            onFeedbackExpanded: { target in
                AssistantFeedbackScroller.scrollAfterLayout(
                    to: target,
                    using: proxy
                )
            }
        )
        .equatable()
        .id(message.id)
        .onAppear {
            guard !didFinishInitialScroll,
                  message.id == projection.messages.last?.id
            else {
                return
            }
            pinOpenedSessionIfNeeded(
                using: proxy,
                projection: projection
            )
        }
    }
}
