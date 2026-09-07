import SwiftUI
import UIKit

enum FeedbackSuccessPresentationAction: Equatable {
    case acknowledgeThenCollapse
    case acknowledgeInPlace
}

enum FeedbackSuccessPresentationPolicy {
    static let acknowledgementHold: Duration = .milliseconds(1000)

    static func action(isEmbedded: Bool) -> FeedbackSuccessPresentationAction {
        isEmbedded ? .acknowledgeThenCollapse : .acknowledgeInPlace
    }
}

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    var isEmbedded = false
    var assistantMessageID: UUID?
    var isCompact = false
    var onSubmitted: () -> Void = {}
    @State private var draftID = UUID()
    @State private var message = ""
    @State private var attachments: [PendingAttachment] = []
    @State private var showsMediaPicker = false
    @State private var isSending = false
    @State private var alert: FeedbackAlert?
    @State private var rating: Int?
    @State private var submissionTask: Task<Void, Never>?
    @State private var showsSuccess = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        Group {
            if isEmbedded {
                content
            } else {
                ScrollView {
                    content.padding()
                }
                .appPageBackground()
                .navigationTitle("反馈")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showsMediaPicker) {
            MediaSourceDialog(
                allowsVideo: true,
                selectionLimit: max(
                    FeedbackSubmissionPolicy.maximumAttachmentCount
                        - attachments.count,
                    1
                ),
                privacyMessage: "只会发送你明确选择的照片或视频。"
            ) { media in
                let available = max(
                    FeedbackSubmissionPolicy.maximumAttachmentCount
                        - attachments.count,
                    0
                )
                attachments.append(
                    contentsOf: media.prefix(available).map(PendingAttachment.init)
                )
            }
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("知道了"))
            )
        }
        .onDisappear {
            submissionTask?.cancel()
            scheduleTemporaryVideoCleanup(in: attachments)
        }
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("返回", systemImage: "chevron.left")
                    }
                    .accessibilityHint("关闭反馈页面并返回聊天")
                }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isCompact {
                Text(
                    assistantMessageID == nil
                        ? "告诉我哪里不好用，或你希望 Soma 接下来做什么。"
                        : "针对这条 AI 回复反馈，帮助我更快回溯问题。"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(
                    .horizontal,
                    isEmbedded ? AppTheme.pagePadding : 0
                )
            }
            if assistantMessageID != nil {
                ratingPicker
            }
            composer
        }
    }

    private var ratingPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("这条回复怎么样？")
                .font(.subheadline.weight(.medium))
            HStack(spacing: 4) {
                ForEach(1 ... 5, id: \.self) { value in
                    Button {
                        rating = value
                    } label: {
                        Image(systemName: value <= (rating ?? 0) ? "star.fill" : "star")
                            .foregroundStyle(AppTheme.warning)
                            .frame(
                                width: AppTheme.minimumTapTarget,
                                height: AppTheme.minimumTapTarget
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) 星")
                    .accessibilityValue(rating == value ? "已选择" : "未选择")
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !attachments.isEmpty {
                FeedbackAttachmentPreview(
                    attachments: attachments,
                    onRemove: removeAttachment
                )
            }

            TextField(
                "写下反馈，也可以只发送照片或视频…",
                text: $message,
                axis: .vertical
            )
            .lineLimit(isCompact ? 3 ... 8 : 5 ... 12)
            .focused($editorFocused)
            .disabled(isSending || showsSuccess)
            .accessibilityLabel("反馈内容")

            Divider()

            composerActions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppTheme.insetBackground,
            in: RoundedRectangle(
                cornerRadius: AppTheme.cardRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: AppTheme.cardRadius,
                style: .continuous
            )
            .stroke(AppTheme.separator, lineWidth: AppTheme.inputBorderWidth)
        }
        .overlay {
            if showsSuccess {
                successAcknowledgement
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: AppTheme.cardRadius,
                style: .continuous
            )
        )
        .animation(.easeInOut(duration: 0.28), value: showsSuccess)
        .sensoryFeedback(.success, trigger: showsSuccess)
    }

    private var successAcknowledgement: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.success)
                .symbolEffect(.bounce, value: showsSuccess)
            Text("已发送")
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.insetBackground.opacity(0.94))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("反馈已发送")
        .accessibilityIdentifier("feedback-success-acknowledgement")
    }

    @ViewBuilder
    private var composerActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                addMediaButton
                HStack(spacing: 12) {
                    attachmentCount
                    Spacer(minLength: 8)
                    submitButton
                }
            }
        } else {
            HStack(spacing: 12) {
                addMediaButton
                Spacer()
                attachmentCount
                submitButton
            }
        }
    }

    private var addMediaButton: some View {
        Button {
            editorFocused = false
            showsMediaPicker = true
        } label: {
            Label("照片或视频", systemImage: "plus.circle.fill")
        }
        .disabled(
            isSending
                || showsSuccess
                || attachments.count
                >= FeedbackSubmissionPolicy.maximumAttachmentCount
        )
    }

    @ViewBuilder
    private var attachmentCount: some View {
        if !attachments.isEmpty {
            Text("\(attachments.count)/\(FeedbackSubmissionPolicy.maximumAttachmentCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("已添加 \(attachments.count) 项附件")
        }
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            if isSending {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 44)
            } else {
                Text("发送")
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
        }
        .appPrimaryButtonStyle()
        .disabled(isSending || showsSuccess || isEmpty)
        .accessibilityHint("提交当前文字和附件")
    }

    private var isEmpty: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attachments.isEmpty
            && rating == nil
    }

    private func submit() {
        let submittedMessage: String
        if let assistantMessageID {
            guard let assistantContext = AssistantFeedbackContextBuilder.make(
                messageID: assistantMessageID,
                in: modelContext
            ) else {
                alert = FeedbackAlert(
                    title: "无法读取回复",
                    message: "这条 AI 回复可能已经被删除，请返回聊天后重试。"
                )
                return
            }
            submittedMessage = AssistantFeedbackEnvelope.compose(
                userFeedback: message,
                rating: rating,
                context: assistantContext
            )
        } else {
            submittedMessage = message
        }
        do {
            _ = try FeedbackSubmissionPolicy.validatedMessage(
                submittedMessage,
                attachments: attachments
            )
        } catch {
            alert = FeedbackAlert(error: error)
            return
        }
        editorFocused = false
        isSending = true
        let id = draftID
        let submittedAttachments = attachments
        submissionTask = Task { @MainActor in
            defer {
                isSending = false
                submissionTask = nil
            }
            do {
                let credentials = try FeedbackMailConfiguration.credentials()
                try await QQMailFeedbackClient(credentials: credentials).submit(
                    id: id,
                    message: submittedMessage,
                    attachments: submittedAttachments
                )
                scheduleTemporaryVideoCleanup(in: submittedAttachments)
                message = ""
                attachments = []
                rating = nil
                draftID = UUID()
                showsSuccess = true
                try await Task.sleep(
                    for: FeedbackSuccessPresentationPolicy.acknowledgementHold
                )
                guard !Task.isCancelled else { return }
                if FeedbackSuccessPresentationPolicy.action(
                    isEmbedded: isEmbedded
                ) == .acknowledgeThenCollapse {
                    onSubmitted()
                } else {
                    withAnimation(.easeOut(duration: 0.32)) {
                        showsSuccess = false
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                alert = FeedbackAlert(error: error)
            }
        }
    }

    private func removeAttachment(_ id: UUID) {
        guard let attachment = attachments.first(where: { $0.id == id }) else {
            return
        }
        scheduleTemporaryVideoCleanup(in: [attachment])
        attachments.removeAll { $0.id == id }
    }

    private func scheduleTemporaryVideoCleanup(in attachments: [PendingAttachment]) {
        let urls = attachments.compactMap { attachment in
            attachment.kind == .video ? attachment.videoURL : nil
        }
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

private struct FeedbackAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(error: Error) {
        title = "发送失败"
        message = (error as? LocalizedError)?.errorDescription
            ?? "反馈暂时无法发送，请稍后重试。"
    }
}

private struct FeedbackAttachmentPreview: View {
    let attachments: [PendingAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        preview(for: attachment)
                            .frame(width: 72, height: 64)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: AppTheme.controlRadius,
                                    style: .continuous
                                )
                            )

                        Button {
                            onRemove(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.7))
                        }
                        .offset(x: 5, y: -5)
                        .accessibilityLabel(
                            attachment.kind == .video ? "移除视频" : "移除照片"
                        )
                    }
                }
            }
            .padding(.top, 5)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func preview(for attachment: PendingAttachment) -> some View {
        if let data = attachment.imageData {
            PendingImagePreview(id: attachment.id, data: data)
        } else {
            ZStack {
                Color.black.opacity(0.84)
                Image(systemName: "play.fill")
                    .foregroundStyle(.white)
            }
        }
    }
}
