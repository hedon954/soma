import Foundation

enum FeedbackServiceConfiguration {
    static func baseURL(bundle: Bundle = .main) -> URL? {
        guard let rawValue = bundle.object(
            forInfoDictionaryKey: "SOMAFeedbackBaseURL"
        ) as? String,
            let url = URL(string: rawValue),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || isDevelopmentLoopback(url)
        else {
            return nil
        }
        return url
    }

    private static func isDevelopmentLoopback(_ url: URL) -> Bool {
        #if DEBUG
            url.scheme?.lowercased() == "http"
                && ["127.0.0.1", "localhost"].contains(
                    url.host?.lowercased() ?? ""
                )
        #else
            false
        #endif
    }
}

struct FeedbackSubmissionReceipt: Decodable, Equatable, Sendable {
    let feedbackID: String
    let accepted: Bool
}

enum FeedbackSubmissionError: LocalizedError, Equatable {
    case empty
    case messageTooLong
    case tooManyAttachments
    case attachmentsTooLarge
    case attachmentUnavailable

    var errorDescription: String? {
        switch self {
        case .empty:
            "请填写反馈内容或添加照片、视频。"
        case .messageTooLong:
            "反馈文字最多 \(FeedbackSubmissionPolicy.maximumMessageCharacters) 个字符。"
        case .tooManyAttachments:
            "最多添加 \(FeedbackSubmissionPolicy.maximumAttachmentCount) 项照片或视频。"
        case .attachmentsTooLarge:
            "附件总大小不能超过 25 MB，请移除较大的视频后重试。"
        case .attachmentUnavailable:
            "一项照片或视频已无法读取，请移除后重新添加。"
        }
    }
}

enum FeedbackSubmissionPolicy {
    static let maximumMessageCharacters = 5000
    static let maximumAttachmentCount = 10
    static let maximumAttachmentBytes = 25 * 1024 * 1024

    static func validatedMessage(
        _ message: String,
        attachments: [PendingAttachment]
    ) throws -> String {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty || !attachments.isEmpty else {
            throw FeedbackSubmissionError.empty
        }
        guard normalized.count <= maximumMessageCharacters else {
            throw FeedbackSubmissionError.messageTooLong
        }
        guard attachments.count <= maximumAttachmentCount else {
            throw FeedbackSubmissionError.tooManyAttachments
        }

        var totalBytes = 0
        for attachment in attachments {
            switch attachment.kind {
            case .image:
                guard let data = attachment.imageData, !data.isEmpty else {
                    throw FeedbackSubmissionError.attachmentUnavailable
                }
                totalBytes += data.count
            case .video:
                guard let url = attachment.videoURL,
                      let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                      let fileSize = values.fileSize,
                      fileSize > 0
                else {
                    throw FeedbackSubmissionError.attachmentUnavailable
                }
                totalBytes += fileSize
            case .none:
                throw FeedbackSubmissionError.attachmentUnavailable
            }
            guard totalBytes <= maximumAttachmentBytes else {
                throw FeedbackSubmissionError.attachmentsTooLarge
            }
        }
        return normalized
    }
}
