import Observation
import OSLog
import SwiftData
import SwiftUI
import UIKit

extension CoachSessionView {
    func submitCurrentDraft(
        quickRecordOverride: ExerciseInputSuggestion? = nil
    ) {
        guard !isPersistingSubmission else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        speechInput?.stop()
        let pending = attachments
        let session = conversationSessions.ensureActiveSession(
            dataSpace: dataSpace.activeSpace,
            in: modelContext
        )
        guard let processingContext = ConversationProcessingContextFactory.make(
            sessionID: session.id,
            dataSpace: dataSpace.activeSpace,
            ai: ai,
            in: modelContext
        ) else {
            return
        }
        let quickRecord = quickRecordOverride ?? selectedExerciseSuggestion
        let exactQuickDraft = pending.isEmpty
            && quickRecord?.draftText == text
            ? quickRecord?.recordDraft
            : nil
        // 精确的结构化快捷记录不经过 LLM，即使尚未配置 API Key 也不应打断发送。
        // 其他路径仍要在落盘前判断：提交后暂存计数会从 0 变成 1。
        let needsConfigurationGuidance = exactQuickDraft == nil
            && needsConfigurationGuidance(forceLocal: useLocalForNextMessage)
        if let exactQuickDraft {
            let accepted = processor.submitQuickWorkout(
                text: text,
                draft: exactQuickDraft,
                context: processingContext,
                locationService: locationContext
            )
            if accepted {
                finishAcceptedSubmission(
                    needsConfigurationGuidance: needsConfigurationGuidance
                )
            }
            return
        }
        isPersistingSubmission = true
        Task { @MainActor in
            let accepted = await processor.submitAsync(
                text: text,
                attachments: pending,
                context: processingContext,
                includeLocation: locationPreference == .enabled,
                locationService: locationContext,
                selectedShortcutID: selectedShortcutID,
                forceLocal: useLocalForNextMessage
            )
            isPersistingSubmission = false
            if accepted {
                finishAcceptedSubmission(
                    needsConfigurationGuidance: needsConfigurationGuidance
                )
            }
        }
    }

    func finishAcceptedSubmission(
        needsConfigurationGuidance: Bool
    ) {
        draft = ""
        attachments = []
        useLocalForNextMessage = false
        selectedExerciseSuggestion = nil
        selectedShortcutID = nil
        composerDismissRequest = UUID()
        scrollRequest = UUID()
        if needsConfigurationGuidance {
            openLLMConfiguration()
        }
    }

    func retry(_ responseMessage: CoachMessage) {
        guard let turnID = responseMessage.turnID else { return }
        retry(turnID: turnID)
    }

    func retryPendingQueue() -> Bool {
        processor.retryPendingQueue(
            dataSpace: dataSpace.activeSpace,
            ai: ai,
            modelContext: modelContext,
            locationService: locationContext
        )
    }

    func retry(turnID: UUID) {
        let needsConfigurationGuidance = needsConfigurationGuidance(forceLocal: false)
        guard let userMessage = ConversationTurnProjection.userMessage(
            for: turnID,
            in: messages
        )
        else {
            return
        }
        let session = conversationSessions.ensureActiveSession(
            dataSpace: dataSpace.activeSpace,
            in: modelContext
        )
        guard let processingContext = ConversationProcessingContextFactory.make(
            sessionID: session.id,
            dataSpace: dataSpace.activeSpace,
            ai: ai,
            in: modelContext
        ) else {
            return
        }
        if processor.retry(
            userMessage: userMessage,
            context: processingContext,
            locationService: locationContext
        ) {
            composerDismissRequest = UUID()
            scrollRequest = UUID()
            if needsConfigurationGuidance {
                openLLMConfiguration()
            }
        }
    }

    func discardPending(_ message: CoachMessage) {
        guard let turnID = message.turnID else { return }
        _ = discardPending(
            turnID: turnID,
            sessionID: message.sessionID ?? conversationSessions.activeSessionID ?? UUID()
        )
    }

    func discardPending(turnID: UUID, sessionID: UUID) -> Bool {
        guard let processingContext = ConversationProcessingContextFactory.make(
            sessionID: sessionID,
            dataSpace: dataSpace.activeSpace,
            ai: ai,
            in: modelContext
        )
        else {
            return false
        }
        return processor.discardPendingTurn(
            turnID: turnID,
            context: processingContext,
            locationService: locationContext
        )
    }

