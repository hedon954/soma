import Observation
import OSLog
import SwiftData
import SwiftUI
import UIKit

extension CoachSessionView {
    func submitQuestionAnswer(
        _ message: CoachMessage,
        questionID: String,
        optionID: String?,
        text: String?
    ) throws -> Bool {
        guard !composer.isPersistingSubmission,
              let sessionID = conversationSessions.activeSessionID,
              let context = ConversationProcessingContextFactory.make(
                  sessionID: sessionID, dataSpace: dataSpace.activeSpace, ai: ai, in: modelContext
              )
        else { return false }
        visibility.tailScroll.followState.resumeExplicitly()
        let accepted = try processor.submitQuestionAnswer(
            from: message, questionID: questionID, optionID: optionID, customText: text,
            context: context, locationService: locationContext, includeLocation: locationPreference == .enabled
        )
        if accepted {
            scrollRequest = UUID()
        }
        return accepted
    }

    func submitComposedAnswer(_ text: String) throws -> Bool {
        guard !composer.isPersistingSubmission,
              let sessionID = conversationSessions.activeSessionID,
              let context = ConversationProcessingContextFactory.make(
                  sessionID: sessionID, dataSpace: dataSpace.activeSpace, ai: ai, in: modelContext
              )
        else { return false }
        visibility.tailScroll.followState.resumeExplicitly()
        let accepted = processor.submitPersisted(
            text: text,
            attachments: [],
            context: context,
            includeLocation: locationPreference == .enabled,
            locationService: locationContext,
            selectedShortcutID: nil,
            forceLocal: false
        )
        if accepted {
            scrollRequest = UUID()
        }
        return accepted
    }

    func consumeCoachSendIfNeeded() {
        guard let text = CoachComposerCommand.pendingSend,
              [ScheduleDraftAnswerText.opening, CoachComposerCommand.energyContextOpening].contains(text) else { return }
        guard !composer.isPersistingSubmission else { return }
        if text == CoachComposerCommand.energyContextOpening {
            composer.selectedShortcutID = nil
        }
        CoachComposerCommand.pendingSend = nil
        sendCoachOpeningRequest(text)
    }

    func sendScheduleDraftRequest() {
        sendCoachOpeningRequest(ScheduleDraftAnswerText.opening)
    }

