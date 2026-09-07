import Foundation

enum FeedbackMailConfiguration {
    static let recipient = "hedonwang@gmail.com"

    static func credentials(bundle: Bundle = .main) throws
        -> FeedbackQQMailCredentials
    {
        guard let url = bundle.url(
            forResource: "FeedbackCredentials",
            withExtension: "plist"
        ) else {
            throw FeedbackSubmissionError.configurationMissing
        }
        do {
            return try credentials(plistData: Data(contentsOf: url))
        } catch {
            throw FeedbackSubmissionError.configurationMissing
        }
    }

    static func credentials(plistData: Data) throws
        -> FeedbackQQMailCredentials
    {
        guard let object = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ),
            let plist = object as? [String: Any],
            let senderAddress = nonemptyString(plist["SenderAddress"]),
            isQQMailAddress(senderAddress),
            let authorizationCode = nonemptyString(
                plist["SMTPAuthorizationCode"]
            )
        else {
            throw FeedbackSubmissionError.configurationMissing
        }
        return FeedbackQQMailCredentials(
            senderAddress: senderAddress,
            smtpAuthorizationCode: authorizationCode
        )
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || normalized.hasPrefix("YOUR_")
            ? nil
            : normalized
    }

    private static func isQQMailAddress(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.hasSuffix("@qq.com")
            || normalized.hasSuffix("@foxmail.com")
    }
}

struct FeedbackQQMailCredentials: Equatable, Sendable {
    let senderAddress: String
    let smtpAuthorizationCode: String
}

struct QQMailFeedbackClient {
    private let credentials: FeedbackQQMailCredentials
    private let transport: any FeedbackSMTPTransport

    init(
        credentials: FeedbackQQMailCredentials,
        transport: any FeedbackSMTPTransport = QQSMTPTransport()
    ) {
        self.credentials = credentials
        self.transport = transport
    }

    func submit(
        id: UUID,
        message: String,
        attachments: [PendingAttachment]
    ) async throws {
        do {
            let normalizedMessage = try FeedbackSubmissionPolicy
                .validatedMessage(message, attachments: attachments)
            let body = try FeedbackMailMessageBuilder.message(
                id: id,
                sender: credentials.senderAddress,
                text: normalizedMessage,
                attachments: attachments
            )
            try await transport.send(
                message: body,
                sender: credentials.senderAddress,
                recipient: FeedbackMailConfiguration.recipient,
                authorizationCode: credentials.smtpAuthorizationCode
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FeedbackSubmissionError {
            throw error
        } catch {
            throw FeedbackSubmissionError.deliveryUnavailable
        }
    }
}

enum FeedbackMailMessageBuilder {
    static func message(
        id: UUID,
        sender: String,
        text: String,
        attachments: [PendingAttachment]
    ) throws -> Data {
        let messageID = id.uuidString.lowercased()
        let subject = Data("Soma 用户反馈".utf8).base64EncodedString()
        let headers = [
            "From: \(sender)",
            "To: \(FeedbackMailConfiguration.recipient)",
            "Subject: =?UTF-8?B?\(subject)?=",
            "Message-ID: <\(messageID)@soma.feedback>",
            "MIME-Version: 1.0"
        ]
        let bodyText = text.isEmpty ? "（仅媒体反馈）" : text
        guard !attachments.isEmpty else {
            let lines = headers + [
                "Content-Type: text/plain; charset=UTF-8",
                "Content-Transfer-Encoding: base64",
                "",
                base64Lines(Data(bodyText.utf8)),
                ""
            ]
            return Data(lines.joined(separator: "\r\n").utf8)
        }

        let boundary = "soma-feedback-\(messageID)"
        var lines = headers + [
            "Content-Type: multipart/mixed; boundary=\"\(boundary)\"",
            "",
            "--\(boundary)",
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
            "",
            base64Lines(Data(bodyText.utf8))
        ]
        for (index, attachment) in attachments.enumerated() {
            let item = try mailAttachment(attachment, position: index + 1)
            lines.append(contentsOf: [
                "--\(boundary)",
                "Content-Type: \(item.contentType); name=\"\(item.filename)\"",
                "Content-Disposition: attachment; filename=\"\(item.filename)\"",
                "Content-Transfer-Encoding: base64",
                "",
                base64Lines(item.data)
            ])
        }
        lines.append(contentsOf: ["--\(boundary)--", ""])
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    private static func mailAttachment(
        _ attachment: PendingAttachment,
        position: Int
    ) throws -> (filename: String, contentType: String, data: Data) {
        switch attachment.kind {
        case .image:
            guard let data = attachment.imageData, !data.isEmpty else {
                throw FeedbackSubmissionError.attachmentUnavailable
            }
            return ("feedback-\(position).jpg", "image/jpeg", data)
        case .video:
            guard let url = attachment.videoURL,
                  let data = try? Data(contentsOf: url),
                  !data.isEmpty
            else {
                throw FeedbackSubmissionError.attachmentUnavailable
            }
            let isMP4 = url.pathExtension.lowercased() == "mp4"
            return (
                "feedback-\(position).\(isMP4 ? "mp4" : "mov")",
                isMP4 ? "video/mp4" : "video/quicktime",
                data
            )
        case .none:
            throw FeedbackSubmissionError.attachmentUnavailable
        }
    }

    private static func base64Lines(_ data: Data) -> String {
        let encoded = data.base64EncodedString()
        var lines: [Substring] = []
        var start = encoded.startIndex
        while start < encoded.endIndex {
            let end = encoded.index(
                start,
                offsetBy: min(
                    76,
                    encoded.distance(from: start, to: encoded.endIndex)
                )
            )
            lines.append(encoded[start ..< end])
            start = end
        }
        return lines.joined(separator: "\r\n")
    }
}

enum FeedbackSubmissionError: LocalizedError, Equatable {
    case empty
    case messageTooLong
    case tooManyAttachments
    case attachmentsTooLarge
    case attachmentUnavailable
    case configurationMissing
    case authenticationFailed
    case networkUnavailable
    case deliveryUnavailable

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
        case .configurationMissing:
            "本机尚未配置反馈邮箱，请填写 FeedbackCredentials.plist 后重新安装。"
        case .authenticationFailed:
            "反馈邮箱授权已失效，请更新本机 QQ SMTP 授权码后重试。"
        case .networkUnavailable:
            "当前网络无法连接邮件服务。蜂窝网络常会拦截 SMTP，请改用 Wi-Fi 后重试。"
        case .deliveryUnavailable:
            "反馈暂时无法发送，请稍后重试。"
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
