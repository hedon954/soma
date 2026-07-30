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

struct PendingAttachment: Identifiable {
    let id = UUID()
    let kind: MediaKind
    let imageData: Data?
    let videoURL: URL?

    init(_ media: PickedMedia) {
        switch media {
        case let .image(data):
            kind = .image
            imageData = data
            videoURL = nil
        case let .video(url):
            kind = .video
            imageData = nil
            videoURL = url
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

    @Query(sort: \CoachMessage.date) private var allMessages: [CoachMessage]
    @Query(sort: \GymProfile.createdAt) private var gyms: [GymProfile]
    @Query(sort: \GymEquipment.createdAt) private var equipment: [GymEquipment]
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \BodyEntry.date, order: .reverse) private var bodyEntries: [BodyEntry]
    @Query(sort: \UserProfile.updatedAt, order: .reverse) private var profiles: [UserProfile]

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

    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = min(340, geometry.size.width * 0.84)
            ZStack(alignment: .leading) {
                ScrollViewReader { proxy in
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
                    .scrollDismissesKeyboard(.interactively)
                    .appPageBackground()
                    .safeAreaInset(edge: .bottom) {
                        CoachComposer(
                            draft: $draft,
                            attachments: $attachments,
                            gyms: gyms,
                            currentGym: currentGym,
                            isSending: processor.isProcessing,
                            isListening: speechInput.isListening,
                            speechMessage: speechInput.errorMessage,
                            focusRequest: composerFocusRequest,
                            dismissRequest: composerDismissRequest,
                            onAddMedia: showMedia,
                            onSelectGym: selectGym,
                            onManageGyms: { showsGyms = true },
                            onToggleVoice: toggleVoice,
                            onSend: send
                        )
                    }
                    .onChange(of: messages.last?.id, initial: true) {
                        scrollToBottomAfterLayout(proxy)
                    }
                    .onChange(of: processor.isProcessing) {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: processor.liveAssistantText) {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: processor.liveAgentActivity) {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: processor.liveEventRevision) {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: scrollRequest) {
                        scrollToBottomAfterLayout(proxy)
                    }
                    .onChange(of: speechInput.transcript) {
                        updateDraftFromSpeech()
                    }
                }
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

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty, !processor.isProcessing else { return }
        guard ensureAIConfigured() else { return }
        guard locationPreference != .unasked else {
            speechInput.stop()
            showsLocationPrompt = true
            return
        }
        submitCurrentDraft()
    }

    private func submitCurrentDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty, !processor.isProcessing else { return }
        guard ensureAIConfigured() else { return }
        speechInput.stop()
        let pending = attachments
        let session = conversationSessions.ensureActiveSession(
            dataSpace: dataSpace.activeSpace,
            in: modelContext
        )
        let accepted = processor.submit(
            text: text,
            attachments: pending,
            context: ConversationProcessingContext(
                structuredContext: structuredContext,
                session: session,
                dataSpace: dataSpace.activeSpace,
                gyms: gyms,
                equipment: equipment,
                ai: ai,
                modelContext: modelContext
            ),
            includeLocation: locationPreference == .enabled,
            locationService: locationContext
        )
        if accepted {
            draft = ""
            attachments = []
            composerDismissRequest = UUID()
            scrollRequest = UUID()
        }
    }

    private func retry(_ responseMessage: CoachMessage) {
        guard ensureAIConfigured() else { return }
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
        if processor.retry(
            userMessage: userMessage,
            context: ConversationProcessingContext(
                structuredContext: structuredContext,
                session: session,
                dataSpace: dataSpace.activeSpace,
                gyms: gyms,
                equipment: equipment,
                ai: ai,
                modelContext: modelContext
            )
        ) {
            composerDismissRequest = UUID()
            scrollRequest = UUID()
        }
    }

    private func ensureAIConfigured() -> Bool {
        guard ai.hasRequiredAPIKey else {
            speechInput.stop()
            onRequireAIConfiguration()
            return false
        }
        return true
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

    private func scrollToBottomAfterLayout(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            scrollToBottom(proxy, animated: false)
        }
    }

