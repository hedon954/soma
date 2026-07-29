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

private struct PreparedConversationMedia {
    var attachments: [MediaAttachmentReference]
    var frames: [Data]
    var imageCount: Int
    var videoCount: Int

    var hasVideo: Bool {
        videoCount > 0
    }

    var primaryKind: MediaKind {
        attachments.first?.kind ?? .none
    }

    var primaryPath: String? {
        attachments.first?.path
    }

    var displaySummary: String {
        let parts = [
            imageCount > 0 ? "\(imageCount) 张图片" : nil,
            videoCount > 0 ? "\(videoCount) 个视频" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "发送了媒体" : "发送了" + parts.joined(separator: "和")
    }
}

@MainActor
@Observable
final class ConversationProcessingService {
    private(set) var isProcessing = false
    private(set) var dataSpace: DataSpace?
    private(set) var liveAssistantText = ""
    private(set) var liveAgentActivity: String?

    @ObservationIgnored
    private var processingTask: Task<Void, Never>?

    @discardableResult
    func submit(
        text: String,
        attachments: [PendingAttachment],
        contextSummary: String,
        dataSpace: DataSpace,
        gyms: [GymProfile],
        equipment: [GymEquipment],
        ai: AIService,
        modelContext: ModelContext
    ) -> Bool {
        guard !isProcessing else { return false }

        isProcessing = true
        self.dataSpace = dataSpace
        liveAssistantText = ""
        liveAgentActivity = ai.isRemoteEnabled
            ? "正在启动 Agent…"
            : "正在理解并整理…"

        processingTask = Task { [weak self] in
            guard let self else { return }
            await process(
                text: text,
                attachments: attachments,
                contextSummary: contextSummary,
                dataSpace: dataSpace,
                gyms: gyms,
                equipment: equipment,
                ai: ai,
                modelContext: modelContext
            )
        }
        return true
    }

    private func process(
        text: String,
        attachments: [PendingAttachment],
        contextSummary: String,
        dataSpace: DataSpace,
        gyms: [GymProfile],
        equipment: [GymEquipment],
        ai: AIService,
        modelContext: ModelContext
    ) async {
        let media = await prepareMedia(attachments)
        let displayText = text.isEmpty
            ? media.displaySummary
            : text
        modelContext.insert(CoachMessage(
            isFromCoach: false,
            text: text,
            mediaKind: media.primaryKind,
            mediaPath: media.primaryPath,
            mediaAttachments: media.attachments
        ))
        try? modelContext.save()

        var performedRecordType: ConversationIntent?
        var responseMessage: CoachMessage?
        var activeTrace: AgentTrace?
        do {
            let reply: String
            if ai.isRemoteEnabled {
                let provider = ai.provider
                let trace = AgentTrace(
                    provider: provider.displayName,
                    model: ai.model(for: provider),
                    endpoint: provider.endpoint(
                        baseURL: ai.baseURL(for: provider),
                        path: "chat/completions"
                    )?.absoluteString ?? ai.baseURL(for: provider),
                    dataSpaceRaw: dataSpace.rawValue,
                    userInput: displayText,
                    contextSnapshot: contextSummary,
                    mediaKind: media.primaryKind,
                    imageCount: media.frames.count,
                    imageAttachmentCount: media.imageCount,
                    videoAttachmentCount: media.videoCount
                )
                activeTrace = trace
                modelContext.insert(trace)
                let message = CoachMessage(
                    isFromCoach: true,
                    text: "",
                    agentTraceID: trace.id,
                    agentStatus: .running
                )
                responseMessage = message
                modelContext.insert(message)
                try? modelContext.save()

                let outcome = try await ai.runAgent(
                    text: text,
                    images: media.frames,
                    hasVideo: media.hasVideo,
                    imageAttachmentCount: media.imageCount,
                    videoAttachmentCount: media.videoCount,
                    context: contextSummary,
                    trace: { [weak self] event in
                        self?.applyLiveAgentEvent(event)
                        trace.apply(event)
                        switch event {
                        case let .assistantTextDelta(delta):
                            message.text += delta
                        case let .span(span):
                            if span.kind == .skill || span.kind == .tool,
                               span.status == .running
                            {
                                message.text = ""
                            }
                            message.applyAgentEvent(span)
                        case .completed:
                            message.agentStatus = .succeeded
                        case let .failed(_, cancelled, _):
                            message.agentStatus = cancelled ? .cancelled : .failed
                        }
                        if case .assistantTextDelta = event {} else {
                            try? modelContext.save()
                        }
                    }
                ) { call in
                    let result = ConversationRecorder.executeAgentTool(
                        call,
                        sourceText: text,
                        mediaKind: media.primaryKind,
                        mediaPath: media.primaryPath,
                        mediaAttachments: media.attachments,
                        in: modelContext
                    )
                    if let recordType = result.recordType {
                        performedRecordType = recordType
                    }
                    return result
                }
                reply = outcome.finalAnswer
                performedRecordType = outcome.primaryRecordType ?? performedRecordType
                message.text = reply
                message.recordType = performedRecordType
                message.agentStatus = .succeeded
            } else {
                let result = try await ai.interpretConversation(
                    text: text,
                    images: media.frames,
                    hasVideo: media.hasVideo,
                    context: contextSummary,
                    allowDemoFallback: dataSpace == .demo
                )
                reply = ConversationRecorder.apply(
                    result,
                    sourceText: text,
                    mediaKind: media.primaryKind,
                    mediaPath: media.primaryPath,
                    mediaAttachments: media.attachments,
                    gyms: gyms,
                    equipment: equipment,
                    in: modelContext
                )
                performedRecordType = result.intent
            }
            if responseMessage == nil {
                modelContext.insert(CoachMessage(
                    isFromCoach: true,
                    text: reply,
                    recordType: performedRecordType
                ))
            }
        } catch {
            let reason = error.localizedDescription
            let recovery = if performedRecordType != nil {
                "\n\nAgent 已完成的本地记录仍然保留，但生成最终回复时中断。"
            } else if !attachments.isEmpty {
                "\n\n附件已保存在本机对话中，但这次没有自动生成统计记录。请检查模型的多模态能力后重试。"
            } else {
                ""
            }
            let failureText = "这次没有处理成功：\(reason)。\(recovery)"
            if let responseMessage {
                responseMessage.text = failureText
                responseMessage.agentStatus = .failed
                if let activeTrace, activeTrace.status == .running {
                    activeTrace.apply(.failed(message: reason, cancelled: false, at: .now))
                }
            } else {
                modelContext.insert(CoachMessage(
                    isFromCoach: true,
                    text: failureText
                ))
            }
        }

        try? modelContext.save()
        liveAssistantText = ""
        liveAgentActivity = nil
        isProcessing = false
        self.dataSpace = nil
        processingTask = nil
    }

