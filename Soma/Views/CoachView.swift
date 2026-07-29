import Observation
import SwiftData
import SwiftUI
import UIKit

private enum CoachSheet: String, Identifiable {
    case media
    var id: String {
        rawValue
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
        attachment: PendingAttachment?,
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
                attachment: attachment,
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
        attachment: PendingAttachment?,
        contextSummary: String,
        dataSpace: DataSpace,
        gyms: [GymProfile],
        equipment: [GymEquipment],
        ai: AIService,
        modelContext: ModelContext
    ) async {
        let media = await prepareMedia(attachment)
        let displayText = text.isEmpty
            ? (attachment?.kind == .video ? "发送了一段训练视频" : "发送了一张照片")
            : text
        modelContext.insert(CoachMessage(
            isFromCoach: false,
            text: displayText,
            mediaKind: attachment?.kind ?? .none,
            mediaPath: media.path
        ))
        try? modelContext.save()

        var performedRecordType: ConversationIntent?
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
                    mediaKind: attachment?.kind ?? .none,
                    imageCount: media.frames.count
                )
                modelContext.insert(trace)
                try? modelContext.save()

                let outcome = try await ai.runAgent(
                    text: text,
                    images: media.frames,
                    hasVideo: attachment?.kind == .video,
                    context: contextSummary,
                    trace: { [weak self] event in
                        self?.applyLiveAgentEvent(event)
                        trace.apply(event)
                        if case .assistantTextDelta = event {
                            return
                        }
                        try? modelContext.save()
                    }
                ) { call in
                    let result = ConversationRecorder.executeAgentTool(
                        call,
                        sourceText: text,
                        mediaKind: attachment?.kind ?? .none,
                        mediaPath: media.path,
                        in: modelContext
                    )
                    if let recordType = result.recordType {
                        performedRecordType = recordType
                    }
                    return result
                }
                reply = outcome.finalAnswer
                performedRecordType = outcome.primaryRecordType ?? performedRecordType
            } else {
                let result = try await ai.interpretConversation(
                    text: text,
                    images: media.frames,
                    hasVideo: attachment?.kind == .video,
                    context: contextSummary,
                    allowDemoFallback: dataSpace == .demo
                )
                reply = ConversationRecorder.apply(
                    result,
                    sourceText: text,
                    mediaKind: attachment?.kind ?? .none,
                    mediaPath: media.path,
                    gyms: gyms,
                    equipment: equipment,
                    in: modelContext
                )
                performedRecordType = result.intent
            }
            modelContext.insert(CoachMessage(
                isFromCoach: true,
                text: reply,
                recordType: performedRecordType
            ))
        } catch {
            let reason = error.localizedDescription
            let recovery = if performedRecordType != nil {
                "\n\nAgent 已完成的本地记录仍然保留，但生成最终回复时中断。"
            } else if attachment != nil {
                "\n\n附件已保存在本机对话中，但这次没有自动生成统计记录。请检查模型的多模态能力后重试。"
            } else {
                ""
            }
            modelContext.insert(CoachMessage(
                isFromCoach: true,
                text: "这次没有处理成功：\(reason)。\(recovery)"
            ))
        }

        try? modelContext.save()
        liveAssistantText = ""
        liveAgentActivity = nil
        isProcessing = false
        self.dataSpace = nil
        processingTask = nil
    }

    private func prepareMedia(
        _ attachment: PendingAttachment?
    ) async -> (path: String?, frames: [Data]) {
        guard let attachment else { return (nil, []) }
        switch attachment.kind {
        case .none:
            return (nil, [])
        case .image:
            guard let data = attachment.imageData else { return (nil, []) }
            return (try? MediaStore.saveImage(data), [data])
        case .video:
            guard let url = attachment.videoURL else { return (nil, []) }
            let path = try? MediaStore.saveVideo(from: url)
            return await (path, VideoFrameExtractor.frames(from: url))
        }
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

    @Query(sort: \CoachMessage.date) private var messages: [CoachMessage]
    @Query(sort: \GymProfile.createdAt) private var gyms: [GymProfile]
    @Query(sort: \GymEquipment.createdAt) private var equipment: [GymEquipment]
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \BodyEntry.date, order: .reverse) private var bodyEntries: [BodyEntry]
    @Query(sort: \UserProfile.updatedAt, order: .reverse) private var profiles: [UserProfile]

    @State private var draft = ""
    @State private var attachment: PendingAttachment?
    @State private var sheet: CoachSheet?
    @State private var speechInput = SpeechInputService()
    @State private var draftBeforeSpeech = ""
    @State private var showsGyms = false

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
                        CoachBubble(message: message)
                            .id(message.id)
                    }

                    if isProcessingHere {
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
                    attachment: $attachment,
                    gyms: gyms,
                    currentGym: currentGym,
                    isSending: processor.isProcessing,
                    isListening: speechInput.isListening,
                    speechMessage: speechInput.errorMessage,
                    onAddMedia: showMedia,
                    onSelectGym: selectGym,
                    onManageGyms: { showsGyms = true },
                    onToggleVoice: toggleVoice,
                    onSend: send
                )
            }
            .onChange(of: messages.count) {
                scrollToBottom(proxy)
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
        .sheet(item: $sheet) { destination in
            switch destination {
            case .media:
                MediaSourceDialog(allowsVideo: true) { media in
                    attachment = PendingAttachment(media)
                }
            }
        }
        .onDisappear {
            speechInput.stop()
        }
    }

    private func showMedia() {
        sheet = .media
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
        guard !text.isEmpty || attachment != nil, !processor.isProcessing else { return }
        speechInput.stop()
        let pending = attachment
        let accepted = processor.submit(
            text: text,
            attachment: pending,
            contextSummary: contextSummary,
            dataSpace: dataSpace.activeSpace,
            gyms: gyms,
            equipment: equipment,
            ai: ai,
            modelContext: modelContext
        )
        if accepted {
            draft = ""
            attachment = nil
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(isProcessingHere ? "live-response" : "bottom", anchor: .bottom)
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
        个人身体信息：\(profile)
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

                if message.mediaKind == .image {
                    LocalImageView(path: message.mediaPath)
                        .frame(width: 180, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                } else if message.mediaKind == .video {
                    Label("训练视频", systemImage: "play.rectangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }

                SelectableChatText(
                    content: message.text,
                    color: message.isFromCoach ? .label : .white
                )
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(
                    message.isFromCoach ? Color(uiColor: .secondarySystemGroupedBackground) : AppTheme.tint,
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .foregroundStyle(message.isFromCoach ? Color.primary : Color.white)
            }

            if message.isFromCoach {
                Spacer(minLength: 32)
            }
        }
        .frame(maxWidth: .infinity)
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
                    SelectableChatText(content: text, color: .label)
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
    @Binding var attachment: PendingAttachment?
    let gyms: [GymProfile]
    let currentGym: GymProfile?
    let isSending: Bool
    let isListening: Bool
    let speechMessage: String?
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

            if let attachment {
                AttachmentPreview(attachment: attachment) {
                    self.attachment = nil
                }
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
                .accessibilityLabel("添加照片或视频")

                TextField("说点什么，或发一张照片…", text: $draft, axis: .vertical)
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
                .disabled((draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachment == nil) || isSending)
                .accessibilityLabel("发送")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

private struct AttachmentPreview: View {
    let attachment: PendingAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let data = attachment.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.black.opacity(0.82)
                        Image(systemName: "play.fill").foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(attachment.kind == .video ? "视频已就绪" : "照片已就绪")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .accessibilityLabel("移除附件")
        }
        .padding(.horizontal, 4)
    }
}
