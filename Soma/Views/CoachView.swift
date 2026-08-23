import Observation
import OSLog
import SwiftData
import SwiftUI
import UIKit

private enum CoachSheet: Identifiable {
    case media
    case pendingQueue
    case quickCapture(CaptureEntryRequest)

    var id: String {
        switch self {
        case .media:
            "media"
        case .pendingQueue:
            "pending-queue"
        case let .quickCapture(request):
            "capture-\(request.id)"
        }
    }
}

struct CoachView: View {
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

    @Query(sort: \CoachMessage.date) private var allMessages: [CoachMessage]
    @Query(sort: \GymProfile.createdAt) private var gyms: [GymProfile]
    @Query(sort: \GymEquipment.createdAt) private var equipment: [GymEquipment]
    @Query(sort: \ExerciseDefinition.canonicalName)
    private var exerciseDefinitions: [ExerciseDefinition]
    @Query(sort: \WorkoutEntry.date, order: .reverse)
    private var workouts: [WorkoutEntry]
    @Query(sort: \ExercisePerformance.order)
    private var exercisePerformances: [ExercisePerformance]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var workoutSessions: [WorkoutSession]
    @Query(sort: \WorkoutSet.order)
    private var workoutSets: [WorkoutSet]
    @Query(sort: \AgentJob.createdAt) private var agentJobs: [AgentJob]

    @State private var draft = ""
    @State private var attachments: [PendingAttachment] = []
    @State private var sheet: CoachSheet?
    @State private var speechInput = SpeechInputService()
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
    /// 设置页可能在返回聊天前改动快捷按钮，这里在出现时重新读一次。
    @State private var inputShortcuts = AgentInputShortcutStore.visibleShortcuts()
    /// 流式期间合并滚动，避免每个 token 启动一次 250ms 动画反压 MainActor。
    @State private var lastLiveScrollAt = Date.distantPast
    @State private var liveScrollTask: Task<Void, Never>?

    let onRequireAIConfiguration: () -> Void

    init(onRequireAIConfiguration: @escaping () -> Void = {}) {
        self.onRequireAIConfiguration = onRequireAIConfiguration
    }

    private var messages: [CoachMessage] {
        guard let activeSessionID = conversationSessions.activeSessionID else {
            return []
        }
        return allMessages.filter { $0.sessionID == activeSessionID }
    }

    private var latestAssistantMessageID: UUID? {
        ChatRecordEditPolicy.latestEditableAssistantMessageID(in: messages)
    }

    private var currentGym: GymProfile? {
        GymSelection.current(in: gyms)
    }

    private var currentSession: ConversationSession? {
        conversationSessions.activeSession(in: modelContext)
    }

    private var locationPreference: ConversationLocationPreference {
        ConversationLocationPreference(rawValue: locationPreferenceRaw) ?? .unasked
    }

