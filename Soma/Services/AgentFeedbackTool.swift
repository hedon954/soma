import Foundation

enum AgentFeedbackTool {
    static func submit(
        id: UUID,
        sourceText: String,
        mediaAttachments: [MediaAttachmentReference],
        credentials: FeedbackQQMailCredentials? = nil,
        transport: any FeedbackSMTPTransport = QQSMTPTransport(),
        mediaURL: @Sendable (String) -> URL? = { MediaStore.url(at: $0) }
    ) async throws -> AgentToolResult {
        do {
            let resolvedCredentials: FeedbackQQMailCredentials = if let credentials {
                credentials
            } else {
                try FeedbackMailConfiguration.credentials()
            }
            let attachments = try pendingAttachments(
                from: mediaAttachments,
                mediaURL: mediaURL
            )
            try await QQMailFeedbackClient(
                credentials: resolvedCredentials,
                transport: transport
            ).submit(
                id: id,
                message: sourceText,
                attachments: attachments
            )
            return .success("反馈已发送。")
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FeedbackSubmissionError {
            return .failure(
                error.errorDescription
                    ?? FeedbackSubmissionError.deliveryUnavailable
                    .errorDescription
                    ?? "反馈暂时无法发送，请稍后重试。"
            )
        } catch {
            return .failure("反馈暂时无法发送，请稍后重试。")
        }
    }

    private static func pendingAttachments(
        from references: [MediaAttachmentReference],
        mediaURL: (String) -> URL?
    ) throws -> [PendingAttachment] {
        try references.map { reference in
            guard let url = mediaURL(reference.path) else {
                throw FeedbackSubmissionError.attachmentUnavailable
            }
            switch reference.kind {
            case .image:
                guard let data = try? Data(contentsOf: url), !data.isEmpty else {
                    throw FeedbackSubmissionError.attachmentUnavailable
                }
                return PendingAttachment(kind: .image, imageData: data)
            case .video:
                return PendingAttachment(kind: .video, videoURL: url)
            case .none:
                throw FeedbackSubmissionError.attachmentUnavailable
            }
        }
    }
}
