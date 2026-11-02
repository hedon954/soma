import Observation
import OSLog
import SwiftData
import SwiftUI
import UIKit

/// Tab 激活态不作为入参逐层下发：那会让每次 Tab 切换都重算整棵教练子树。
/// 需要激活态的叶子自行读取 `\.coachTabIsActive` 环境值。
struct CoachView: View {
    @Environment(DataSpaceController.self) private var dataSpace
    @Environment(ConversationSessionController.self) private var conversationSessions
    @Environment(\.modelContext) private var historyContext
    @State private var sessionHistory = ConversationSessionHistory()
    @State private var sessionTransition = CoachSessionTransitionCoordinator()

    var body: some View {
        CoachSessionPage(
            sessionID: conversationSessions.activeSessionID,
            dataSpace: dataSpace.activeSpace,
            sessionTransition: sessionTransition
        )
        // Session 身份变化时在查询创建前同步回到 30 条，不能先拿上一条
        // Session 的分页上限构造一次重视图，再在 onChange 里补救。
        .id(conversationSessions.activeSessionID)
        .environment(sessionHistory)
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
            sessionHistory.applySave(notification, in: historyContext)
        }
    }
}

struct CoachSessionPage: View {
    let sessionID: UUID?
    let dataSpace: DataSpace
    let sessionTransition: CoachSessionTransitionCoordinator

    @State private var messageLimit = CoachMessagePagePolicy.pageSize

    var body: some View {
        CoachSessionView(
            sessionID: sessionID,
            dataSpace: dataSpace,
            messageLimit: messageLimit,
            sessionTransition: sessionTransition,
            onLoadEarlier: {
                messageLimit = CoachMessagePagePolicy.nextLimit(after: messageLimit)
            }
        )
    }
}

