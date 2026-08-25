import Observation
import OSLog
import SwiftData
import SwiftUI
import UIKit

struct CoachView: View {
    @Environment(DataSpaceController.self) private var dataSpace
    @Environment(ConversationSessionController.self) private var conversationSessions
    @State private var sessionTransition = CoachSessionTransitionCoordinator()

    let isTabActive: Bool
    let onRequireAIConfiguration: () -> Void

    init(
        isTabActive: Bool = true,
        onRequireAIConfiguration: @escaping () -> Void = {}
    ) {
        self.isTabActive = isTabActive
        self.onRequireAIConfiguration = onRequireAIConfiguration
    }

    var body: some View {
        CoachSessionPage(
            sessionID: conversationSessions.activeSessionID,
            dataSpace: dataSpace.activeSpace,
            isTabActive: isTabActive,
            sessionTransition: sessionTransition,
            onRequireAIConfiguration: onRequireAIConfiguration
        )
        // Session 身份变化时在查询创建前同步回到 10 条，不能先拿上一条
        // Session 的分页上限构造一次重视图，再在 onChange 里补救。
        .id(conversationSessions.activeSessionID)
    }
}

private struct CoachSessionPage: View {
    let sessionID: UUID?
    let dataSpace: DataSpace
    let isTabActive: Bool
    let sessionTransition: CoachSessionTransitionCoordinator
    let onRequireAIConfiguration: () -> Void

    @State private var messageLimit = CoachMessagePagePolicy.pageSize

    var body: some View {
        CoachSessionView(
            sessionID: sessionID,
            dataSpace: dataSpace,
            messageLimit: messageLimit,
            isTabActive: isTabActive,
            sessionTransition: sessionTransition,
            onLoadEarlier: {
                messageLimit = CoachMessagePagePolicy.nextLimit(after: messageLimit)
            },
            onRequireAIConfiguration: onRequireAIConfiguration
        )
    }
}

