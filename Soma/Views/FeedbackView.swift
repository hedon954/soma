import SwiftUI
import UIKit

struct FeedbackView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var isEmbedded = false
    @State private var draftID = UUID()
    @State private var message = ""
    @State private var attachments: [PendingAttachment] = []
    @State private var showsMediaPicker = false
    @State private var isSending = false
    @State private var alert: FeedbackAlert?
    @State private var submissionTask: Task<Void, Never>?
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
            cleanupTemporaryVideos(in: attachments)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("告诉我哪里不好用，或你希望 Soma 接下来做什么。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(
                    .horizontal,
                    isEmbedded ? AppTheme.pagePadding : 0
                )
            composer
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
            .lineLimit(5 ... 12)
            .focused($editorFocused)
            .disabled(isSending)
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
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accentEmphasis)
        .disabled(isSending || isEmpty)
        .accessibilityHint("提交当前文字和附件")
    }

    private var isEmpty: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attachments.isEmpty
    }

    private func submit() {
        do {
            _ = try FeedbackSubmissionPolicy.validatedMessage(
                message,
                attachments: attachments
            )
        } catch {
            alert = FeedbackAlert(error: error)
            return
        }
        editorFocused = false
        isSending = true
        let id = draftID
        let submittedMessage = message
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
                cleanupTemporaryVideos(in: submittedAttachments)
                message = ""
                attachments = []
                draftID = UUID()
                alert = FeedbackAlert(
                    title: "反馈已发送",
                    message: "谢谢，你的反馈已经送达。"
                )
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
        cleanupTemporaryVideos(in: [attachment])
        attachments.removeAll { $0.id == id }
    }

    private func cleanupTemporaryVideos(in attachments: [PendingAttachment]) {
        for attachment in attachments where attachment.kind == .video {
            guard let url = attachment.videoURL else { continue }
            try? FileManager.default.removeItem(at: url)
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
        if let data = attachment.imageData,
           let image = UIImage(data: data)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.black.opacity(0.84)
                Image(systemName: "play.fill")
                    .foregroundStyle(.white)
            }
        }
    }
}