struct CoachSessionView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(AIService.self) var ai
    @Environment(DataSpaceController.self) var dataSpace
    @Environment(ConversationProcessingService.self) var processor
    @Environment(ConversationSessionController.self) var conversationSessions
    @Environment(SomaCaptureRouter.self) private var captureRouter
    @Environment(LocationContextService.self) var locationContext
    @AppStorage(ConversationLocationPreference.defaultsKey)
    private var locationPreferenceRaw = ConversationLocationPreference.unasked.rawValue
    @AppStorage(RemoteAgentPreference.enabledKey)
    private var remoteExecutionEnabled = false

    @Query private var recentMessages: [CoachMessage]
    @Query private var gyms: [GymProfile]
    @Query private var agentJobs: [AgentJob]

    /// 输入区状态只在事件回调里读写；body 不读取任何字段，
    /// 打字与听写因此只重渲染 `CoachComposer` 子树。
    @State var composer = CoachComposerState()
    @State var sheet: CoachSheet?
    @State private var showsGyms = false
    @State var scrollRequest = UUID()
    @State private var sessionDrawerPresented = false
    @State private var showsSessionDeleteBlockedAlert = false
    @State var pendingDeletionError: String?

    private var pendingDeletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletionError != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletionError = nil
                }
            }
        )
    }

    @State private var showsLocationPrompt = false
    /// 标准配置由 Store 缓存；设置保存时通过通知精确刷新，不再在每次 Tab
    /// 重新挂载时重复解码 UserDefaults JSON。
    @State private var inputShortcuts: [AgentInputShortcut] = []
    @State private var suggestionSnapshot = CoachSuggestionSnapshot.empty
    @State private var timelineRecords: [CoachTimelineRecord] = []
    @State private var suggestionDataRevision = 0
    @State private var loadedSuggestionRevision = -1
    @State private var requestedSuggestionRevision: Int?
    /// 显隐、滚底去重与流式滚动节流都在这个非 Observation 引用里：
    /// 5 Hz 的滚动 tick 只改写引用字段，不再让整页 body 失效。
    @State var visibility = CoachVisibilityState()
    @State var didFinishInitialScroll = false
    @State var isLoadingEarlier = false
    @State var paginationAnchorMessageID: UUID?
    @State var paginationTriggerID = UUID()
    @State var hasUserInteractedWithMessageList = false
    @State var didPrepareVisiblePage = false
    @State var pagePaintKey = ""
    @State private var recordSaveToast: String?
    @State var messageListPosition = CoachMessageScrollPosition(
        isAtTop: false,
        isNearBottom: false,
        contentFitsViewport: nil
    )

    let messageLimit: Int
    let sessionTransition: CoachSessionTransitionCoordinator
    let onLoadEarlier: () -> Void

    init(
        sessionID: UUID?,
        dataSpace: DataSpace,
        messageLimit: Int,
        sessionTransition: CoachSessionTransitionCoordinator,
        onLoadEarlier: @escaping () -> Void
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
        // 排除成功终态：暂存计数、暂存标记与可重试判断只依赖未成功的 Job。
        // 成功 Job 随历史无限增长，若参与查询，流式期间每次 Job 保存都会
        // 重新物化 100 行陈旧历史。cancelled/failed 必须保留：可重试集合要
        // 通过它们区分“系统仍会续跑”与“交给用户手动重试”。
        let succeededRaw = AgentJobState.succeeded.rawValue
        var jobDescriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate {
                $0.dataSpaceRaw == dataSpaceRaw && $0.stateRaw != succeededRaw
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        jobDescriptor.fetchLimit = 100
        _agentJobs = Query(jobDescriptor)

        self.messageLimit = messageLimit
        self.sessionTransition = sessionTransition
        self.onLoadEarlier = onLoadEarlier
    }

    var messages: [CoachMessage] {
        Array(recentMessages.prefix(messageLimit).reversed())
    }

    private var currentGym: GymProfile? {
        GymSelection.current(in: gyms)
    }

    private var currentSession: ConversationSession? {
        conversationSessions.activeSessionReference
    }

    var isProcessingHere: Bool {
        processor.isProcessing
            && processor.dataSpace == dataSpace.activeSpace
            && processor.sessionID == conversationSessions.activeSessionID
    }

    var locationPreference: ConversationLocationPreference {
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

    var pendingJobCount: Int {
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
        .alert("未能删除暂存消息", isPresented: pendingDeletionPresented) {
            Button("知道了", role: .cancel) { pendingDeletionError = nil }
        } message: {
            Text(pendingDeletionError ?? "请重新打开暂存管理后重试。")
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
        .sheet(item: $sheet) { destination in
            switch destination {
            case .media:
                MediaSourceDialog(
                    allowsVideo: true,
                    selectionLimit: max(
                        MediaPicker.maximumSelectionCount - composer.attachments.count,
                        1
                    )
                ) { media in
                    composer.appendPickedMedia(media)
                }
            case .pendingQueue:
                PendingAgentQueueView(
                    jobs: pendingJobs,
                    isBusy: processor.isProcessing,
                    onRetryAll: retryPendingQueue,
                    onDelete: { job in
                        try await discardPending(
                            turnID: job.turnID,
                            sessionID: job.sessionID
                        )
                    },
                    onClear: clearPendingQueue,
                    onOpenLLMConfiguration: openLLMConfigurationFromPendingQueue
                )
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .prefillCoachDraft)
        ) { notification in
            guard let text = notification.object as? String else { return }
            composer.draft = text
            composer.requestFocus()
        }
        .modifier(CoachScheduleDraftSendModifier(onSend: consumeCoachSendIfNeeded))
        .onReceive(
            NotificationCenter.default.publisher(for: .focusCoachComposer)
        ) { _ in
            composer.requestFocus()
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
            if ModelContextSaveImpact.affectsCoachSuggestions(
                notification,
                in: modelContext
            ) {
                suggestionDataRevision &+= 1
                requestSuggestionSnapshotIfNeeded()
            }
            if ModelContextSaveImpact.affectsCoachTimeline(
                notification,
                in: modelContext
            ) {
                refreshTimelineRecords()
            }
        }
        .onAppear {
            visibility.isVisible = true
            refreshTimelineRecords()
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
        .onDisappear {
            visibility.isVisible = false
            guard let speechInput = composer.speechInput,
                  speechInput.isListening
            else {
                return
            }
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
                .background {
                    // 切换到「教练」Tab 时自动回到最新消息；只有这枚叶子
                    // 因激活态变化重新求值。
                    CoachTabActivationDriver {
                        guard didFinishInitialScroll else { return }
                        scrollRequest = UUID()
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    composer(pendingCount: projection.pendingJobCount)
                }
                .appToast(
                    $recordSaveToast,
                    duration: 2.8,
                    systemImage: "checkmark.circle.fill",
                    tint: AppTheme.success
                )
                .onReceive(NotificationCenter.default.publisher(for: .inlineRecordDidSave)) { _ in
                    recordSaveToast = "已保存"
                }
                .onChange(of: pagePaintSignature(for: projection), initial: true) { _, key in
                    schedulePagePaint(for: projection, key: key) {
                        if isLoadingEarlier {
                            restorePositionAfterLoadingEarlier(
                                using: proxy,
                                projection: projection
                            )
                            return
                        }
                        pinOpenedSessionIfNeeded(
                            using: proxy,
                            projection: projection
                        )
                    }
                }
                .onChange(of: projection.messages.last?.id, initial: true) { _, messageID in
                    guard let messageID else { return }
                    if !didFinishInitialScroll {
                        visibility.tailMessageID = messageID
                        _ = visibility.autoScrollGate.shouldScroll(to: messageID)
                        return
                    }
                    visibility.tailMessageID = projection.latestAssistantMessageID
                        ?? messageID
                    guard visibility.autoScrollGate.shouldScroll(to: messageID), visibility.tailScroll.followState.isFollowing else { return }
                    visibility.tailScroll.enqueueMessage(
                        projection.latestAssistantMessageID ?? messageID
                    )
                }
                .onChange(of: messageListPosition) {
                    pinOpenedSessionIfNeeded(
                        using: proxy,
                        projection: projection
                    )
                }
                .onChange(of: projection.messages.count) { oldCount, newCount in
                    if oldCount == 0, newCount > 0 {
                        didFinishInitialScroll = false
                    }
                    pinOpenedSessionIfNeeded(
                        using: proxy,
                        projection: projection
                    )
                }
                .onChange(of: projection.messages.first?.id) {
                    restorePositionAfterLoadingEarlier(
                        using: proxy,
                        projection: projection
                    )
                }
                .onChange(of: isProcessingHere) { wasProcessing, isProcessing in
                    guard wasProcessing, !isProcessing else { return }
                    visibility.tailScroll.cancelRequest()
                    if visibility.tailScroll.followState.isFollowing {
                        requestTailScroll(
                            proxy,
                            targetMessageID: projection.latestAssistantMessageID
                                ?? projection.messages.last?.id,
                            waitsForLayout: true,
                            animated: true
                        )
                    }
                }
                .onChange(of: scrollRequest) {
                    visibility.tailScroll.followState.resumeExplicitly()
                    requestTailScroll(
                        proxy,
                        targetMessageID: projection.latestAssistantMessageID
                            ?? projection.messages.last?.id,
                        waitsForLayout: true
                    )
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .coachDoubleReselected)
                ) { _ in
                    visibility.tailScroll.followState.resumeExplicitly()
                    guard messageListPosition.contentFitsViewport != true else {
                        return
                    }
                    requestTailScroll(
                        proxy,
                        targetMessageID: projection.latestAssistantMessageID
                            ?? projection.messages.last?.id,
                        waitsForLayout: true
                    )
                }
                .modifier(
                    CoachPerformanceScrollModifier(
                        proxy: proxy,
                        firstMessageID: projection.messages.first?.id,
                        lastMessageID: projection.latestAssistantMessageID
                            ?? projection.messages.last?.id
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
            // 已加载页用即时 VStack：懒栈会在滑动时卸载气泡，丢掉卡片 @State，
            // 再以 1pt 占位重新出现并撑开，内容高度抖动还会把整页 body 打满。
            // 窗口仍由 30 条分页封顶，不在 body 里同步查库。
            VStack(spacing: 14) {
                coachMessageRows(
                    scrollProxy: proxy,
                    projection: projection,
                    processorIsProcessing: processorIsProcessing,
                    processingHere: processingHere
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .frame(maxWidth: AppTheme.readableContentMaxWidth)
            .frame(maxWidth: .infinity)
            .background {
                CoachMessageContentHeightReporter()
            }
        }
        .background {
            CoachMessageViewportHeightReporter()
        }
        .onPreferenceChange(CoachMessageContentHeightPreferenceKey.self) { height in
            let didGrow = visibility.tailScroll.recordContentHeight(height)
            updateLegacyMessageMeasurement()
            if !didFinishInitialScroll {
                pinOpenedSessionIfNeeded(
                    using: proxy,
                    projection: projection
                )
                return
            }
            guard didGrow else { return }
            if let pendingMessageID = visibility.tailScroll.consumePendingMessageID() {
                requestTailScroll(
                    proxy,
                    targetMessageID: pendingMessageID,
                    waitsForLayout: false
                )
            } else if isProcessingHere,
                      visibility.tailScroll.followState.isFollowing
            {
                scheduleLiveScroll(
                    proxy,
                    targetMessageID: projection.latestAssistantMessageID
                        ?? projection.messages.last?.id
                )
            }
        }
        .onPreferenceChange(CoachMessageViewportHeightPreferenceKey.self) { height in
            visibility.tailScroll.recordViewportHeight(height)
            updateLegacyMessageMeasurement()
        }
        .modifier(CoachMessageTopPagingModifier())
        .modifier(CoachMessageScrollTrackingModifier { position in
            if messageListPosition != position {
                messageListPosition = position
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
                ? "count=\(projection.messages.count),"
                + "tail=\(projection.messages.last?.id.uuidString ?? "none"),"
                + "nearBottom=\(messageListPosition.isNearBottom),"
                + "following=\(visibility.tailScroll.followState.isFollowing),"
                + "streaming=\(processingHere)"
                : "")
        )
    }

    private func updateLegacyMessageMeasurement() {
        if #available(iOS 18.0, *) {
            return
        }
        guard let fits = visibility.tailScroll.contentFitsViewport, messageListPosition.contentFitsViewport != fits else { return }
        messageListPosition = CoachMessageScrollPosition(
            isAtTop: messageListPosition.isAtTop,
            isNearBottom: fits ? true : messageListPosition.isNearBottom,
            contentFitsViewport: fits
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
            .accessibilityHint("到顶后会再加载 30 条，也可以点这里加载")
            .disabled(isLoadingEarlier)
            .id(paginationTriggerID)
            .modifier(CoachOlderMessageVisibilityModifier {
                loadEarlierKeepingPosition(
                    using: proxy,
                    projection: projection
                )
            })
        }

        let timeline = CoachTimelineBuilder.build(
            messages: projection.messages.map {
                CoachTimelineMessage(id: $0.id, date: $0.date)
            },
            records: timelineRecords,
            hasEarlierMessages: projection.hasEarlierMessages
        )
        let messagesByID = Dictionary(
            uniqueKeysWithValues: projection.messages.map { ($0.id, $0) }
        )
        let hasExternalRecord = timeline.contains {
            if case .records = $0.payload {
                return true
            }
            return false
        }
        if ConversationStarterPolicy.shouldShow(for: projection.messages),
           !hasExternalRecord
        {
            ConversationStarter(
                suggestions: sessionStarterSuggestions,
                onSelect: sendStarter
            )
        }

        ForEach(timeline) { item in
            timelineRow(
                item,
                messagesByID: messagesByID,
                scrollProxy: proxy,
                projection: projection,
                processorIsProcessing: processorIsProcessing,
                processingHere: processingHere,
                isTail: item.scrollID == timeline.last?.scrollID
            )
        }
    }

    private func composer(pendingCount: Int) -> some View {
        CoachComposer(
            state: composer,
            gyms: gyms,
            currentGym: currentGym,
            suggestionSnapshot: suggestionSnapshot,
            pendingCount: pendingCount,
            showsExecutionChoice: remoteExecutionEnabled
                && RemoteAgentPreference.baseURL() != nil,
            shortcuts: inputShortcuts,
            processorIsSending: processor.isProcessing,
            canInterrupt: isProcessingHere,
            onAddMedia: showMedia,
            onSelectGym: selectGym,
            onManageGyms: { showsGyms = true },
            onManagePending: { sheet = .pendingQueue },
            onSend: send,
            onInterrupt: interruptCurrentProcessing
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
        if let selectedShortcutID = composer.selectedShortcutID,
           !inputShortcuts.contains(where: { $0.id == selectedShortcutID })
        {
            composer.selectedShortcutID = nil
        }
    }

    private func refreshTimelineRecords() {
        guard let session = currentSession else {
            timelineRecords = []
            return
        }
        timelineRecords = CoachTimelineLoader.records(
            on: session.effectiveBusinessDate,
            timeZone: session.businessTimeZone,
            in: modelContext
        )
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
        composer.stopVoice()
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
        guard session.setManualTitle(title) else { return false }
        do {
            try modelContext.save()
            return true
        } catch {
            session.title = previousTitle
            return false
        }
    }

    private func restoreAutomaticTitle(_ session: ConversationSession) -> Bool {
        let previousTitle = session.title
        session.restoreDateTitle()
        do {
            try modelContext.save()
            return true
        } catch {
            session.title = previousTitle
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
        composer.prepareForSessionChange()
        scrollRequest = UUID()
    }

    private func handleMediaDelivery() {
        guard let delivery = captureRouter.mediaDelivery else { return }
        composer.appendPickedMedia(delivery.media)
        captureRouter.clearDelivery(delivery.id)
    }

    private func selectGym(_ gym: GymProfile) {
        StructuredDataStore.activateGym(gym, in: modelContext)
    }

    private func sendPrompt(_ prompt: String) {
        composer.draft = prompt
        send()
    }

    private func sendStarter(_ suggestion: ConversationStarterSuggestion) {
        guard let quickRecord = suggestion.quickRecord else {
            sendPrompt(suggestion.prompt)
            return
        }
        composer.draft = quickRecord.draftText
        composer.selectedExerciseSuggestion = quickRecord
        guard locationPreference != .unasked else {
            composer.stopVoice()
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

    private func send() {
        guard composer.speechInput?.isListening == true || !composer.trimmedDraft.isEmpty || !composer.attachments.isEmpty else {
            return
        }
        guard locationPreference != .unasked else {
            composer.stopVoice()
            showsLocationPrompt = true
            return
        }
        submitCurrentDraft()
    }
}

private struct CoachScheduleDraftSendModifier: ViewModifier {
    let onSend: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .sendCoachMessage)) { _ in
                onSend()
            }
            .onAppear(perform: onSend)
    }
}