private struct CoachSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AIService.self) private var ai
    @Environment(DataSpaceController.self) private var dataSpace
    @Environment(ConversationProcessingService.self) private var processor
    @Environment(ConversationSessionController.self) private var conversationSessions
    @Environment(SomaCaptureRouter.self) private var captureRouter
    @Environment(LocationContextService.self) private var locationContext
    @AppStorage(ConversationLocationPreference.defaultsKey)
    private var locationPreferenceRaw = ConversationLocationPreference.unasked.rawValue
    @AppStorage(RemoteAgentPreference.enabledKey)
    private var remoteExecutionEnabled = false

    @Query private var recentMessages: [CoachMessage]
    @Query private var gyms: [GymProfile]
    @Query private var agentJobs: [AgentJob]

    @State private var draft = ""
    @State private var attachments: [PendingAttachment] = []
    @State private var sheet: CoachSheet?
    /// 语音服务只在用户第一次点麦克风时创建。即使 SwiftUI 丢弃新构造的
    /// View struct，Tab 切换也不会再额外分配一个未使用的服务实例。
    @State private var speechInput: SpeechInputService?
    @State private var draftBeforeSpeech = ""
    @State private var showsGyms = false
    @State private var composerFocusRequest = UUID()
    @State private var composerDismissRequest = UUID()
    @State private var scrollRequest = UUID()
    @State private var sessionDrawerPresented = false
    @State private var showsSessionDeleteBlockedAlert = false
    @State private var showsLocationPrompt = false
    @State private var useLocalForNextMessage = false
    @State private var selectedExerciseSuggestion: ExerciseInputSuggestion?
    @State private var selectedShortcutID: String?
    /// 标准配置由 Store 缓存；设置保存时通过通知精确刷新，不再在每次 Tab
    /// 重新挂载时重复解码 UserDefaults JSON。
    @State private var inputShortcuts: [AgentInputShortcut] = []
    /// 流式期间合并滚动，避免每批文字都同步触发布局和滚动。
    @State private var lastLiveScrollAt = Date.distantPast
    @State private var liveScrollTask: Task<Void, Never>?
    @State private var isPersistingSubmission = false
    @State private var suggestionSnapshot = CoachSuggestionSnapshot.empty
    @State private var suggestionDataRevision = 0
    @State private var loadedSuggestionRevision = -1
    @State private var requestedSuggestionRevision: Int?
    @State private var visibility = CoachVisibilityState()
    @State private var didFinishInitialScroll = false
    @State private var isLoadingEarlier = false
    @State private var paginationAnchorMessageID: UUID?
    @State private var paginationTriggerID = UUID()
    @State private var followsLiveMessage = true
    @State private var hasUserInteractedWithMessageList = false
    @State private var messageListPosition = CoachMessageScrollPosition(
        isAtTop: false,
        isNearBottom: false
    )

    let messageLimit: Int
    let isTabActive: Bool
    let sessionTransition: CoachSessionTransitionCoordinator
    let onLoadEarlier: () -> Void
    let onRequireAIConfiguration: () -> Void

    init(
        sessionID: UUID?,
        dataSpace: DataSpace,
        messageLimit: Int,
        isTabActive: Bool,
        sessionTransition: CoachSessionTransitionCoordinator,
        onLoadEarlier: @escaping () -> Void,
        onRequireAIConfiguration: @escaping () -> Void
    ) {
        let targetSessionID = sessionID ?? UUID()
        var messageDescriptor = FetchDescriptor<CoachMessage>(
            predicate: #Predicate { $0.sessionID == targetSessionID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        messageDescriptor.fetchLimit = messageLimit + 1
        _recentMessages = Query(messageDescriptor)

        var gymDescriptor = FetchDescriptor<GymProfile>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        gymDescriptor.fetchLimit = 100
        _gyms = Query(gymDescriptor)

        let dataSpaceRaw = dataSpace.rawValue
        var jobDescriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate { $0.dataSpaceRaw == dataSpaceRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        jobDescriptor.fetchLimit = 100
        _agentJobs = Query(jobDescriptor)

        self.messageLimit = messageLimit
        self.isTabActive = isTabActive
        self.sessionTransition = sessionTransition
        self.onLoadEarlier = onLoadEarlier
        self.onRequireAIConfiguration = onRequireAIConfiguration
    }

    private var messages: [CoachMessage] {
        Array(recentMessages.prefix(messageLimit).reversed())
    }

    private var currentGym: GymProfile? {
        GymSelection.current(in: gyms)
    }

    private var currentSession: ConversationSession? {
        conversationSessions.activeSessionReference
    }

    private var isProcessingHere: Bool {
        processor.isProcessing
            && processor.dataSpace == dataSpace.activeSpace
            && processor.sessionID == conversationSessions.activeSessionID
    }

    private var locationPreference: ConversationLocationPreference {
        ConversationLocationPreference(rawValue: locationPreferenceRaw) ?? .unasked
    }

    /// ADR 0045：暂存队列按数据空间统计，不区分 Session——
    /// 用户关心的是「还有多少条没被消费」。
    private var pendingJobs: [AgentJob] {
        agentJobs.filter {
            $0.dataSpace == dataSpace.activeSpace
                && [.staged, .waitingForUser, .queued, .waitingForNetwork]
                .contains($0.state)
        }
    }

    private var pendingJobCount: Int {
        pendingJobs.count
    }

    var body: some View {
        ZStack(alignment: .leading) {
            conversationArea

            if sessionDrawerPresented {
                Color.black.opacity(0.16)
                    .contentShape(Rectangle())
                    .onTapGesture { closeSessionDrawer() }
                    .ignoresSafeArea()

                ConversationSessionDrawer(
                    currentSessionID: conversationSessions.activeSessionID,
                    isProcessing: processor.isProcessing,
                    onNewSession: createSession,
                    onSelectSession: selectSession,
                    onRenameSession: renameSession,
                    onRestoreAutomaticTitle: restoreAutomaticTitle,
                    onDeleteSession: deleteSession
                )
                .containerRelativeFrame(.horizontal) { width, _ in
                    min(340, width * 0.84)
                }
                .transition(.move(edge: .leading))
            }
        }
        .clipped()
        .appPageBackground()
        .navigationTitle("Soma")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: openSessionDrawer) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("历史对话")
                .accessibilityHint("打开对话会话列表")
            }
            // PRD 033：记录日期是本次对话的高频上下文，放在标题下方居中，不再占输入区。
            ToolbarItem(placement: .principal) {
                CoachTitleWithBusinessDate(
                    businessDate: currentSession?.effectiveBusinessDate ?? .now,
                    onChangeBusinessDate: changeBusinessDate
                )
            }
        }
        .accessibilityAction(named: "打开历史对话") {
            openSessionDrawer()
        }
        .alert("无法删除对话", isPresented: $showsSessionDeleteBlockedAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("这条对话正在处理或仍有未完成的任务，暂不能删除。")
        }
        .alert("允许随消息记录位置？", isPresented: $showsLocationPrompt) {
            Button("不允许", role: .cancel) {
                locationPreferenceRaw = ConversationLocationPreference.disabled.rawValue
                submitCurrentDraft()
            }
            Button("允许") {
                locationPreferenceRaw = ConversationLocationPreference.enabled.rawValue
                submitCurrentDraft()
            }
        } message: {
            Text("Soma 只在发送消息时获取一次位置，用于识别训练场馆和相关天气；不会持续或后台定位。之后可在设置中更改。")
        }
        .navigationDestination(isPresented: $showsGyms) {
            GymLibraryView()
        }
        .sheet(item: $sheet, onDismiss: clearDismissedCaptureRequest) { destination in
            switch destination {
            case .media:
                MediaSourceDialog(
                    allowsVideo: true,
                    selectionLimit: max(
                        MediaPicker.maximumSelectionCount - attachments.count,
                        1
                    )
                ) { media in
                    let available = max(
                        MediaPicker.maximumSelectionCount - attachments.count,
                        0
                    )
                    attachments.append(
                        contentsOf: media.prefix(available).map(PendingAttachment.init)
                    )
                }
            case .pendingQueue:
                PendingAgentQueueView(
                    jobs: pendingJobs,
                    isBusy: processor.isProcessing,
                    onRetryAll: retryPendingQueue,
                    onDelete: { job in
                        discardPending(
                            turnID: job.turnID,
                            sessionID: job.sessionID
                        )
                    },
                    onClear: clearPendingQueue,
                    onOpenLLMConfiguration: openLLMConfigurationFromPendingQueue
                )
            case let .quickCapture(request):
                MediaSourceDialog(
                    allowsVideo: true,
                    selectionLimit: MediaPicker.maximumSelectionCount,
                    initialSource: request.mode == .camera ? .camera : .library
                ) { media in
                    captureRouter.deliver(media)
                }
            }
        }
        .onChange(of: captureRouter.pendingRequest, initial: true) {
            handleCaptureRequest()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .prefillCoachDraft)
        ) { notification in
            guard let text = notification.object as? String else { return }
            draft = text
            composerFocusRequest = UUID()
        }
        .modifier(CoachPerformanceSessionSelectionModifier(onSelect: selectSession))
        .task(id: captureRouter.mediaDelivery?.id) {
            handleMediaDelivery()
        }
        .task(id: requestedSuggestionRevision) {
            guard let requestedSuggestionRevision else { return }
            await refreshSuggestionSnapshot(
                targetRevision: requestedSuggestionRevision
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: ModelContext.didSave,
                object: modelContext
            )
        ) { notification in
            guard ModelContextSaveImpact.affectsCoachSuggestions(
                notification,
                in: modelContext
            ) else {
                return
            }
            suggestionDataRevision &+= 1
            requestSuggestionSnapshotIfNeeded()
        }
        .onAppear {
            visibility.isVisible = true
        }
        .task {
            // 先让 TabView 提交选中外观；次要快照请求不参与点击当帧。
            await Task.yield()
            guard visibility.isVisible else { return }
            refreshInputShortcuts()
            requestSuggestionSnapshotIfNeeded()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .agentInputShortcutsDidChange)
        ) { _ in
            refreshInputShortcuts()
        }
        .onChange(of: draft) {
            guard let selectedExerciseSuggestion else { return }
            if draft.trimmingCharacters(in: .whitespacesAndNewlines)
                != selectedExerciseSuggestion.draftText
            {
                self.selectedExerciseSuggestion = nil
            }
        }
        .onDisappear {
            visibility.isVisible = false
            guard let speechInput, speechInput.isListening else { return }
            Task { @MainActor in
                // AVAudioSession 停用可能同步等待系统音频服务；先让 Tab 切换提交。
                await Task.yield()
                speechInput.stop()
            }
        }
    }

    private var conversationArea: some View {
        let projection = CoachMessageRenderProjection(
            recentMessages: recentMessages,
            messageLimit: messageLimit,
            agentJobs: agentJobs
        )
        return ScrollViewReader { proxy in
            messageList(scrollProxy: proxy, projection: projection)
                .scrollDismissesKeyboard(.interactively)
                .appPageBackground()
                .safeAreaInset(edge: .bottom) {
                    composer(pendingCount: projection.pendingJobCount)
                }
                .onChange(of: projection.messages.last?.id, initial: true) { _, messageID in
                    guard messageID != nil else { return }
                    if !didFinishInitialScroll {
                        _ = visibility.autoScrollGate.shouldScroll(to: messageID)
                        finishInitialScrollSetup(using: proxy)
                        return
                    }
                    guard visibility.autoScrollGate.shouldScroll(to: messageID) else {
                        return
                    }
                    guard followsLiveMessage else { return }
                    scrollToBottomAfterLayout(proxy)
                }
                .onChange(of: projection.messages.first?.id) {
                    restorePositionAfterLoadingEarlier(
                        using: proxy,
                        projection: projection
                    )
                }
                .onChange(of: processor.isProcessing) { _, isProcessing in
                    if isProcessing {
                        scheduleLiveScroll(proxy)
                    } else {
                        liveScrollTask?.cancel()
                        liveScrollTask = nil
                        if followsLiveMessage {
                            scrollToBottom(proxy)
                        }
                    }
                }
                .onChange(of: scrollRequest) {
                    followsLiveMessage = true
                    scrollToBottomAfterLayout(proxy)
                }
                .onChange(of: speechInput?.transcript) {
                    updateDraftFromSpeech()
                }
                .modifier(
                    CoachPerformanceScrollModifier(
                        proxy: proxy,
                        firstMessageID: projection.messages.first?.id
                    )
                )
        }
    }

    private func messageList(
        scrollProxy proxy: ScrollViewProxy,
        projection: CoachMessageRenderProjection
    ) -> some View {
        let processorIsProcessing = processor.isProcessing
        let processingHere = processorIsProcessing
            && processor.dataSpace == dataSpace.activeSpace
            && processor.sessionID == conversationSessions.activeSessionID
        return ScrollView {
            Group {
                if CoachMessageStackPolicy.usesLazyStack(
                    messageCount: projection.messages.count
                ) {
                    LazyVStack(spacing: 14) {
                        coachMessageRows(
                            scrollProxy: proxy,
                            projection: projection,
                            processorIsProcessing: processorIsProcessing,
                            processingHere: processingHere
                        )
                    }
                } else {
                    VStack(spacing: 14) {
                        coachMessageRows(
                            scrollProxy: proxy,
                            projection: projection,
                            processorIsProcessing: processorIsProcessing,
                            processingHere: processingHere
                        )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: AppTheme.readableContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .modifier(CoachMessageTopPagingModifier())
        .modifier(CoachMessageScrollTrackingModifier { position in
            messageListPosition = position
            if didFinishInitialScroll, !position.isNearBottom {
                stopFollowingLiveMessage()
            }
            guard hasUserInteractedWithMessageList, position.isAtTop else {
                return
            }
            loadEarlierKeepingPosition(
                using: proxy,
                projection: projection
            )
        } onUserInteraction: {
            beginMessageHistoryInteraction()
        })
        .accessibilityIdentifier("coach-message-list")
        .accessibilityValue(
            Text(verbatim: AppTestRuntime.isRunning
                ? "count=\(projection.messages.count)"
                : "")
        )
    }

    @ViewBuilder
    private func coachMessageRows(
        scrollProxy proxy: ScrollViewProxy,
        projection: CoachMessageRenderProjection,
        processorIsProcessing: Bool,
        processingHere: Bool
    ) -> some View {
        if projection.hasEarlierMessages {
            Button {
                beginMessageHistoryInteraction()
                loadEarlierKeepingPosition(
                    using: proxy,
                    projection: projection
                )
            } label: {
                if isLoadingEarlier {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("加载更早的消息")
                }
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.borderless)
            .accessibilityHint("上滑到这里会自动再加载 10 条")
            .disabled(isLoadingEarlier)
            .id(paginationTriggerID)
            .modifier(CoachOlderMessageVisibilityModifier {
                loadEarlierKeepingPosition(
                    using: proxy,
                    projection: projection
                )
            })
        }

        if ConversationStarterPolicy.shouldShow(for: projection.messages) {
            ConversationStarter(
                suggestions: sessionStarterSuggestions,
                onSelect: sendStarter
            )
        }

        ForEach(projection.messages) { message in
            CoachBubble(
                message: message,
                isLatestAssistantMessage: message.id
                    == projection.latestAssistantMessageID,
                isLive: processingHere
                    && message.agentStatus == .running,
                observesLiveText: isTabActive,
                isStaged: message.turnID.map(
                    projection.stagedTurnIDs.contains
                ) ?? false,
                canRetry: !processorIsProcessing
                    && projection.retryableMessageIDs.contains(message.id),
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
                },
                onLiveRevision: { scheduleLiveScroll(proxy) }
            )
            .id(message.id)
        }

        Color.clear.frame(height: 1).id("bottom")
    }

    private func composer(pendingCount: Int) -> some View {
        CoachComposer(
            draft: $draft,
            attachments: $attachments,
            gyms: gyms,
            currentGym: currentGym,
            exerciseSuggestions: exerciseSuggestions,
            pendingCount: pendingCount,
            showsExecutionChoice: remoteExecutionEnabled
                && RemoteAgentPreference.baseURL() != nil,
            useLocalForNextMessage: $useLocalForNextMessage,
            selectedShortcutID: $selectedShortcutID,
            shortcuts: inputShortcuts,
            isSending: processor.isProcessing || isPersistingSubmission,
            isListening: speechInput?.isListening == true,
            speechMessage: speechInput?.errorMessage,
            focusRequest: composerFocusRequest,
            dismissRequest: composerDismissRequest,
            onAddMedia: showMedia,
            onSelectGym: selectGym,
            onManageGyms: { showsGyms = true },
            onApplySuggestion: applySuggestion,
            onManagePending: { sheet = .pendingQueue },
            onToggleVoice: toggleVoice,
            onSend: send
        )
        .frame(maxWidth: AppTheme.readableContentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private func showMedia() {
        sheet = .media
    }

    private func refreshInputShortcuts() {
        let currentShortcuts = AgentInputShortcutStore.visibleShortcuts()
        guard visibility.isVisible else { return }
        if inputShortcuts != currentShortcuts {
            inputShortcuts = currentShortcuts
        }
        if let selectedShortcutID,
           !inputShortcuts.contains(where: { $0.id == selectedShortcutID })
        {
            self.selectedShortcutID = nil
        }
    }

    private func requestSuggestionSnapshotIfNeeded() {
        guard visibility.isVisible,
              loadedSuggestionRevision != suggestionDataRevision,
              requestedSuggestionRevision != suggestionDataRevision
        else {
            return
        }
        requestedSuggestionRevision = suggestionDataRevision
    }

    @MainActor
    private func refreshSuggestionSnapshot(targetRevision: Int) async {
        let interval = AppPerformance.begin(
            .derivedSnapshot,
            detail: "screen=coach,kind=suggestions"
        )
        let container = modelContext.container
        let worker = Task.detached(priority: .utility) {
            let loader = CoachSuggestionSnapshotLoader(modelContainer: container)
            return try await loader.load()
        }
        let payload = try? await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard let payload, !Task.isCancelled else {
            if requestedSuggestionRevision == targetRevision {
                requestedSuggestionRevision = nil
            }
            AppPerformance.end(
                interval,
                detail: "screen=coach,kind=suggestions,cancelled=true"
            )
            return
        }

        suggestionSnapshot = payload
        loadedSuggestionRevision = targetRevision
        AppPerformance.end(interval, detail: "screen=coach,kind=suggestions")
        if suggestionDataRevision != targetRevision {
            requestedSuggestionRevision = nil
            requestSuggestionSnapshotIfNeeded()
        }
    }

    private func changeBusinessDate(_ date: Date) {
        guard let session = currentSession else { return }
        session.setBusinessDate(date, timeZone: .current)
        try? modelContext.save()
    }

    private func openSessionDrawer() {
        speechInput?.stop()
        withAnimation(.snappy(duration: 0.24)) {
            sessionDrawerPresented = true
        }
    }

    private func closeSessionDrawer(animated: Bool = true) {
        if animated {
            withAnimation(.snappy(duration: 0.24)) {
                sessionDrawerPresented = false
            }
        } else {
            sessionDrawerPresented = false
        }
    }

    private func createSession() {
        let session = conversationSessions.createSession(
            dataSpace: dataSpace.activeSpace,
            in: modelContext
        )
        switchToSession(session)
    }

    private func selectSession(_ session: ConversationSession) {
        sessionTransition.begin(
            from: conversationSessions.activeSessionID,
            to: session.id
        )
        conversationSessions.select(
            session,
            dataSpace: dataSpace.activeSpace
        )
        switchToSession(session)
    }

    private func deleteSession(_ session: ConversationSession) {
        let wasCurrent = conversationSessions.activeSessionID == session.id
        do {
            let outcome = try ConversationSessionDeletion.delete(
                session,
                dataSpace: dataSpace.activeSpace,
                processingSessionID: processor.isProcessing
                    ? processor.sessionID
                    : nil,
                controller: conversationSessions,
                in: modelContext
            )
            switch outcome {
            case .deleted:
                if wasCurrent {
                    prepareComposerForSessionChange()
                }
            case .refusedBusy:
                showsSessionDeleteBlockedAlert = true
            case .notFound:
                break
            }
        } catch {
            showsSessionDeleteBlockedAlert = true
        }
    }

    private func renameSession(
        _ session: ConversationSession,
        title: String
    ) -> Bool {
        let previousTitle = session.title
        let previousSourceRaw = session.titleSourceRaw
        guard session.setManualTitle(title) else { return false }
        do {
            try modelContext.save()
            return true
        } catch {
            session.title = previousTitle
            session.titleSourceRaw = previousSourceRaw
            return false
        }
    }

    private func restoreAutomaticTitle(_ session: ConversationSession) -> Bool {
        let previousTitle = session.title
        let previousSourceRaw = session.titleSourceRaw
        let sessionID = session.id
        var descriptor = FetchDescriptor<CoachMessage>(
            predicate: #Predicate {
                $0.sessionID == sessionID && !$0.isFromCoach
            },
            sortBy: [SortDescriptor(\.date)]
        )
        descriptor.fetchLimit = 1
        let fallbackText = ConversationSessionTitleService.fallbackText(
            sessionID: session.id,
            messages: (try? modelContext.fetch(descriptor)) ?? []
        )
        session.restoreAutomaticTitle(from: fallbackText)
        do {
            try modelContext.save()
            processor.titleGenerator.request(
                sessionID: session.id,
                ai: ai,
                modelContext: modelContext
            )
            return true
        } catch {
            session.title = previousTitle
            session.titleSourceRaw = previousSourceRaw
            return false
        }
    }

    private func switchToSession(_: ConversationSession) {
        prepareComposerForSessionChange()
        // Session 内容树不参与抽屉退场动画，避免把两组不同高度的消息、
        // Markdown 和原位记录卡放进同一个动画事务里反复测量。
        closeSessionDrawer(animated: false)
    }

    private func prepareComposerForSessionChange() {
        draft = ""
        attachments = []
        useLocalForNextMessage = false
        speechInput?.stop()
        composerDismissRequest = UUID()
        scrollRequest = UUID()
    }

    private func appendPickedMedia(_ media: [PickedMedia]) {
        let available = max(
            MediaPicker.maximumSelectionCount - attachments.count,
            0
        )
        attachments.append(
            contentsOf: media.prefix(available).map(PendingAttachment.init)
        )
    }

    private func handleCaptureRequest() {
        guard let request = captureRouter.pendingRequest else { return }
        somaCaptureLogger.info(
            "Routing capture request in coach: \(request.mode.rawValue, privacy: .public)"
        )
        if request.mode == .text {
            composerFocusRequest = UUID()
            captureRouter.clear(request.id)
        } else {
            Task { @MainActor in
                await Task.yield()
                guard captureRouter.pendingRequest?.id == request.id else { return }
                sheet = .quickCapture(request)
                somaCaptureLogger.info("Presented quick capture sheet state")
            }
        }
    }

    private func clearDismissedCaptureRequest() {
        somaCaptureLogger.info("Quick capture sheet dismissed")
        guard let request = captureRouter.pendingRequest,
              request.mode != .text
        else {
            return
        }
        captureRouter.clear(request.id)
    }

    private func handleMediaDelivery() {
        guard let delivery = captureRouter.mediaDelivery else { return }
        appendPickedMedia(delivery.media)
        captureRouter.clearDelivery(delivery.id)
    }

    private func selectGym(_ gym: GymProfile) {
        GymSelection.activate(gym, among: gyms)
        try? modelContext.save()
    }

    private func sendPrompt(_ prompt: String) {
        draft = prompt
        send()
    }

    private func sendStarter(_ suggestion: ConversationStarterSuggestion) {
        guard let quickRecord = suggestion.quickRecord else {
            sendPrompt(suggestion.prompt)
            return
        }
        draft = quickRecord.draftText
        selectedExerciseSuggestion = quickRecord
        guard locationPreference != .unasked else {
            speechInput?.stop()
            showsLocationPrompt = true
            return
        }
        submitCurrentDraft(quickRecordOverride: quickRecord)
    }

    private var sessionStarterSuggestions: [ConversationStarterSuggestion] {
        var values: [ConversationStarterSuggestion] = []
        if let currentGym {
            let prompt = "我到\(currentGym.name)了，今天怎么练？"
            values.append(.init(title: prompt, prompt: prompt))
        }
        if let recent = suggestionSnapshot.recentCapacities
            .filter({
                !$0.text.isEmpty && $0.recordDraft?.setEntries.isEmpty == false
            })
            .max(by: { $0.date < $1.date }),
            let exercise = suggestionSnapshot.exercises.first(where: {
                $0.id == recent.exerciseID
            })
        {
            let quickRecord = ExerciseInputSuggestion(
                id: exercise.id,
                exerciseName: exercise.name,
                recentSummary: recent.text,
                recentDate: recent.date,
                recordDraft: recent.recordDraft
            )
            values.append(.init(
                title: "继续记录\(exercise.name)",
                prompt: quickRecord.draftText,
                quickRecord: quickRecord
            ))
        } else if let latestExerciseName = suggestionSnapshot.latestWorkoutExerciseName {
            let prompt = "继续记录\(latestExerciseName)"
            values.append(.init(title: prompt, prompt: prompt))
        }
        let hour = Calendar.current.component(.hour, from: .now)
        let mealPrompt = hour < 11
            ? "记录今天的早餐"
            : hour < 17 ? "记录刚才这顿饭" : "记录今天的晚餐"
        values.append(.init(title: mealPrompt, prompt: mealPrompt))
        return Array(values.prefix(3))
    }

    /// ADR 0046：一行同时给出动作名与最近一次训练容量，点一次即得到完整草稿。
    private var exerciseSuggestions: [ExerciseInputSuggestion] {
        let query = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let suggestions = ExerciseInputSuggestionBuilder.suggestions(
            query: query,
            exercises: suggestionSnapshot.exercises,
            recentCapacities: suggestionSnapshot.recentCapacities
        )
        // 草稿已经等于唯一建议时不再重复提示。
        if suggestions.count == 1, suggestions[0].draftText == query {
            return []
        }
        return suggestions
    }

    private func applySuggestion(_ suggestion: ExerciseInputSuggestion) {
        draft = suggestion.draftText
        selectedExerciseSuggestion = suggestion
        composerFocusRequest = UUID()
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        guard locationPreference != .unasked else {
            speechInput?.stop()
            showsLocationPrompt = true
            return
        }
        submitCurrentDraft()
    }
}

private extension CoachSessionView {
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

    private func finishAcceptedSubmission(
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

    private func retry(_ responseMessage: CoachMessage) {
        guard let turnID = responseMessage.turnID else { return }
        retry(turnID: turnID)
    }

    private func retryPendingQueue() -> Bool {
        processor.retryPendingQueue(
            dataSpace: dataSpace.activeSpace,
            ai: ai,
            modelContext: modelContext,
            locationService: locationContext
        )
    }

    private func retry(turnID: UUID) {
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

    private func discardPending(_ message: CoachMessage) {
        guard let turnID = message.turnID else { return }
        _ = discardPending(
            turnID: turnID,
            sessionID: message.sessionID ?? conversationSessions.activeSessionID ?? UUID()
        )
    }

    private func discardPending(turnID: UUID, sessionID: UUID) -> Bool {
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

    private func clearPendingQueue() -> Bool {
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
    private func needsConfigurationGuidance(forceLocal: Bool) -> Bool {
        if !forceLocal, RemoteAgentPreference.isEnabled() {
            return false
        }
        return !ai.hasRequiredAPIKey && pendingJobCount == 0
    }

    private func openLLMConfiguration() {
        speechInput?.stop()
        onRequireAIConfiguration()
    }

    private func openLLMConfigurationFromPendingQueue() {
        sheet = nil
        Task { @MainActor in
            await Task.yield()
            openLLMConfiguration()
        }
    }

    private func toggleVoice() {
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

    private func updateDraftFromSpeech() {
        guard let speechInput else { return }
        let transcript = speechInput.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        draft = [draftBeforeSpeech, transcript]
            .filter { !$0.isEmpty }
            .joined(separator: draftBeforeSpeech.isEmpty ? "" : " ")
    }

    private func scrollToBottom(
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
    private func scheduleLiveScroll(_ proxy: ScrollViewProxy) {
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

    private func scrollToBottomAfterLayout(
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

    private func finishInitialScrollSetup(using proxy: ScrollViewProxy) {
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

    private func loadEarlierKeepingPosition(
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

    private func beginMessageHistoryInteraction() {
        hasUserInteractedWithMessageList = true
        stopFollowingLiveMessage()
    }

    private func stopFollowingLiveMessage() {
        followsLiveMessage = false
        liveScrollTask?.cancel()
        liveScrollTask = nil
    }

    private func restorePositionAfterLoadingEarlier(
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

private enum AssistantFeedbackScroller {
    static func scrollAfterLayout(
        to target: AssistantFeedbackScrollTarget,
        using proxy: ScrollViewProxy
    ) {
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }
}

private struct ConversationStarterSuggestion {
    let title: String
    let prompt: String
    var quickRecord: ExerciseInputSuggestion?

    init(
        title: String,
        prompt: String,
        quickRecord: ExerciseInputSuggestion? = nil
    ) {
        self.title = title
        self.prompt = prompt
        self.quickRecord = quickRecord
    }
}

enum ConversationStarterPolicy {
    static func shouldShow(for messages: [CoachMessage]) -> Bool {
        messages.isEmpty
    }

    static func customPrompts(from rawValue: String) -> [String] {
        let normalized = rawValue
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return Array(normalized.filter { seen.insert($0).inserted }.suffix(6))
    }

    static func adding(_ value: String, to prompts: [String]) -> [String] {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return prompts }
        return Array((prompts.filter { $0 != normalized } + [normalized]).suffix(6))
    }
}

private struct ConversationStarter: View {
    let suggestions: [ConversationStarterSuggestion]
    let onSelect: (ConversationStarterSuggestion) -> Void
    @AppStorage("coach.customStarterPrompts") private var customPromptsRaw = ""
    @State private var customDraft = ""
    @State private var customizationExpanded = false

    private var customPrompts: [String] {
        ConversationStarterPolicy.customPrompts(from: customPromptsRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("像聊天一样描述训练、饮食或身体变化，Soma 会理解并记录。")
                .font(.title3.weight(.medium))
                .lineSpacing(3)
            VStack(spacing: 8) {
                ForEach(Array(allSuggestions.enumerated()), id: \.offset) { _, suggestion in
                    starter(suggestion)
                }
            }
            DisclosureGroup("自定义快捷语", isExpanded: $customizationExpanded) {
                HStack {
                    TextField("例如：记录晨起体重", text: $customDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("添加", action: addCustomPrompt)
                        .disabled(customDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(customPrompts, id: \.self) { prompt in
                    HStack {
                        Text(prompt).font(.caption).lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            removeCustomPrompt(prompt)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除快捷语 \(prompt)")
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func addCustomPrompt() {
        let value = customDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        customPromptsRaw = ConversationStarterPolicy.adding(value, to: customPrompts)
            .joined(separator: "\n")
        customDraft = ""
    }

    private func removeCustomPrompt(_ prompt: String) {
        customPromptsRaw = customPrompts.filter { $0 != prompt }
            .joined(separator: "\n")
    }

    private var allSuggestions: [ConversationStarterSuggestion] {
        suggestions + customPrompts.map {
            ConversationStarterSuggestion(title: $0, prompt: $0)
        }
    }

    private func starter(_ suggestion: ConversationStarterSuggestion) -> some View {
        Button {
            onSelect(suggestion)
        } label: {
            Text(suggestion.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .somaCardSurface(radius: 14)
        }
        .buttonStyle(.plain)
    }
}

/// PRD 033：导航栏标题区的两行结构：上面是 App 名，下面是当前 Session 的记录日期入口。
private struct CoachTitleWithBusinessDate: View {
    let businessDate: Date
    let onChangeBusinessDate: (Date) -> Void
    @State private var showsPicker = false
    @State private var pendingDate = Date.now

    var body: some View {
        VStack(spacing: 1) {
            Text("Soma")
                .font(.headline.weight(.medium))
            Button {
                pendingDate = businessDate
                showsPicker = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                    Text(businessDate.formatted(.dateTime.month().day()))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("本次对话的记录日期")
            .accessibilityValue(
                businessDate.formatted(date: .long, time: .omitted)
            )
            .accessibilityHint("更改后，本次对话新增的记录默认使用这个日期")
        }
        .sheet(isPresented: $showsPicker) {
            NavigationStack {
                DatePicker(
                    "Session 日期",
                    selection: $pendingDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("默认记录日期")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showsPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            onChangeBusinessDate(pendingDate)
                            showsPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

private struct CoachComposer: View {
    @Binding var draft: String
    @Binding var attachments: [PendingAttachment]
    let gyms: [GymProfile]
    let currentGym: GymProfile?
    let exerciseSuggestions: [ExerciseInputSuggestion]
    let pendingCount: Int
    let showsExecutionChoice: Bool
    @Binding var useLocalForNextMessage: Bool
    @Binding var selectedShortcutID: String?
    let shortcuts: [AgentInputShortcut]
    let isSending: Bool
    let isListening: Bool
    let speechMessage: String?
    let focusRequest: UUID
    let dismissRequest: UUID
    let onAddMedia: () -> Void
    let onSelectGym: (GymProfile) -> Void
    let onManageGyms: () -> Void
    let onApplySuggestion: (ExerciseInputSuggestion) -> Void
    let onManagePending: () -> Void
    let onToggleVoice: () -> Void
    let onSend: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focused: Bool

    /// PRD 020：输入区同一时间最多一层内容上下文条，附件预览优先于动作建议。
    /// PRD 037：场馆切换与快捷按钮同属发送前控制，固定在同一个横向滚动行。
    private enum ContextStrip {
        case attachments, suggestions
    }

    private var contextStrip: ContextStrip? {
        if !attachments.isEmpty {
            return .attachments
        }
        if !exerciseSuggestions.isEmpty {
            return .suggestions
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 8) {
            composerContextControls

            // ADR 0045：暂存计数常驻在输入区上方，与上下文条互不挤占。
            if pendingCount > 0 {
                PendingQueueBanner(
                    count: pendingCount,
                    onManage: onManagePending
                )
            }

            switch contextStrip {
            case .attachments:
                AttachmentPreview(
                    attachments: attachments,
                    onRemove: { id in
                        attachments.removeAll { $0.id == id }
                    }
                )
            case .suggestions:
                InputSuggestionList(
                    items: exerciseSuggestions.map(Self.suggestionItem),
                    selectionHint: "把动作与最近一次训练数据填入输入框"
                ) { item in
                    guard let suggestion = exerciseSuggestions.first(where: {
                        $0.id.uuidString == item.id
                    }) else {
                        return
                    }
                    onApplySuggestion(suggestion)
                }
            case nil:
                EmptyView()
            }

            if isListening {
                Label("正在听写…", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            } else if let speechMessage {
                Text(speechMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    composerTextField
                    HStack(spacing: 12) {
                        addMediaButton
                        Spacer(minLength: 8)
                        voiceButton
                        sendControl
                    }
                    .padding(.horizontal, 6)
                }
            } else {
                HStack(alignment: .bottom, spacing: 9) {
                    addMediaButton
                    composerTextField
                    voiceButton
                    sendControl
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.pageBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.separator)
                .frame(height: 0.5)
        }
        .onChange(of: focusRequest) {
            focused = true
        }
        .onChange(of: dismissRequest) {
            focused = false
        }
        .onChange(of: isSending) {
            if isSending {
                focused = false
            }
        }
    }

    /// PRD 033 / 037：可见快捷按钮与多场馆切换在一个水平行内，窄屏只滚动不换行。
    private var composerContextControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shortcuts) { shortcut in
                    let isSelected = selectedShortcutID == shortcut.id
                    Button {
                        selectedShortcutID = isSelected ? nil : shortcut.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: shortcut.iconSystemName)
                                .foregroundStyle(
                                    isSelected
                                        ? AppTheme.onAccent
                                        : shortcutColor(shortcut)
                                )
                            Text(shortcut.title)
                                .foregroundStyle(
                                    isSelected ? AppTheme.onAccent : Color.secondary
                                )
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isSelected
                                ? AppTheme.accentEmphasis
                                : AppTheme.insetBackground,
                            in: Capsule()
                        )
                        .frame(minHeight: AppTheme.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("快捷按钮：\(shortcut.title)")
                    .accessibilityValue(isSelected ? "已选择" : "未选择")
                }
                if gyms.count >= 2 {
                    gymStrip
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var gymStrip: some View {
        Menu {
            ForEach(gyms) { gym in
                Button {
                    onSelectGym(gym)
                } label: {
                    if gym.id == currentGym?.id {
                        Label(gym.name, systemImage: "checkmark")
                    } else {
                        Text(gym.name)
                    }
                }
            }

            Divider()

            Button {
                onManageGyms()
            } label: {
                Label("管理健身房…", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(currentGym?.name ?? "选择健身房")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                AppTheme.insetBackground,
                in: Capsule()
            )
            .frame(minHeight: AppTheme.minimumTapTarget)
        }
        .accessibilityLabel("当前健身房 \(currentGym?.name ?? "未选择")，点击切换")
    }

    private var addMediaButton: some View {
        Button(action: onAddMedia) {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(AppTheme.insetBackground, in: Circle())
                .frame(
                    width: AppTheme.minimumTapTarget,
                    height: AppTheme.minimumTapTarget
                )
        }
        .disabled(attachments.count >= MediaPicker.maximumSelectionCount)
        .accessibilityLabel("添加照片或视频，可多选")
    }

    private var composerTextField: some View {
        TextField("说点什么，或添加照片与视频…", text: $draft, axis: .vertical)
            .lineLimit(1 ... 5)
            .focused($focused)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .frame(minHeight: AppTheme.minimumTapTarget)
            .background(
                AppTheme.insetBackground,
                in: RoundedRectangle(cornerRadius: 19)
            )
    }

    private var voiceButton: some View {
        Button(action: onToggleVoice) {
            Image(systemName: isListening ? "waveform" : "mic.fill")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(isListening ? AppTheme.onAccent : AppTheme.tint)
                .background(
                    isListening ? AppTheme.accentEmphasis : AppTheme.insetBackground,
                    in: Circle()
                )
                .frame(
                    width: AppTheme.minimumTapTarget,
                    height: AppTheme.minimumTapTarget
                )
        }
        .disabled(isSending)
        .accessibilityLabel(isListening ? "停止语音输入" : "开始语音输入")
    }

    private static func suggestionItem(
        _ suggestion: ExerciseInputSuggestion
    ) -> InputSuggestionItem {
        InputSuggestionItem(
            id: suggestion.id.uuidString,
            title: suggestion.draftText,
            detail: suggestion.recentDate.map {
                "上次 " + $0.formatted(date: .abbreviated, time: .omitted)
            },
            icon: "figure.strengthtraining.traditional"
        )
    }

    /// ADR 0045：任务在途时仍可继续发送，队列按 FIFO 消费。
    private var sendDisabled: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attachments.isEmpty
    }

    private var sendLabel: some View {
        let foreground = useLocalForNextMessage ? Color.white : AppTheme.onAccent
        return Group {
            if isSending {
                ProgressView().tint(foreground)
            } else {
                Image(systemName: useLocalForNextMessage ? "iphone" : "arrow.up")
                    .fontWeight(.bold)
            }
        }
        .frame(width: 40, height: 40)
        .foregroundStyle(foreground)
        .background(
            useLocalForNextMessage ? AppTheme.warningEmphasis : AppTheme.accentEmphasis,
            in: Circle()
        )
        .frame(
            width: AppTheme.minimumTapTarget,
            height: AppTheme.minimumTapTarget
        )
    }

    private func shortcutColor(_ shortcut: AgentInputShortcut) -> Color {
        switch shortcut.id {
        case "shortcut_nutrition":
            AppTheme.mealAccent
        case "shortcut_workout_log":
            AppTheme.trainingAccent
        case "shortcut_recent_review":
            AppTheme.trendAccent
        default:
            AppTheme.tint
        }
    }

    /// PRD 020：远程执行方式不再常驻输入区，改为发送按钮长按菜单按条覆盖。
    @ViewBuilder
    private var sendControl: some View {
        if showsExecutionChoice {
            Menu {
                Toggle(isOn: $useLocalForNextMessage) {
                    Label("本次仅本机", systemImage: "iphone")
                }
                .appToggleStyle()
            } label: {
                sendLabel
            } primaryAction: {
                onSend()
            }
            .disabled(sendDisabled)
            .accessibilityLabel(
                useLocalForNextMessage ? "发送，本次仅本机" : "发送"
            )
            .accessibilityHint("长按选择这条消息是仅在本机执行还是可后台继续")
        } else {
            Button(action: onSend) {
                sendLabel
            }
            .disabled(sendDisabled)
            .accessibilityLabel("发送")
        }
    }
}

/// ADR 0062：输入区只保留计数入口，完整队列操作进入可审查的管理列表。
private struct PendingQueueBanner: View {
    let count: Int
    let onManage: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .font(.footnote)
                .foregroundStyle(AppTheme.warning)
            Text("\(count) 条待处理，按发送顺序等待")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onManage) {
                Text("管理")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tint)
            }
            .accessibilityHint("查看暂存列表并重试或删除")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            AppTheme.warning.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) 条消息待处理，按发送顺序等待")
    }
}

private struct AttachmentPreview: View {
    let attachments: [PendingAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let data = attachment.imageData {
                                PendingImagePreview(id: attachment.id, data: data)
                            } else {
                                ZStack {
                                    Color.black.opacity(0.82)
                                    Image(systemName: "play.fill").foregroundStyle(.white)
                                }
                            }
                        }
                        .frame(width: 64, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 11))

                        Button {
                            onRemove(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.65))
                        }
                        .offset(x: 5, y: -5)
                        .accessibilityLabel(
                            attachment.kind == .video ? "移除视频" : "移除图片"
                        )
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