    private var structuredContext: String {
        let gym = currentGym
        let currentEquipment = gym.map { target in
            equipment.filter { $0.gymID == target.id }.map(\.name).joined(separator: "、")
        } ?? "无"
        let latestWorkout = workouts.first.map {
            var parts = [$0.exercise]
            if let setEvidenceSummary = $0.setEvidenceSummary {
                parts.append(setEvidenceSummary)
            } else if let sets = $0.sets, let reps = $0.reps {
                parts.append("\(sets)×\(reps)")
            }
            if $0.setEntries.isEmpty, let weight = $0.weight {
                parts.append(weight == 0 ? "自重" : String(format: "%.1fkg", weight))
            }
            return parts.joined(separator: " ")
        } ?? "暂无"
        let todayCalories = meals
            .filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.calories }
        let weight = bodyEntries.compactMap(\.weight).first.map {
            String(format: "%.1fkg", $0)
        } ?? "暂无"
        let profile = profiles.first.map {
            var parts: [String] = []
            if !$0.displayName.isEmpty {
                parts.append("称呼 \($0.displayName)")
            }
            if let birthDate = $0.birthDate {
                parts.append("出生日期 \(birthDate.formatted(date: .numeric, time: .omitted))")
            }
            if let currentAge = $0.currentAge {
                parts.append("当前 \(currentAge) 岁")
            }
            if let height = $0.height {
                parts.append(String(format: "%.1fcm", height))
            }
            if !$0.fitnessGoal.isEmpty {
                parts.append("目标 \($0.fitnessGoal)")
            }
            if !$0.healthNotes.isEmpty {
                parts.append("限制 \($0.healthNotes)")
            }
            return parts.isEmpty ? "未填写" : parts.joined(separator: "；")
        } ?? "未填写"
        return """
        身体信息：\(profile)
        健身房：\(gym?.name ?? "无")；器械：\(currentEquipment)；最近训练：\(latestWorkout)；今日饮食：\(todayCalories)kcal；体重：\(weight)
        """
    }
}

