import Foundation

/// ADR 0083：崩溃诊断走和用户反馈相同的 SMTP 通道，但主题、体积上限与校验规则独立，
/// 不受用户反馈的 5000 字限制约束。正文另存为 `.txt` 附件，方便邮件客户端阅读长报告。
struct DiagnosticReportMailer: Sendable {
    static let maximumAttachmentBytes = 2 * 1024 * 1024

    private let credentialsProvider: @Sendable () throws
        -> FeedbackQQMailCredentials
    private let transport: any FeedbackSMTPTransport

    init(
        credentialsProvider: @escaping @Sendable () throws
            -> FeedbackQQMailCredentials = {
                try FeedbackMailConfiguration.credentials()
            },
        transport: any FeedbackSMTPTransport = QQSMTPTransport()
    ) {
        self.credentialsProvider = credentialsProvider
        self.transport = transport
    }

    func send(_ report: DiagnosticReport) async throws {
        let credentials = try credentialsProvider()
        let message = Self.mailMessage(
            report: report,
            sender: credentials.senderAddress
        )
        try await transport.send(
            message: message,
            sender: credentials.senderAddress,
            recipient: FeedbackMailConfiguration.recipient,
            authorizationCode: credentials.smtpAuthorizationCode
        )
    }

    static func mailMessage(
        report: DiagnosticReport,
        sender: String
    ) -> Data {
        let messageID = report.id.uuidString.lowercased()
        let boundary = "soma-diagnostic-\(messageID)"
        let encodedSubject = Data(report.subject.utf8).base64EncodedString()
        let body = trimmedAttachmentBody(report.body)
        let preview = String(body.prefix(1200))
        var lines = [
            "From: \(sender)",
            "To: \(FeedbackMailConfiguration.recipient)",
            "Subject: =?UTF-8?B?\(encodedSubject)?=",
            "Message-ID: <\(messageID)@soma.diagnostics>",
            "MIME-Version: 1.0",
            "Content-Type: multipart/mixed; boundary=\"\(boundary)\"",
            "",
            "--\(boundary)",
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
            "",
            base64Lines(Data(preview.utf8)),
            "--\(boundary)",
            "Content-Type: text/plain; charset=UTF-8; name=\"soma-crash-\(messageID).txt\"",
            "Content-Disposition: attachment; filename=\"soma-crash-\(messageID).txt\"",
            "Content-Transfer-Encoding: base64",
            "",
            base64Lines(Data(body.utf8))
        ]
        lines.append(contentsOf: ["--\(boundary)--", ""])
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    static func trimmedAttachmentBody(_ body: String) -> String {
        guard Data(body.utf8).count > maximumAttachmentBytes else { return body }
        var trimmed = body
        while Data(trimmed.utf8).count > maximumAttachmentBytes {
            trimmed = String(trimmed.suffix(trimmed.count / 2))
        }
        return "…（超出邮件体积上限，已截断更早内容）\n" + trimmed
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
