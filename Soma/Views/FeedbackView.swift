import SwiftUI
import UIKit

struct FeedbackView: View {
    @State private var draftID = UUID()
    @State private var message = ""
    @State private var attachments: [PendingAttachment] = []
    @State private var showsMediaPicker = false
    @State private var isSending = false
    @State private var alert: FeedbackAlert?
    @State private var submissionTask: Task<Void, Never>?
    @FocusState private var editorFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("告诉我们哪里不好用，或你希望 Soma 接下来做什么。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                composer

                Label(
                    "只有点击发送后，文字和所选媒体才会经 Soma Server 投递到 hedonwang@gmail.com；不会进入身体数据库、聊天记录或 Agent Trace。",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .appPageBackground()
        .navigationTitle("发送反馈")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsMediaPicker) {
            MediaSourceDialog(
                allowsVideo: true,
                selectionLimit: max(
                    FeedbackSubmissionPolicy.maximumAttachmentCount
                        - attachments.count,
                    1
                ),
                privacyMessage: "所选媒体只在你点击发送后用于本次反馈，并经 Soma Server 投递到反馈邮箱。"
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

            HStack(spacing: 12) {
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

                Spacer()

                if !attachments.isEmpty {
                    Text("\(attachments.count)/\(FeedbackSubmissionPolicy.maximumAttachmentCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("已添加 \(attachments.count) 项附件")
                }

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
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || isEmpty)
                .accessibilityHint("将反馈直接发送到 Soma 反馈邮箱")
            }
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(
                cornerRadius: AppTheme.cardRadius,
                style: .continuous
            )
        )
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
        guard let baseURL = FeedbackServiceConfiguration.baseURL() else {
            alert = FeedbackAlert(
                title: "反馈服务暂不可用",
                message: "当前版本没有可用的反馈服务地址，请更新后重试。"
            )
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
                let receipt = try await RemoteAgentClient(baseURL: baseURL)
                    .submitFeedback(
                        id: id,
                        message: submittedMessage,
                        attachments: submittedAttachments
                    )
                guard receipt.accepted else {
                    throw RemoteAgentError.invalidResponse
                }
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