    func clearPendingQueue() -> Bool {
        guard let sessionID = conversationSessions.activeSessionID,
              let processingContext = ConversationProcessingContextFactory.make(
                  sessionID: sessionID,
                  dataSpace: dataSpace.activeSpace,
                  ai: ai,
                  in: modelContext
              )
        else {
            return false
        }
        return processor.clearPendingQueue(context: processingContext)
    }

    /// ADR 0045：缺配置不再阻止发送。队列里还没有暂存消息时说明用户是第一次遇到，
    /// 此时把消息落盘暂存并同时打开「LLM 配置」；之后只靠输入区的暂存提示，不再打断。
    func needsConfigurationGuidance(forceLocal: Bool) -> Bool {
        if !forceLocal, RemoteAgentPreference.isEnabled() {
            return false
        }
        return !ai.hasRequiredAPIKey && pendingJobCount == 0
    }

    func openLLMConfiguration() {
        speechInput?.stop()
        onRequireAIConfiguration()
    }

    func openLLMConfigurationFromPendingQueue() {
        sheet = nil
        Task { @MainActor in
            await Task.yield()
            openLLMConfiguration()
        }
    }

    func toggleVoice() {
        if speechInput?.isListening == true {
            speechInput?.stop()
            return
        }

        draftBeforeSpeech = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = speechInput ?? SpeechInputService()
        speechInput = service
        Task {
            await service.start()
        }
    }

    func updateDraftFromSpeech() {
        guard let speechInput else { return }
        let transcript = speechInput.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        draft = [draftBeforeSpeech, transcript]
            .filter { !$0.isEmpty }
            .joined(separator: draftBeforeSpeech.isEmpty ? "" : " ")
    }

    func scrollToBottom(
        _ proxy: ScrollViewProxy,
        animated: Bool = true
    ) {
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    /// 与文字投影一致约 5Hz 非动画跟随；结束后再做一次动画归位。
    func scheduleLiveScroll(_ proxy: ScrollViewProxy) {
        guard isProcessingHere, followsLiveMessage else { return }
        let interval: TimeInterval = 0.2
        let elapsed = Date().timeIntervalSince(lastLiveScrollAt)
        if elapsed >= interval {
            lastLiveScrollAt = Date()
            scrollToBottom(proxy, animated: false)
            return
        }
        guard liveScrollTask == nil else { return }
        let delay = interval - elapsed
        liveScrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            liveScrollTask = nil
            guard !Task.isCancelled, isProcessingHere, followsLiveMessage else {
                return
            }
            lastLiveScrollAt = Date()
            scrollToBottom(proxy, animated: false)
        }
    }

    func scrollToBottomAfterLayout(
        _ proxy: ScrollViewProxy,
        completion: (() -> Void)? = nil
    ) {
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            scrollToBottom(proxy, animated: false)
            await Task.yield()
            guard !Task.isCancelled else { return }
            completion?()
        }
    }

    func finishInitialScrollSetup(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard !Task.isCancelled else { return }
            if !messageListPosition.isNearBottom {
                followsLiveMessage = true
                scrollToBottom(proxy, animated: false)
                await Task.yield()
                guard !Task.isCancelled else { return }
            }
            didFinishInitialScroll = true
            paginationTriggerID = UUID()
            if let activeSessionID = conversationSessions.activeSessionID {
                sessionTransition.contentDidBecomeVisible(activeSessionID)
            }
        }
    }

    func loadEarlierKeepingPosition(
        using _: ScrollViewProxy,
        projection: CoachMessageRenderProjection
    ) {
        guard didFinishInitialScroll,
              hasUserInteractedWithMessageList,
              !isLoadingEarlier,
              projection.hasEarlierMessages,
              let anchor = projection.messages.first?.id
        else {
            return
        }
        isLoadingEarlier = true
        paginationAnchorMessageID = anchor
        onLoadEarlier()
    }

    func beginMessageHistoryInteraction() {
        hasUserInteractedWithMessageList = true
        stopFollowingLiveMessage()
    }

    func stopFollowingLiveMessage() {
        followsLiveMessage = false
        liveScrollTask?.cancel()
        liveScrollTask = nil
    }

    func restorePositionAfterLoadingEarlier(
        using proxy: ScrollViewProxy,
        projection: CoachMessageRenderProjection
    ) {
        guard isLoadingEarlier,
              let anchor = paginationAnchorMessageID,
              projection.messages.first?.id != anchor
        else {
            return
        }
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            proxy.scrollTo(anchor, anchor: .top)
            await Task.yield()
            guard !Task.isCancelled else { return }
            paginationAnchorMessageID = nil
            isLoadingEarlier = false
            paginationTriggerID = UUID()
        }
    }
}