    private var isProcessingHere: Bool {
        processor.isProcessing
            && processor.dataSpace == dataSpace.activeSpace
            && processor.sessionID == conversationSessions.activeSessionID
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

    private var stagedTurnIDs: Set<UUID> {
        Set(
            agentJobs
                .filter {
                    $0.dataSpace == dataSpace.activeSpace && $0.state == .staged
                        || $0.dataSpace == dataSpace.activeSpace
                        && $0.state == .waitingForUser
                }
                .map(\.turnID)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = min(340, geometry.size.width * 0.84)
            ZStack(alignment: .leading) {
                conversationArea
                    .offset(x: sessionDrawerPresented ? drawerWidth : 0)

                if sessionDrawerPresented {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: drawerWidth)
                            .allowsHitTesting(false)
                        Color.black.opacity(0.16)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: closeSessionDrawer)
                    }
                    .ignoresSafeArea()
                }

                ConversationSessionDrawer(
                    currentSessionID: conversationSessions.activeSessionID,
                    isProcessing: processor.isProcessing,
                    onNewSession: createSession,
                    onSelectSession: selectSession,
                    onRenameSession: renameSession,
                    onRestoreAutomaticTitle: restoreAutomaticTitle,
                    onDeleteSession: deleteSession
                )
                .frame(width: drawerWidth)
                .offset(x: sessionDrawerPresented ? 0 : -drawerWidth)
            }
            .clipped()
            .animation(.snappy(duration: 0.24), value: sessionDrawerPresented)
            .simultaneousGesture(sessionDrawerGesture(drawerWidth: drawerWidth))
        }
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
        .task(id: captureRouter.mediaDelivery?.id) {
            handleMediaDelivery()
        }
        .onAppear {
            locationPreferenceRaw = ConversationLocationPreference.current().rawValue
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
            speechInput.stop()
        }
    }

    private var conversationArea: some View {
        ScrollViewReader { proxy in
            messageList
                .scrollDismissesKeyboard(.interactively)
                .appPageBackground()
                .safeAreaInset(edge: .bottom) {
                    composer
                }
                .onChange(of: messages.last?.id, initial: true) {
                    scrollToBottomAfterLayout(proxy)
                }
                .onChange(of: processor.isProcessing) { _, isProcessing in
                    if isProcessing {
                        scheduleLiveScroll(proxy)
                    } else {
                        liveScrollTask?.cancel()
                        liveScrollTask = nil
                        scrollToBottom(proxy)
                    }
                }
                .onChange(of: processor.liveAssistantText) {
                    scheduleLiveScroll(proxy)
                }
                .onChange(of: processor.liveAgentActivity) {
                    scheduleLiveScroll(proxy)
                }
                .onChange(of: processor.liveEventRevision) {
                    scheduleLiveScroll(proxy)
                }
                .onChange(of: scrollRequest) {
                    scrollToBottomAfterLayout(proxy)
                }
                .onChange(of: speechInput.transcript) {
                    updateDraftFromSpeech()
                }
        }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if ConversationStarterPolicy.shouldShow(for: messages) {
                    ConversationStarter(
                        suggestions: sessionStarterSuggestions,
                        onSelect: sendStarter
                    )
                }

                ForEach(messages) { message in
                    CoachBubble(
                        message: message,
                        isLatestAssistantMessage: message.id == latestAssistantMessageID,
                        isLive: isProcessingHere
                            && message.agentStatus == .running,
                        isStaged: message.turnID.map(stagedTurnIDs.contains) ?? false,
                        canRetry: !processor.isProcessing
                            && ConversationTurnProjection.canRetry(
                                message,
                                in: messages,
                                job: agentJobs.last { $0.responseMessageID == message.id }
                            ),
                        onRetry: { retry(message) },
                        onDiscardPending: message.turnID.map(stagedTurnIDs.contains) == true
                            ? { discardPending(message) }
                            : nil
                    )
                    .id(message.id)
                }

                Color.clear.frame(height: 1).id("bottom")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: AppTheme.readableContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private var composer: some View {
        CoachComposer(
            draft: $draft,
            attachments: $attachments,
            gyms: gyms,
            currentGym: currentGym,
            exerciseSuggestions: exerciseSuggestions,
            pendingCount: pendingJobCount,
            showsExecutionChoice: remoteExecutionEnabled
                && RemoteAgentPreference.baseURL() != nil,
            useLocalForNextMessage: $useLocalForNextMessage,
            selectedShortcutID: $selectedShortcutID,
            shortcuts: inputShortcuts,
            isSending: processor.isProcessing,
            isListening: speechInput.isListening,
            speechMessage: speechInput.errorMessage,
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
        inputShortcuts = AgentInputShortcutStore.visibleShortcuts()
        if let selectedShortcutID,
           !inputShortcuts.contains(where: { $0.id == selectedShortcutID })
        {
            self.selectedShortcutID = nil
        }
    }

    private func changeBusinessDate(_ date: Date) {
        guard let session = currentSession else { return }
        session.setBusinessDate(date, timeZone: .current)
        try? modelContext.save()
    }

    private func sessionDrawerGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .global)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) else {
                    return
                }
                if sessionDrawerPresented,
                   horizontal < -60,
                   value.startLocation.x > drawerWidth
                {
                    closeSessionDrawer()
                } else if !sessionDrawerPresented,
                          value.startLocation.x <= 28,
                          horizontal > 60
                {
                    openSessionDrawer()
                }
            }
    }

    private func openSessionDrawer() {
        speechInput.stop()
        sessionDrawerPresented = true
    }

    private func closeSessionDrawer() {
        sessionDrawerPresented = false
    }

    private func createSession() {
        let session = conversationSessions.createSession(
            dataSpace: dataSpace.activeSpace,
            in: modelContext
        )
        switchToSession(session)
    }

    private func selectSession(_ session: ConversationSession) {
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
        let fallbackText = ConversationSessionTitleService.fallbackText(
            sessionID: session.id,
            messages: allMessages
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
        closeSessionDrawer()
    }

    private func prepareComposerForSessionChange() {
        draft = ""
        attachments = []
        useLocalForNextMessage = false
        speechInput.stop()
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
            speechInput.stop()
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
        if let recent = recentExerciseCapacities
            .filter({
                !$0.text.isEmpty && $0.recordDraft?.setEntries.isEmpty == false
            })
            .max(by: { $0.date < $1.date }),
            let exercise = exerciseDefinitions.first(where: {
                $0.id == recent.exerciseID
            })
        {
            let quickRecord = ExerciseInputSuggestion(
                id: exercise.id,
                exerciseName: exercise.canonicalName,
                recentSummary: recent.text,
                recentDate: recent.date,
                recordDraft: recent.recordDraft
            )
            values.append(.init(
                title: "继续记录\(exercise.canonicalName)",
                prompt: quickRecord.draftText,
                quickRecord: quickRecord
            ))
        } else if let latest = workouts.first {
            let prompt = "继续记录\(latest.exercise)"
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
            exercises: exerciseDefinitions.map {
                ExerciseInputSuggestionBuilder.ExerciseInput(
                    id: $0.id,
                    name: $0.canonicalName,
                    isArchived: $0.isArchived
                )
            },
            recentCapacities: recentExerciseCapacities
        )
        // 草稿已经等于唯一建议时不再重复提示。
        if suggestions.count == 1, suggestions[0].draftText == query {
            return []
        }
        return suggestions
    }

    private var recentExerciseCapacities:
        [ExerciseInputSuggestionBuilder.RecentCapacityInput]
    {
        let legacy = workouts.compactMap { workout -> ExerciseInputSuggestionBuilder.RecentCapacityInput? in
            guard let exerciseID = workout.exerciseID else { return nil }
            return ExerciseInputSuggestionBuilder.RecentCapacityInput(
                exerciseID: exerciseID,
                date: workout.date,
                text: ExerciseQuickFill.text(for: workout),
                recordDraft: ExerciseQuickRecordDraft(
                    exerciseID: exerciseID,
                    exerciseName: workout.exercise,
                    setEntries: workout.setEntries,
                    restSeconds: workout.restSeconds,
                    durationMinutes: workout.durationMinutes
                )
            )
        }
        let projectedPerformanceIDs = Set(
            workouts.compactMap(\.sourcePerformanceID)
        )
        let guided = exercisePerformances.compactMap { performance -> ExerciseInputSuggestionBuilder.RecentCapacityInput? in
            guard !projectedPerformanceIDs.contains(performance.id),
                  !performance.workoutProjectionSuppressed,
                  let session = workoutSessions.first(where: {
                      $0.id == performance.sessionID
                  })
            else {
                return nil
            }
            return ExerciseInputSuggestionBuilder.RecentCapacityInput(
                exerciseID: performance.exerciseID,
                date: session.startedAt,
                text: ExerciseQuickFill.text(for: workoutSets.filter {
                    $0.performanceID == performance.id
                }),
                recordDraft: guidedQuickRecordDraft(
                    performance: performance,
                    sets: workoutSets.filter { $0.performanceID == performance.id }
                )
            )
        }
        return legacy + guided
    }

    private func applySuggestion(_ suggestion: ExerciseInputSuggestion) {
        draft = suggestion.draftText
        selectedExerciseSuggestion = suggestion
        composerFocusRequest = UUID()
    }

    private func guidedQuickRecordDraft(
        performance: ExercisePerformance,
        sets: [WorkoutSet]
    ) -> ExerciseQuickRecordDraft? {
        let completed = sets
            .filter { $0.status == .completed }
            .sorted { $0.order < $1.order }
        guard !completed.isEmpty else { return nil }
        let rests = completed.compactMap(\.actualRestSeconds)
        let rest = rests.count == completed.count && Set(rests).count == 1
            ? rests.first
            : nil
        return ExerciseQuickRecordDraft(
            exerciseID: performance.exerciseID,
            exerciseName: performance.exerciseName,
            setEntries: completed.map {
                WorkoutSetEvidence(
                    reps: $0.actualReps,
                    externalWeightKG: $0.actualWeightKG
                )
            },
            restSeconds: rest,
            durationMinutes: nil
        )
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        guard locationPreference != .unasked else {
            speechInput.stop()
            showsLocationPrompt = true
            return
        }
        submitCurrentDraft()
    }

    private func submitCurrentDraft(
        quickRecordOverride: ExerciseInputSuggestion? = nil
    ) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        speechInput.stop()
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
        let accepted = if let exactQuickDraft {
            processor.submitQuickWorkout(
                text: text,
                draft: exactQuickDraft,
                context: processingContext,
                locationService: locationContext
            )
        } else {
            processor.submit(
                text: text,
                attachments: pending,
                context: processingContext,
                includeLocation: locationPreference == .enabled,
                locationService: locationContext,
                selectedShortcutID: selectedShortcutID,
                forceLocal: useLocalForNextMessage
            )
        }
        if accepted {
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
        speechInput.stop()
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
        if speechInput.isListening {
            speechInput.stop()
            return
        }

        draftBeforeSpeech = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await speechInput.start()
        }
    }

    private func updateDraftFromSpeech() {
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

    /// 约 10Hz 非动画跟随；流式结束后由 `isProcessing` 的 off 分支做一次动画归位。
    private func scheduleLiveScroll(_ proxy: ScrollViewProxy) {
        guard isProcessingHere else { return }
        let interval: TimeInterval = 0.1
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
            guard !Task.isCancelled, isProcessingHere else { return }
            lastLiveScrollAt = Date()
            scrollToBottom(proxy, animated: false)
        }
    }

    private func scrollToBottomAfterLayout(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            scrollToBottom(proxy, animated: false)
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

enum ChatTextSelectionStyle {
    static let tintColor = UIColor.label
}

private struct SelectableChatText: UIViewRepresentable {
    let content: String
    let color: UIColor

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.tintColor = ChatTextSelectionStyle.tintColor
        textView.accessibilityTraits = .staticText
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard textView.attributedText?.string != content else { return }
        textView.attributedText = attributedContent
        textView.accessibilityLabel = content
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        let maximumWidth = max(proposal.width ?? 320, 1)
        let bounds = uiView.attributedText.boundingRect(
            with: CGSize(width: maximumWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let width = min(max(ceil(bounds.width), 1), maximumWidth)
        let height = ceil(uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height)
        return CGSize(width: width, height: height)
    }

    private var attributedContent: NSAttributedString {
        var attributed = (
            try? AttributedString(
                markdown: content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        ) ?? AttributedString(content)
        let runs = attributed.runs.map {
            ($0.range, $0.inlinePresentationIntent)
        }

        for (range, intent) in runs {
            let preferred = UIFont.preferredFont(forTextStyle: .subheadline)
            let baseFont = UIFont.systemFont(ofSize: preferred.pointSize, weight: .light)
            let font: UIFont
            if intent?.contains(.code) == true {
                font = UIFont.monospacedSystemFont(
                    ofSize: baseFont.pointSize,
                    weight: .regular
                )
            } else {
                let resolvedBase = intent?.contains(.stronglyEmphasized) == true
                    ? UIFont.systemFont(ofSize: preferred.pointSize, weight: .medium)
                    : baseFont
                var traits: UIFontDescriptor.SymbolicTraits = []
                if intent?.contains(.emphasized) == true {
                    traits.insert(.traitItalic)
                }
                let descriptor = resolvedBase.fontDescriptor
                    .withSymbolicTraits(traits)
                    ?? resolvedBase.fontDescriptor
                font = UIFont(descriptor: descriptor, size: resolvedBase.pointSize)
            }
            attributed[range].font = font
            attributed[range].foregroundColor = color
        }
        return NSAttributedString(attributed)
    }
}

struct CoachBubble: View {
    let message: CoachMessage
    var isLatestAssistantMessage = false
    var isLive = false
    var isStaged = false
    var canRetry = false
    var onRetry: () -> Void = {}
    var onDiscardPending: (() -> Void)?

    var body: some View {
        let visibleMessageText = message.isFromCoach
            ? AgentVisibleTextSanitizer.sanitize(message.text)
            : message.text

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

                if !message.mediaAttachments.isEmpty {
                    StoredMediaStrip(attachments: message.mediaAttachments)
                }

                if message.isFromCoach,
                   !message.agentTurnItems.isEmpty || isLive
                {
                    AgentTurnTranscript(
                        items: message.agentTurnItems,
                        isLive: isLive,
                        sourceMessage: message,
                        isEditable: isLatestAssistantMessage
                    )
                } else if !visibleMessageText.isEmpty, !message.isAutomaticMediaSummary {
                    Group {
                        if message.isFromCoach {
                            CoachResponseView(visibleMessageText)
                        } else {
                            SelectableChatText(
                                content: visibleMessageText,
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

                if canRetry {
                    Button(action: onRetry) {
                        Label("重试", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: AppTheme.minimumTapTarget)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.tint)
                    .accessibilityHint("复用原始文字、媒体和发送时的位置再次处理")
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
            locationName: message.location?.displayName,
            isFromCoach: message.isFromCoach
        )
        Text(content.text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .accessibilityLabel(content.accessibilityLabel)
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

private extension CoachMessage {
    var isAutomaticMediaSummary: Bool {
        guard !isFromCoach, !mediaAttachments.isEmpty else { return false }
        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "个", with: "")
        let imageCount = mediaAttachments.count { $0.kind == .image }
        let videoCount = mediaAttachments.count { $0.kind == .video }
        let parts = [
            imageCount > 0 ? "\(imageCount)张图片" : nil,
            videoCount > 0 ? "\(videoCount)视频" : nil
        ].compactMap { $0 }
        return normalized == "发送了" + parts.joined(separator: "和")
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
                            if let data = attachment.imageData,
                               let image = UIImage(data: data)
                            {
                                Image(uiImage: image).resizable().scaledToFill()
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