    private func prepareMedia(
        _ attachments: [PendingAttachment]
    ) async -> PreparedConversationMedia {
        var references: [MediaAttachmentReference] = []
        var frameGroups: [[Data]] = []
        var imageCount = 0
        var videoCount = 0

        for attachment in attachments {
            switch attachment.kind {
            case .none:
                continue
            case .image:
                guard
                    let data = attachment.imageData,
                    let path = try? MediaStore.saveImage(data)
                else { continue }
                references.append(MediaAttachmentReference(kind: .image, path: path))
                frameGroups.append([data])
                imageCount += 1
            case .video:
                guard
                    let url = attachment.videoURL,
                    let path = try? MediaStore.saveVideo(from: url)
                else { continue }
                references.append(MediaAttachmentReference(kind: .video, path: path))
                await frameGroups.append(VideoFrameExtractor.frames(from: url))
                videoCount += 1
            }
        }

        return PreparedConversationMedia(
            attachments: references,
            frames: Self.balancedFrames(from: frameGroups, limit: 12),
            imageCount: imageCount,
            videoCount: videoCount
        )
    }

    private static func balancedFrames(
        from groups: [[Data]],
        limit: Int
    ) -> [Data] {
        guard limit > 0 else { return [] }
        var result: [Data] = []
        var index = 0
        while result.count < limit {
            var appended = false
            for group in groups where index < group.count {
                result.append(group[index])
                appended = true
                if result.count == limit {
                    return result
                }
            }
            guard appended else { break }
            index += 1
        }
        return result
    }

