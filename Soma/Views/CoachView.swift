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

struct CoachSessionPage: View {
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

struct CoachSessionView: View {
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