private struct ConversationStarter: View {
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("直接告诉我，剩下的交给 AI。")
                .font(.title3.bold())
            Text("发照片、视频，或者像聊天一样描述。我会自动理解、记录并更新你的进展。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            VStack(spacing: 8) {
                starter("刚做完深蹲 4组8次 60kg")
                starter("午餐吃了鸡胸肉杂粮饭")
                starter("切换到公司健身房")
            }
        }
        .padding(.vertical, 8)
    }

    private func starter(_ text: String) -> some View {
        Button {
            onSelect(text)
        } label: {
            HStack {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
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
        textView.tintColor = UIColor(AppTheme.tint)
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
    var canRetry = false
    var onRetry: () -> Void = {}

    var body: some View {
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
                } else if !message.text.isEmpty, !message.isAutomaticMediaSummary {
                    Group {
                        if message.isFromCoach {
                            MarkdownText(message.text)
                        } else {
                            SelectableChatText(content: message.text, color: .white)
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

                if canRetry {
                    Button(action: onRetry) {
                        Label("重试", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
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

enum FoldedMediaLayout {
    static let cardWidth: CGFloat = 172
    static let minimumHeight: CGFloat = 116
    static let maximumHeight: CGFloat = 258
    static let portraitCardSize = CGSize(width: 150, height: 200)
    static let squareCardSize = CGSize(width: 160, height: 160)
    static let landscapeCardSize = CGSize(width: 172, height: 116)
    static let cornerRadius: CGFloat = 10
    static let layerScaleStep: CGFloat = 0.10
    static let middleLayerExposureRatio: CGFloat = 0.10
    static let backLayerExposureRatio: CGFloat = 0.165
    static let layerRotationStep: Double = 1.8

    static func cardHeight(forAspectRatio aspectRatio: CGFloat) -> CGFloat {
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            return cardWidth
        }
        return min(
            maximumHeight,
            max(minimumHeight, cardWidth / aspectRatio)
        )
    }

    static func scale(forLayer layer: Int) -> CGFloat {
        max(0.72, 1 - layerScaleStep * CGFloat(max(layer, 0)))
    }

    static func rotation(forLayer layer: Int) -> Double {
        layerRotationStep * Double(max(layer, 0))
    }

    static func foldedFrontSize(forAspectRatio aspectRatio: CGFloat) -> CGSize {
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            return squareCardSize
        }
        if aspectRatio < 0.90 {
            return portraitCardSize
        }
        if aspectRatio > 1.10 {
            return landscapeCardSize
        }
        return squareCardSize
    }

    static func scaledSize(
        forLayer layer: Int,
        frontSize: CGSize
    ) -> CGSize {
        let scale = scale(forLayer: layer)
        return CGSize(
            width: frontSize.width * scale,
            height: frontSize.height * scale
        )
    }

    static func targetExposure(
        forLayer layer: Int,
        frontWidth: CGFloat
    ) -> CGFloat {
        switch max(layer, 0) {
        case 0:
            0
        case 1:
            frontWidth * middleLayerExposureRatio
        default:
            frontWidth * backLayerExposureRatio
        }
    }

    static func rotatedBoundingWidth(
        forLayer layer: Int,
        size: CGSize
    ) -> CGFloat {
        let radians = rotation(forLayer: layer) * .pi / 180
        return size.width * abs(cos(radians)) +
            size.height * abs(sin(radians))
    }

    static func centerX(
        forLayer layer: Int,
        size: CGSize,
        frontSize: CGSize
    ) -> CGFloat {
        frontSize.width + targetExposure(
            forLayer: layer,
            frontWidth: frontSize.width
        ) -
            rotatedBoundingWidth(forLayer: layer, size: size) / 2
    }

    static func rightEdge(
        forLayer layer: Int,
        size: CGSize,
        frontSize: CGSize
    ) -> CGFloat {
        centerX(
            forLayer: layer,
            size: size,
            frontSize: frontSize
        ) +
            rotatedBoundingWidth(forLayer: layer, size: size) / 2
    }

    static func stackOverflowWidth(frontWidth: CGFloat) -> CGFloat {
        targetExposure(forLayer: 2, frontWidth: frontWidth)
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

struct StoredMediaStrip: View {
    let attachments: [MediaAttachmentReference]
    @State private var isExpanded = false

    var body: some View {
        Group {
            if attachments.count >= 3 {
                if isExpanded {
                    expandedGrid
                } else {
                    foldedCard
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        StoredMediaTile(attachment: attachment)
                            .frame(width: 132, height: 108)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )
                    }
                }
            }
        }
        .frame(maxWidth: 278, alignment: .trailing)
        .animation(.snappy(duration: 0.28), value: isExpanded)
    }

    private var foldedCard: some View {
        let backSize = foldedLayerSize(offset: 2)
        let middleSize = foldedLayerSize(offset: 1)

        return HStack(spacing: 10) {
            Button {
                isExpanded = true
            } label: {
                Text("展开 \(attachments.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 32)
                    .background(
                        Color.black.opacity(0.065),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("展开 \(attachments.count) 个媒体附件")

            ZStack(alignment: .topLeading) {
                StoredMediaTile(
                    attachment: foldedAttachment(offset: 2),
                    cornerRadius: FoldedMediaLayout.cornerRadius
                )
                .frame(
                    width: backSize.width,
                    height: backSize.height
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: FoldedMediaLayout.cornerRadius,
                        style: .continuous
                    )
                )
                .rotationEffect(
                    .degrees(FoldedMediaLayout.rotation(forLayer: 2)),
                    anchor: .center
                )
                .position(
                    x: FoldedMediaLayout.centerX(
                        forLayer: 2,
                        size: backSize,
                        frontSize: foldedFrontSize
                    ),
                    y: foldedCardHeight / 2
                )

                StoredMediaTile(
                    attachment: foldedAttachment(offset: 1),
                    cornerRadius: FoldedMediaLayout.cornerRadius
                )
                .frame(
                    width: middleSize.width,
                    height: middleSize.height
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: FoldedMediaLayout.cornerRadius,
                        style: .continuous
                    )
                )
                .rotationEffect(
                    .degrees(FoldedMediaLayout.rotation(forLayer: 1)),
                    anchor: .center
                )
                .position(
                    x: FoldedMediaLayout.centerX(
                        forLayer: 1,
                        size: middleSize,
                        frontSize: foldedFrontSize
                    ),
                    y: foldedCardHeight / 2
                )

                StoredMediaTile(
                    attachment: foldedAttachment(offset: 0),
                    cornerRadius: FoldedMediaLayout.cornerRadius
                )
                .frame(
                    width: foldedFrontSize.width,
                    height: foldedFrontSize.height
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: FoldedMediaLayout.cornerRadius,
                        style: .continuous
                    )
                )
                .position(
                    x: foldedFrontSize.width / 2,
                    y: foldedCardHeight / 2
                )
            }
            .frame(
                width: foldedFrontSize.width +
                    FoldedMediaLayout.stackOverflowWidth(
                        frontWidth: foldedFrontSize.width
                    ),
                height: foldedCardHeight,
                alignment: .topLeading
            )
            .contentShape(Rectangle())
            .onTapGesture {
                isExpanded = true
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("展开 \(attachments.count) 个媒体附件")
            .accessibilityAddTraits(.isButton)
        }
    }

    private var expandedGrid: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                isExpanded = false
            } label: {
                Text("收起")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 32)
                    .background(
                        Color.black.opacity(0.065),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, max(0, (foldedCardHeight - 32) / 2))
            .accessibilityLabel("收起媒体附件")

            LazyVStack(alignment: .trailing, spacing: 14) {
                ForEach(attachments) { attachment in
                    StoredMediaTile(
                        attachment: attachment,
                        cornerRadius: FoldedMediaLayout.cornerRadius
                    )
                    .frame(
                        width: FoldedMediaLayout.cardWidth,
                        height: cardHeight(for: attachment)
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: FoldedMediaLayout.cornerRadius,
                            style: .continuous
                        )
                    )
                }
            }
        }
    }

    private var foldedCardHeight: CGFloat {
        foldedFrontSize.height
    }

    private var foldedFrontSize: CGSize {
        FoldedMediaLayout.foldedFrontSize(
            forAspectRatio: aspectRatio(for: attachments[0])
        )
    }

    private func foldedLayerSize(offset: Int) -> CGSize {
        FoldedMediaLayout.scaledSize(
            forLayer: offset,
            frontSize: foldedFrontSize
        )
    }

    private func cardHeight(for attachment: MediaAttachmentReference) -> CGFloat {
        FoldedMediaLayout.cardHeight(
            forAspectRatio: aspectRatio(for: attachment)
        )
    }

    private func aspectRatio(
        for attachment: MediaAttachmentReference
    ) -> CGFloat {
        guard attachment.kind == .image,
              let image = MediaStore.image(at: attachment.path),
              image.size.width > 0,
              image.size.height > 0
        else {
            return 1
        }

        return image.size.width / image.size.height
    }

    private func foldedAttachment(offset: Int) -> MediaAttachmentReference {
        attachments[offset]
    }
}

private struct StoredMediaTile: View {
    let attachment: MediaAttachmentReference
    var cornerRadius: CGFloat = 14

    var body: some View {
        Group {
            if attachment.kind == .image {
                LocalImageView(path: attachment.path)
            } else {
                ZStack {
                    Color.black.opacity(0.84)
                    VStack(spacing: 5) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                        Text("视频")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .accessibilityLabel(attachment.kind == .image ? "图片附件" : "视频附件")
    }
}

private struct LiveAgentResponse: View {
    let text: String
    let activity: String?
    let isAgent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !text.isEmpty {
                HStack {
                    MarkdownText(text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                    Spacer(minLength: 32)
                }
            }

            if let activity {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(activity)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            } else if text.isEmpty {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(isAgent ? "Agent 正在分析…" : "正在理解并整理…")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CoachComposer: View {
    @Binding var draft: String
    @Binding var attachments: [PendingAttachment]
    let gyms: [GymProfile]
    let currentGym: GymProfile?
    let isSending: Bool
    let isListening: Bool
    let speechMessage: String?
    let focusRequest: UUID
    let dismissRequest: UUID
    let onAddMedia: () -> Void
    let onSelectGym: (GymProfile) -> Void
    let onManageGyms: () -> Void
    let onToggleVoice: () -> Void
    let onSend: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if gyms.count >= 2 {
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

            if !attachments.isEmpty {
                AttachmentPreview(
                    attachments: attachments,
                    onRemove: { id in
                        attachments.removeAll { $0.id == id }
                    }
                )
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
            HStack(alignment: .bottom, spacing: 9) {
                Button(action: onAddMedia) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                }
                .disabled(attachments.count >= MediaPicker.maximumSelectionCount)
                .accessibilityLabel("添加照片或视频，可多选")

                TextField("说点什么，或添加照片与视频…", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .focused($focused)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 19))

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

                Button(action: onSend) {
                    Group {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up").fontWeight(.bold)
                        }
                    }
                    .frame(width: 38, height: 38)
                    .foregroundStyle(.white)
                    .background(AppTheme.tint, in: Circle())
                }
                .disabled(
                    (
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && attachments.isEmpty
                    ) || isSending
                )
                .accessibilityLabel("发送")
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