    private func sendCoachOpeningRequest(_ text: String) {
        guard !composer.isPersistingSubmission else { return }
        visibility.tailScroll.followState.resumeExplicitly()
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
            CoachComposerCommand.pendingSend = text
            return
        }
        let needsGuidance = needsConfigurationGuidance(forceLocal: false)
        composer.isPersistingSubmission = true
        Task { @MainActor in
            let accepted = await processor.submitAsync(
                text: text,
                attachments: [],
                context: processingContext,
                includeLocation: locationPreference == .enabled,
                locationService: locationContext,
                selectedShortcutID: nil,
                forceLocal: false
            )
            composer.isPersistingSubmission = false
            if accepted {
                visibility.tailScroll.followState.resumeExplicitly()
                scrollRequest = UUID()
                if needsGuidance {
                    openLLMConfiguration()
                }
            } else {
                CoachComposerCommand.pendingSend = text
            }
        }
    }

    func submitCurrentDraft(
        quickRecordOverride: ExerciseInputSuggestion? = nil
    ) {
        guard !composer.isPersistingSubmission else { return }
        if composer.speechInput?.isListening == true {
            composer.isPersistingSubmission = true
            let activeSessionID = conversationSessions.activeSessionID
            Task { @MainActor in
                await composer.finishVoice()
                composer.isPersistingSubmission = false
                guard conversationSessions.activeSessionID == activeSessionID else { return }
                submitCurrentDraft(quickRecordOverride: quickRecordOverride)
            }
            return
        }
        composer.stopVoice()
        let text = composer.trimmedDraft
        guard !text.isEmpty || !composer.attachments.isEmpty else { return }
        // “发送”本身就是显式回到底部的用户意图。必须在异步落盘之前恢复
        // follow，避免 SwiftData 先发布新增消息、而旧的暂停状态漏掉这次 append。
        visibility.tailScroll.followState.resumeExplicitly()
        composer.stopVoice()
        let pending = composer.attachments
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
        let quickRecord = quickRecordOverride ?? composer.selectedExerciseSuggestion
        let exactQuickDraft = pending.isEmpty
            && quickRecord?.draftText == text
            ? quickRecord?.recordDraft
            : nil
        // 精确的结构化快捷记录不经过 LLM，即使尚未配置 API Key 也不应打断发送。
        // 其他路径仍要在落盘前判断：提交后暂存计数会从 0 变成 1。
        let needsConfigurationGuidance = exactQuickDraft == nil
            && needsConfigurationGuidance(
                forceLocal: composer.useLocalForNextMessage
            )
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
        composer.isPersistingSubmission = true
        Task { @MainActor in
            let accepted = await processor.submitAsync(
                text: text,
                attachments: pending,
                context: processingContext,
                includeLocation: locationPreference == .enabled,
                locationService: locationContext,
                selectedShortcutID: composer.selectedShortcutID,
                forceLocal: composer.useLocalForNextMessage
            )
            composer.isPersistingSubmission = false
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
        visibility.tailScroll.followState.resumeExplicitly()
        composer.clearAfterSubmission()
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

    func interruptCurrentProcessing() {
        guard let sessionID = processor.sessionID,
              let processingContext = ConversationProcessingContextFactory.make(
                  sessionID: sessionID,
                  dataSpace: dataSpace.activeSpace,
                  ai: ai,
                  in: modelContext
              )
        else {
            return
        }
        if processor.interruptActiveProcessing(context: processingContext) {
            composer.dismissKeyboard()
            scrollRequest = UUID()
        }
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
            composer.dismissKeyboard()
            scrollRequest = UUID()
            if needsConfigurationGuidance {
                openLLMConfiguration()
            }
        }
    }

    func discardPending(_ message: CoachMessage) {
        guard let turnID = message.turnID else { return }
        let sessionID = message.sessionID ?? conversationSessions.activeSessionID ?? UUID()
        Task {
            do {
                try await discardPending(turnID: turnID, sessionID: sessionID)
            } catch {
                pendingDeletionError = AppErrorMessage.message(for: error, operation: .delete)
            }
        }
    }

    func discardPending(turnID: UUID, sessionID: UUID) async throws {
        guard let processingContext = ConversationProcessingContextFactory.make(
            sessionID: sessionID,
            dataSpace: dataSpace.activeSpace,
            ai: ai,
            in: modelContext
        )
        else {
            throw PendingConversationDeletionError.unavailable
        }
        let protectedPaths = try MediaReferenceStore.referencedPaths(
            in: dataSpace.activeSpace == .personal ? dataSpace.demoContainer : dataSpace.personalContainer
        )
        try await processor.discardPendingTurn(
            turnID: turnID,
            context: processingContext,
            locationService: locationContext,
            protectedMediaPaths: protectedPaths
        )
    }

    func clearPendingQueue() async throws {
        guard let sessionID = conversationSessions.activeSessionID,
              let processingContext = ConversationProcessingContextFactory.make(
                  sessionID: sessionID,
                  dataSpace: dataSpace.activeSpace,
                  ai: ai,
                  in: modelContext
              )
        else {
            throw PendingConversationDeletionError.unavailable
        }
        let protectedPaths = try MediaReferenceStore.referencedPaths(
            in: dataSpace.activeSpace == .personal ? dataSpace.demoContainer : dataSpace.personalContainer
        )
        try await processor.clearPendingQueue(context: processingContext, protectedMediaPaths: protectedPaths)
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
        composer.stopVoice()
        NotificationCenter.default.post(
            name: .coachRequiresAIConfiguration,
            object: nil
        )
    }

    func openLLMConfigurationFromPendingQueue() {
        sheet = nil
        Task { @MainActor in
            await Task.yield()
            openLLMConfiguration()
        }
    }

    func scrollToBottom(
        _ proxy: ScrollViewProxy,
        animated: Bool = true
    ) {
        guard CoachTailScrollPolicy.shouldScroll(
            contentFitsViewport: visibility.tailScroll.contentFitsViewport
                ?? messageListPosition.contentFitsViewport
        ), let target = visibility.tailMessageID
        else {
            return
        }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    /// 与文字投影一致约 5Hz 非动画跟随；结束后再做一次动画归位。
    /// 节流状态放在非 Observation 引用里：每个滚动 tick 不触发整页失效。
    func scheduleLiveScroll(
        _ proxy: ScrollViewProxy,
        targetMessageID: UUID? = nil
    ) {
        guard isProcessingHere else { return }
        guard visibility.tailScroll.followState.isFollowing else { return }
        let performanceInterval = AppPerformance.begin(
            .agentProjection,
            detail: "phase=stream-scroll"
        )
        defer {
            AppPerformance.end(performanceInterval, detail: "phase=stream-scroll")
        }
        let coordinator = visibility.tailScroll
        guard let generation = coordinator.startRequest(replacingExisting: false) else {
            return
        }
        let interval: TimeInterval = 0.2
        let elapsed = Date().timeIntervalSince(coordinator.lastScrollAt)
        let delay = max(interval - elapsed, 0)
        let task = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled,
                  coordinator.owns(generation),
                  isProcessingHere,
                  coordinator.followState.isFollowing
            else {
                coordinator.finish(generation)
                return
            }
            coordinator.lastScrollAt = Date()
            if CoachTailScrollPolicy.shouldScroll(
                contentFitsViewport: coordinator.contentFitsViewport
                    ?? messageListPosition.contentFitsViewport
            ), let targetMessageID {
                proxy.scrollTo(targetMessageID, anchor: .bottom)
            } else {
                scrollToBottom(proxy, animated: false)
            }
            coordinator.finish(generation)
        }
        coordinator.install(task, generation: generation)
    }

    func requestTailScroll(
        _ proxy: ScrollViewProxy,
        targetMessageID: UUID?,
        waitsForLayout: Bool,
        animated: Bool = false
    ) {
        let coordinator = visibility.tailScroll
        guard coordinator.followState.isFollowing,
              let generation = coordinator.startRequest(replacingExisting: true)
        else {
            return
        }
        let task = Task { @MainActor in
            let interval = AppPerformance.begin(
                .coachScrollLayout,
                detail: "phase=tail"
            )
            if waitsForLayout {
                await Task.yield()
            }
            guard !Task.isCancelled, coordinator.owns(generation) else {
                AppPerformance.end(interval, detail: "result=cancelled")
                coordinator.finish(generation)
                return
            }
            if CoachTailScrollPolicy.shouldScroll(
                contentFitsViewport: coordinator.contentFitsViewport
                    ?? messageListPosition.contentFitsViewport
            ), let targetMessageID {
                if animated {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(targetMessageID, anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo(targetMessageID, anchor: .bottom)
                }
            }
            AppPerformance.end(interval, detail: "result=settled")
            coordinator.finish(generation)
        }
        coordinator.install(task, generation: generation)
    }

    func pinOpenedSessionIfNeeded(
        using proxy: ScrollViewProxy,
        projection: CoachMessageRenderProjection
    ) {
        guard !didFinishInitialScroll, !isLoadingEarlier else { return }
        let lastMessageID = projection.messages.last?.id
        visibility.tailMessageID = lastMessageID
        let displayed = displayedMessages(
            from: projection,
            processingHere: isProcessingHere
        )
        let canObserveNearBottom = if #available(iOS 18.0, *) {
            true
        } else {
            false
        }
        let action = CoachOpenedSessionPinPolicy.nextAction(
            CoachOpenedSessionPinSnapshot(
                didPrepareVisiblePage: didPrepareVisiblePage,
                messageCount: projection.messages.count,
                lastMessageIsDisplayed: lastMessageID.map { id in
                    displayed.contains { $0.id == id }
                } ?? false,
                contentFitsViewport: visibility.tailScroll.contentFitsViewport
                    ?? messageListPosition.contentFitsViewport,
                isNearBottom: messageListPosition.isNearBottom,
                contentHeight: visibility.tailScroll.contentHeight,
                canObserveNearBottom: canObserveNearBottom
            )
        )
        switch action {
        case .wait:
            return
        case .scrollToLastMessage:
            scrollOpenedSessionToLastMessage(lastMessageID, using: proxy)
            Task { @MainActor in
                await Task.yield()
                guard !didFinishInitialScroll, !isLoadingEarlier else { return }
                scrollOpenedSessionToLastMessage(lastMessageID, using: proxy)
            }
        case .scrollToLastMessageAndFinish:
            scrollOpenedSessionToLastMessage(lastMessageID, using: proxy)
            finishOpenedSessionPin()
        case .finish:
            finishOpenedSessionPin()
        }
    }

    private func scrollOpenedSessionToLastMessage(
        _ lastMessageID: UUID?,
        using proxy: ScrollViewProxy
    ) {
        guard let lastMessageID else { return }
        visibility.tailScroll.followState.resumeExplicitly()
        proxy.scrollTo(lastMessageID, anchor: .bottom)
    }

    private func finishOpenedSessionPin() {
        if visibility.tailScroll.contentFitsViewport == true {
            visibility.tailScroll.followState.userDidInteract()
        }
        didFinishInitialScroll = true
        paginationTriggerID = UUID()
        if let activeSessionID = conversationSessions.activeSessionID {
            sessionTransition.contentDidBecomeVisible(activeSessionID)
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

    /// iOS 17 的手势回退路径会按拖动帧频调用这里；所有 `@State` 写入都必须
    /// 先做等值判断，避免把一次滚动手势放大成逐帧整页失效。
    func beginMessageHistoryInteraction() {
        if !hasUserInteractedWithMessageList {
            hasUserInteractedWithMessageList = true
        }
        stopFollowingLiveMessage()
    }

    func stopFollowingLiveMessage() {
        visibility.tailScroll.followState.userDidInteract()
        visibility.tailScroll.cancelRequest()
    }

    func restorePositionAfterLoadingEarlier(
        using proxy: ScrollViewProxy,
        projection: CoachMessageRenderProjection
    ) {
        guard isLoadingEarlier,
              pageCacheIsWarm(for: projection),
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

    func pagePaintSignature(for projection: CoachMessageRenderProjection) -> String {
        projection.messages.map { message in
            let live = isProcessingHere && message.agentStatus == .running
            if live {
                return message.id.uuidString
            }
            return "\(message.id.uuidString):\(message.agentTurnItemsData.count)"
        }.joined(separator: "|")
    }

    func displayedMessages(
        from projection: CoachMessageRenderProjection,
        processingHere: Bool
    ) -> [CoachMessage] {
        CoachMessageVisibility.displayed(
            messages: projection.messages,
            didPreparePage: didPrepareVisiblePage,
            processingHere: processingHere
        )
    }

    func schedulePagePaint(
        for projection: CoachMessageRenderProjection,
        key: String,
        onReady: @escaping () -> Void
    ) {
        guard key != pagePaintKey || !didPrepareVisiblePage else { return }
        if pageCacheIsWarm(for: projection) {
            pagePaintKey = key
            markVisiblePagePrepared()
            onReady()
            return
        }
        pagePaintKey = key
        let messages = projection.messages
        let liveID = isProcessingHere ? projection.messages.last?.id : nil
        Task { @MainActor in
            await Task.yield()
            guard pagePaintKey == key else { return }
            ChatRecordCardCache.prefetch(
                CoachMessagePagePaint.references(in: messages),
                in: modelContext
            )
            await CoachMessagePagePaint.warmMarkdown(
                CoachMessagePagePaint.settledMarkdowns(
                    in: messages,
                    liveMessageID: liveID
                )
            )
            guard pagePaintKey == key else { return }
            markVisiblePagePrepared()
            onReady()
        }
    }

    private func markVisiblePagePrepared() {
        if !didPrepareVisiblePage {
            visibility.tailScroll.contentHeight = 0
            messageListPosition = CoachMessageScrollPosition(
                isAtTop: false,
                isNearBottom: false,
                contentFitsViewport: nil
            )
        }
        didPrepareVisiblePage = true
    }

    func pageCacheIsWarm(for projection: CoachMessageRenderProjection) -> Bool {
        let liveID = isProcessingHere ? projection.messages.last?.id : nil
        return ChatRecordCardCache.canRender(
            CoachMessagePagePaint.references(in: projection.messages),
            in: modelContext
        ) && CoachMessagePagePaint.markdownsAreWarm(
            CoachMessagePagePaint.settledMarkdowns(
                in: projection.messages,
                liveMessageID: liveID
            )
        )
    }
}

enum CoachMessageVisibility {
    static func displayed(
        messages: [CoachMessage],
        didPreparePage _: Bool,
        processingHere _: Bool
    ) -> [CoachMessage] {
        messages
    }
}