    private func applyLiveAgentEvent(_ event: AgentTraceEvent) {
        switch event {
        case let .assistantTextDelta(delta):
            liveAssistantText += delta
            liveAgentActivity = "正在生成回复…"
        case let .span(span):
            guard span.status == .running else { return }
            switch span.kind {
            case .model:
                liveAgentActivity = "模型正在响应…"
            case .skill:
                liveAgentActivity = "正在加载 Skill：\(span.title)"
            case .tool:
                liveAgentActivity = "正在执行：\(span.title)"
            case .output:
                liveAgentActivity = "正在整理结果…"
            }
        case .completed, .failed:
            liveAgentActivity = nil
        }
    }
}

struct CoachView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AIService.self) private var ai
    @Environment(DataSpaceController.self) private var dataSpace
    @Environment(ConversationProcessingService.self) private var processor
    @Environment(SomaCaptureRouter.self) private var captureRouter

    @Query(sort: \CoachMessage.date) private var messages: [CoachMessage]
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

    private var currentGym: GymProfile? {
        GymSelection.current(in: gyms)
    }

    private var isProcessingHere: Bool {
        processor.isProcessing && processor.dataSpace == dataSpace.activeSpace
    }

    var body: some View {
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
                                && message.agentStatus == .running
                        )
                        .id(message.id)
                    }

                    if isProcessingHere, !ai.isRemoteEnabled {
                        LiveAgentResponse(
                            text: processor.liveAssistantText,
                            activity: processor.liveAgentActivity,
                            isAgent: ai.isRemoteEnabled
                        )
                        .id("live-response")
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
            .onChange(of: speechInput.transcript) {
                updateDraftFromSpeech()
            }
        }
        .navigationTitle("Soma")
        .navigationBarTitleDisplayMode(.inline)
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
        .onDisappear {
            speechInput.stop()
        }
    }

    private func showMedia() {
        sheet = .media
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
        speechInput.stop()
        let pending = attachments
        let accepted = processor.submit(
            text: text,
            attachments: pending,
            contextSummary: contextSummary,
            dataSpace: dataSpace.activeSpace,
            gyms: gyms,
            equipment: equipment,
            ai: ai,
            modelContext: modelContext
        )
        if accepted {
            draft = ""
            attachments = []
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
        let target = isProcessingHere ? "live-response" : "bottom"
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func scrollToBottomAfterLayout(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            scrollToBottom(proxy, animated: false)
        }
    }

    private var contextSummary: String {
        let gym = currentGym
        let currentEquipment = gym.map { target in
            equipment.filter { $0.gymID == target.id }.map(\.name).joined(separator: "、")
        } ?? "无"
        let latestWorkout = workouts.first.map {
            var parts = [$0.exercise]
            if let sets = $0.sets, let reps = $0.reps {
                parts.append("\(sets)×\(reps)")
            }
            if let weight = $0.weight {
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
        let recentConversation = messages.suffix(8).map {
            let role = $0.isFromCoach ? "教练" : "用户"
            let text = $0.text
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(160)
            return "\(role)：\(text)"
        }
        .joined(separator: "\n")
        return """
        身体信息：\(profile)
        健身房：\(gym?.name ?? "无")；器械：\(currentEquipment)；最近训练：\(latestWorkout)；今日饮食：\(todayCalories)kcal；体重：\(weight)
        最近对话：
        \(recentConversation)
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

private struct CoachBubble: View {
    let message: CoachMessage
    var isLive = false

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

                if !message.mediaAttachments.isEmpty {
                    StoredMediaStrip(attachments: message.mediaAttachments)
                }

                if !message.text.isEmpty, !message.isAutomaticMediaSummary {
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

                if message.isFromCoach,
                   !message.agentEvents.isEmpty || isLive
                {
                    AgentEventTimeline(
                        events: message.agentEvents,
                        status: message.agentStatus,
                        isLive: isLive
                    )
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

private struct StoredMediaStrip: View {
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

private struct AgentEventTimeline: View {
    let events: [AgentTraceSpan]
    let status: AgentTraceStatus?
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(events) { event in
                HStack(alignment: .top, spacing: 8) {
                    eventIcon(event)
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.caption.weight(.semibold))
                        if let detail = detail(for: event) {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            if isLive, events.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("Agent 正在分析…")
                        .font(.caption.weight(.medium))
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .foregroundStyle(status == .failed ? Color.red : Color.primary)
    }

    @ViewBuilder
    private func eventIcon(_ event: AgentTraceSpan) -> some View {
        switch event.status {
        case .running:
            ProgressView().controlSize(.mini)
        case .succeeded:
            Image(systemName: event.kind == .skill ? "sparkles" : "checkmark.circle.fill")
                .foregroundStyle(AppTheme.tint)
        case .failed, .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func detail(for event: AgentTraceSpan) -> String? {
        if event.status == .running {
            return event.kind == .skill ? "正在加载 Skill" : "正在调用工具"
        }
        if let error = event.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty
        {
            return error
        }
        guard event.kind == .tool,
              let output = event.output,
              let data = output.data(using: .utf8),
              let result = try? JSONDecoder().decode(AgentToolResult.self, from: data)
        else {
            return event.status == .succeeded ? "已完成" : nil
        }
        return result.observation
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
    let onAddMedia: () -> Void
    let onSelectGym: (GymProfile) -> Void
    let onManageGyms: () -> Void
    let onToggleVoice: () -> Void
    let onSend: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Menu {
                    if gyms.isEmpty {
                        Text("暂无健身房")
                    } else {
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

                Spacer()
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
