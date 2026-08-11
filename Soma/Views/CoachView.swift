import Observation
import OSLog
import SwiftData
import SwiftUI
import UIKit

private enum CoachSheet: Identifiable {
    case media
    case quickCapture(CaptureEntryRequest)

    var id: String {
        switch self {
        case .media:
            "media"
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
    @State private var showsLocationPrompt = false
    @State private var useLocalForNextMessage = false
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

    private var currentGym: GymProfile? {
        GymSelection.current(in: gyms)
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
    private var stagedJobCount: Int {
        agentJobs.filter {
            $0.dataSpace == dataSpace.activeSpace && $0.state == .staged
        }.count
    }

    private var stagedTurnIDs: Set<UUID> {
        Set(
            agentJobs
                .filter {
                    $0.dataSpace == dataSpace.activeSpace && $0.state == .staged
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
                    onSelectSession: selectSession
                )
                .frame(width: drawerWidth)
                .offset(x: sessionDrawerPresented ? 0 : -drawerWidth)
            }
            .clipped()
            .animation(.snappy(duration: 0.24), value: sessionDrawerPresented)
            .simultaneousGesture(sessionDrawerGesture)
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
        }
        .accessibilityAction(named: "打开历史对话") {
            openSessionDrawer()
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
                if messages.count <= 1 {
                    ConversationStarter(onSelect: sendPrompt)
                }

                ForEach(messages) { message in
                    CoachBubble(
                        message: message,
                        isLive: isProcessingHere
                            && message.agentStatus == .running,
                        isStaged: message.turnID.map(stagedTurnIDs.contains) ?? false,
                        canRetry: !processor.isProcessing
                            && ConversationTurnProjection.canRetry(
                                message,
                                in: messages
                            ),
                        onRetry: { retry(message) }
                    )
                    .id(message.id)
                }

                Color.clear.frame(height: 1).id("bottom")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var composer: some View {
        CoachComposer(
            draft: $draft,
            attachments: $attachments,
            gyms: gyms,
            currentGym: currentGym,
            exerciseSuggestions: exerciseSuggestions,
            stagedCount: stagedJobCount,
            showsExecutionChoice: remoteExecutionEnabled
                && RemoteAgentPreference.baseURL() != nil,
            useLocalForNextMessage: $useLocalForNextMessage,
            isSending: processor.isProcessing,
            isListening: speechInput.isListening,
            speechMessage: speechInput.errorMessage,
            focusRequest: composerFocusRequest,
            dismissRequest: composerDismissRequest,
            onAddMedia: showMedia,
            onSelectGym: selectGym,
            onManageGyms: { showsGyms = true },
            onApplySuggestion: applySuggestion,
            onOpenLLMConfiguration: onRequireAIConfiguration,
            onToggleVoice: toggleVoice,
            onSend: send
        )
    }

    private func showMedia() {
        sheet = .media
    }

    private var sessionDrawerGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .global)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) else {
                    return
                }
                if sessionDrawerPresented, horizontal < -60 {
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

    private func switchToSession(_: ConversationSession) {
        draft = ""
        attachments = []
        useLocalForNextMessage = false
        speechInput.stop()
        composerDismissRequest = UUID()
        scrollRequest = UUID()
        closeSessionDrawer()
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
                text: ExerciseQuickFill.text(for: workout)
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
                })
            )
        }
        return legacy + guided
    }

    private func applySuggestion(_ suggestion: ExerciseInputSuggestion) {
        draft = suggestion.draftText
        composerFocusRequest = UUID()
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

    private func submitCurrentDraft() {
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
        // 引导条件要在落盘前判断：这条消息本身会让暂存计数从 0 变成 1。
        let needsConfigurationGuidance = needsConfigurationGuidance(
            forceLocal: useLocalForNextMessage
        )
        let accepted = processor.submit(
            text: text,
            attachments: pending,
            context: processingContext,
            includeLocation: locationPreference == .enabled,
            locationService: locationContext,
            forceLocal: useLocalForNextMessage
        )
        if accepted {
            draft = ""
            attachments = []
            useLocalForNextMessage = false
            composerDismissRequest = UUID()
            scrollRequest = UUID()
            if needsConfigurationGuidance {
                openLLMConfiguration()
            }
        }
    }

    private func retry(_ responseMessage: CoachMessage) {
        let needsConfigurationGuidance = needsConfigurationGuidance(forceLocal: false)
        guard let turnID = responseMessage.turnID,
              let userMessage = ConversationTurnProjection.userMessage(
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

    /// ADR 0045：缺配置不再阻止发送。队列里还没有暂存消息时说明用户是第一次遇到，
    /// 此时把消息落盘暂存并同时打开「LLM 配置」；之后只靠输入区的暂存提示，不再打断。
    private func needsConfigurationGuidance(forceLocal: Bool) -> Bool {
        if !forceLocal, RemoteAgentPreference.isEnabled() {
            return false
        }
        return !ai.hasRequiredAPIKey && stagedJobCount == 0
    }

    private func openLLMConfiguration() {
        speechInput.stop()
        onRequireAIConfiguration()
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

private struct ConversationStarter: View {
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("像聊天一样描述训练、饮食或身体变化，Soma 会理解并记录。")
                .font(.title3.bold())
                .lineSpacing(3)
            VStack(spacing: 8) {
                starter("刚做完深蹲 4组8次 60kg")
                starter("午餐吃了鸡胸肉杂粮饭")
            }
        }
        .padding(.vertical, 8)
    }

    private func starter(_ text: String) -> some View {
        Button {
            onSelect(text)
        } label: {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
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
            let baseFont = UIFont.preferredFont(forTextStyle: .body)
            let font: UIFont
            if intent?.contains(.code) == true {
                font = UIFont.monospacedSystemFont(
                    ofSize: baseFont.pointSize,
                    weight: .regular
                )
            } else {
                var traits: UIFontDescriptor.SymbolicTraits = []
                if intent?.contains(.stronglyEmphasized) == true {
                    traits.insert(.traitBold)
                }
                if intent?.contains(.emphasized) == true {
                    traits.insert(.traitItalic)
                }
                let descriptor = baseFont.fontDescriptor
                    .withSymbolicTraits(traits)
                    ?? baseFont.fontDescriptor
                font = UIFont(descriptor: descriptor, size: baseFont.pointSize)
            }
            attributed[range].font = font
            attributed[range].foregroundColor = color
        }
        return NSAttributedString(attributed)
    }
}

struct CoachBubble: View {
    let message: CoachMessage
    var isLive = false
    var isStaged = false
    var canRetry = false
    var onRetry: () -> Void = {}

    var body: some View {
        let visibleMessageText = message.isFromCoach
            ? AgentVisibleTextSanitizer.sanitize(message.text)
            : message.text

        HStack(alignment: .bottom, spacing: 8) {
            if !message.isFromCoach {
                Spacer(minLength: 52)
            }

            VStack(alignment: message.isFromCoach ? .leading : .trailing, spacing: 7) {
                if let label = message.recordType?.recordedLabel {
                    Label(label, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.tint)
                }

                if !message.isFromCoach, let location = message.location {
                    Label(location.displayName, systemImage: "location.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(AppTheme.tint.opacity(0.88), in: Capsule())
                        .accessibilityLabel("发送位置 \(location.displayName)")
                }

                if !message.mediaAttachments.isEmpty {
                    StoredMediaStrip(attachments: message.mediaAttachments)
                }

                if message.isFromCoach,
                   !message.agentTurnItems.isEmpty || isLive
                {
                    AgentTurnTranscript(
                        items: message.agentTurnItems,
                        isLive: isLive
                    )
                } else if !visibleMessageText.isEmpty, !message.isAutomaticMediaSummary {
                    Group {
                        if message.isFromCoach {
                            MarkdownText(visibleMessageText)
                        } else {
                            SelectableChatText(content: visibleMessageText, color: .white)
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(
                        message.isFromCoach
                            ? Color(uiColor: .secondarySystemGroupedBackground)
                            : AppTheme.tint,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                    .foregroundStyle(message.isFromCoach ? Color.primary : Color.white)
                }

                if isStaged, !message.isFromCoach {
                    Label("已暂存，恢复后自动继续", systemImage: "tray.full")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if canRetry {
                    Button(action: onRetry) {
                        Label("重试", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.tint)
                    .accessibilityHint("复用原始文字、媒体和发送时的位置再次处理")
                }
            }

            if message.isFromCoach {
                Spacer(minLength: 32)
            }
        }
        .frame(maxWidth: .infinity)
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
    let stagedCount: Int
    let showsExecutionChoice: Bool
    @Binding var useLocalForNextMessage: Bool
    let isSending: Bool
    let isListening: Bool
    let speechMessage: String?
    let focusRequest: UUID
    let dismissRequest: UUID
    let onAddMedia: () -> Void
    let onSelectGym: (GymProfile) -> Void
    let onManageGyms: () -> Void
    let onApplySuggestion: (ExerciseInputSuggestion) -> Void
    let onOpenLLMConfiguration: () -> Void
    let onToggleVoice: () -> Void
    let onSend: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focused: Bool

    /// PRD 020：输入区同一时间最多一层上下文条，优先级为
    /// 附件预览 > 动作建议 > 场馆切换。
    private enum ContextStrip {
        case attachments, suggestions, gym
    }

    private var contextStrip: ContextStrip? {
        if !attachments.isEmpty {
            return .attachments
        }
        if !exerciseSuggestions.isEmpty {
            return .suggestions
        }
        if gyms.count >= 2 {
            return .gym
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 8) {
            // ADR 0045：暂存计数常驻在输入区上方，与上下文条互不挤占。
            if stagedCount > 0 {
                StagedQueueBanner(
                    count: stagedCount,
                    onOpenConfiguration: onOpenLLMConfiguration
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
            case .gym:
                gymStrip
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
        .padding(.vertical, 9)
        .background(.bar)
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
            .padding(.vertical, 6)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: Capsule()
            )
        }
        .accessibilityLabel("当前健身房 \(currentGym?.name ?? "未选择")，点击切换")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addMediaButton: some View {
        Button(action: onAddMedia) {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .frame(width: 38, height: 38)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
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
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 19)
            )
    }

    private var voiceButton: some View {
        Button(action: onToggleVoice) {
            Image(systemName: isListening ? "waveform" : "mic.fill")
                .font(.body.weight(.semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(isListening ? Color.white : AppTheme.tint)
                .background(
                    isListening ? AppTheme.tint : Color(uiColor: .secondarySystemGroupedBackground),
                    in: Circle()
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
        Group {
            if isSending {
                ProgressView().tint(.white)
            } else {
                Image(systemName: useLocalForNextMessage ? "iphone" : "arrow.up")
                    .fontWeight(.bold)
            }
        }
        .frame(width: 38, height: 38)
        .foregroundStyle(.white)
        .background(
            useLocalForNextMessage ? AppTheme.warning : AppTheme.tint,
            in: Circle()
        )
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

/// ADR 0045：暂存队列对用户只有两个信息——还有几条没被消费，以及去哪里恢复。
private struct StagedQueueBanner: View {
    let count: Int
    let onOpenConfiguration: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .font(.footnote)
                .foregroundStyle(AppTheme.warning)
            Text("\(count) 条已暂存，LLM 恢复后自动继续")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("去配置", action: onOpenConfiguration)
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            AppTheme.warning.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) 条消息已暂存，LLM 恢复后自动继续")
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
