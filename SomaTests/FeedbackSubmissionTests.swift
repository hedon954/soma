import Foundation
@testable import Soma
import SwiftData
import XCTest

final class FeedbackSubmissionTests: XCTestCase {
    func testQQMailCredentialsRequireRealLocalValues() throws {
        let valid = try PropertyListSerialization.data(
            fromPropertyList: [
                "SenderAddress": "123456@qq.com",
                "SMTPAuthorizationCode": "authorization-code"
            ],
            format: .xml,
            options: 0
        )
        XCTAssertEqual(
            try FeedbackMailConfiguration.credentials(plistData: valid),
            FeedbackQQMailCredentials(
                senderAddress: "123456@qq.com",
                smtpAuthorizationCode: "authorization-code"
            )
        )

        let placeholder = try PropertyListSerialization.data(
            fromPropertyList: [
                "SenderAddress": "YOUR_QQ_EMAIL",
                "SMTPAuthorizationCode": "YOUR_QQ_SMTP_AUTHORIZATION_CODE"
            ],
            format: .xml,
            options: 0
        )
        XCTAssertThrowsError(
            try FeedbackMailConfiguration.credentials(plistData: placeholder)
        ) { error in
            XCTAssertEqual(
                error as? FeedbackSubmissionError,
                .configurationMissing
            )
        }
    }

    func testQQMailClientSendsFixedRecipientMIMEMessage() async throws {
        let transport = CapturingFeedbackSMTPTransport()
        let feedbackID = UUID()

        try await QQMailFeedbackClient(
            credentials: FeedbackQQMailCredentials(
                senderAddress: "123456@qq.com",
                smtpAuthorizationCode: "authorization-code"
            ),
            transport: transport
        ).submit(
            id: feedbackID,
            message: "  这是虚构反馈。  ",
            attachments: [
                PendingAttachment(
                    kind: .image,
                    imageData: Data("synthetic-image".utf8)
                )
            ]
        )
        let capturedDelivery = await transport.delivery
        let delivery = try XCTUnwrap(capturedDelivery)
        let sentMessage = String(data: delivery.message, encoding: .utf8)

        XCTAssertEqual(delivery.sender, "123456@qq.com")
        XCTAssertEqual(delivery.recipient, "hedonwang@gmail.com")
        XCTAssertEqual(delivery.authorizationCode, "authorization-code")
        XCTAssertTrue(
            sentMessage?.contains("From: 123456@qq.com\r\n") == true
        )
        XCTAssertTrue(
            sentMessage?.contains("To: hedonwang@gmail.com\r\n") == true
        )
        XCTAssertTrue(
            sentMessage?.contains(
                "Message-ID: <\(feedbackID.uuidString.lowercased())@soma.feedback>"
            ) == true
        )
        XCTAssertTrue(
            sentMessage?.contains(
                Data("这是虚构反馈。".utf8).base64EncodedString()
            ) == true
        )
        XCTAssertTrue(sentMessage?.contains("filename=\"feedback-1.jpg\"") == true)
    }

    @MainActor
    func testAgentFeedbackToolSendsCurrentSourceTextAndMedia() async throws {
        let transport = CapturingFeedbackSMTPTransport()
        let feedbackID = UUID()
        let imageURL = FileManager.default.temporaryDirectory
            .appending(path: "soma-agent-feedback-\(UUID().uuidString).jpg")
        try Data("synthetic-current-image".utf8).write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let result = try await AgentFeedbackTool.submit(
            id: feedbackID,
            sourceText: "  提交反馈：虚构按钮无法点击。  ",
            mediaAttachments: [
                MediaAttachmentReference(
                    kind: .image,
                    path: "PrivateMedia/current-image.jpg"
                )
            ],
            credentials: FeedbackQQMailCredentials(
                senderAddress: "123456@qq.com",
                smtpAuthorizationCode: "authorization-code"
            ),
            transport: transport,
            mediaURL: { path in
                path == "PrivateMedia/current-image.jpg" ? imageURL : nil
            }
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.observation, "反馈已发送。")
        let capturedDelivery = await transport.delivery
        let delivery = try XCTUnwrap(capturedDelivery)
        let sentMessage = try XCTUnwrap(
            String(data: delivery.message, encoding: .utf8)
        )
        XCTAssertTrue(sentMessage.contains(
            Data("提交反馈：虚构按钮无法点击。".utf8).base64EncodedString()
        ))
        XCTAssertTrue(sentMessage.contains(
            Data("synthetic-current-image".utf8).base64EncodedString()
        ))
    }

    @MainActor
    func testAgentFeedbackToolReturnsFailureWhenDeliveryFails() async throws {
        let result = try await AgentFeedbackTool.submit(
            id: UUID(),
            sourceText: "提交一条虚构反馈",
            mediaAttachments: [],
            credentials: FeedbackQQMailCredentials(
                senderAddress: "123456@qq.com",
                smtpAuthorizationCode: "authorization-code"
            ),
            transport: FailingFeedbackSMTPTransport()
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.observation, "反馈暂时无法发送，请稍后重试。")
    }

    func testTextAndMediaOnlyFeedbackAreBothAccepted() throws {
        XCTAssertEqual(
            try FeedbackSubmissionPolicy.validatedMessage(
                "  希望增加虚构功能。  ",
                attachments: []
            ),
            "希望增加虚构功能。"
        )
        XCTAssertEqual(
            try FeedbackSubmissionPolicy.validatedMessage(
                "   ",
                attachments: [
                    PendingAttachment(
                        kind: .image,
                        imageData: Data([0x01])
                    )
                ]
            ),
            ""
        )
    }

    func testSuccessfulReplyFeedbackAcknowledgesThenCollapses() {
        XCTAssertEqual(
            FeedbackSuccessPresentationPolicy.action(isEmbedded: true),
            .acknowledgeThenCollapse
        )
        XCTAssertEqual(
            FeedbackSuccessPresentationPolicy.action(isEmbedded: false),
            .acknowledgeInPlace
        )
    }

    func testAssistantReplyFeedbackIncludesRatingAndBoundedDiagnostics() throws {
        let context = try AssistantFeedbackContext(
            messageID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000101")),
            turnID: UUID(uuidString: "00000000-0000-0000-0000-000000000102"),
            messageDate: Date(timeIntervalSince1970: 1_700_000_000),
            userText: "虚构提问",
            assistantText: "虚构回复",
            originalMediaSummary: "图片 1",
            assistantStatus: "失败",
            jobID: UUID(uuidString: "00000000-0000-0000-0000-000000000103"),
            backend: "local",
            jobState: "waitingForUser",
            submissionAttemptCount: 1,
            selectedSkillID: "fictional-skill",
            selectedShortcutID: "fictional-shortcut",
            traceID: UUID(uuidString: "00000000-0000-0000-0000-000000000104"),
            provider: "Fictional Provider",
            model: "fictional-model",
            traceStatus: "失败",
            spans: [
                AssistantFeedbackSpanSummary(
                    kind: "tool",
                    title: "虚构工具",
                    status: "failed",
                    durationMilliseconds: 42,
                    error: "虚构错误 Authorization: Bearer fictional-secret-value"
                )
            ],
            appVersion: "0.0.0-test",
            buildNumber: "1",
            operatingSystem: "Test OS"
        )

        let envelope = AssistantFeedbackEnvelope.compose(
            userFeedback: "这里不符合预期",
            rating: 2,
            context: context
        )

        XCTAssertTrue(envelope.contains("评分：2 / 5"))
        XCTAssertTrue(envelope.contains("对应提问：\n虚构提问"))
        XCTAssertTrue(envelope.contains("对应 AI 回复：\n虚构回复"))
        XCTAssertTrue(envelope.contains("job_state=waitingForUser"))
        XCTAssertTrue(envelope.contains("虚构工具"))
        XCTAssertFalse(envelope.contains("fictional-secret-value"))
        XCTAssertTrue(envelope.contains("[已脱敏]"))
        XCTAssertLessThanOrEqual(
            envelope.count,
            FeedbackSubmissionPolicy.maximumMessageCharacters
        )
    }

    @MainActor
    func testAssistantFeedbackContextLoadsOnDemandFromMessageID() throws {
        let schema = Schema([
            CoachMessage.self,
            AgentJob.self,
            AgentTrace.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let sessionID = UUID()
        let turnID = UUID()
        let userMessage = CoachMessage(
            sessionID: sessionID,
            isFromCoach: false,
            text: "虚构提问",
            mediaAttachments: [
                MediaAttachmentReference(
                    kind: .image,
                    path: "PrivateMedia/fictional.jpg"
                )
            ],
            turnID: turnID
        )
        let trace = AgentTrace(
            provider: "Fictional Provider",
            model: "fictional-model",
            endpoint: "https://example.invalid/v1",
            dataSpaceRaw: DataSpace.personal.rawValue,
            userInput: "不应进入反馈",
            contextSnapshot: "不应进入反馈",
            mediaKind: .image,
            imageCount: 1,
            turnID: turnID
        )
        trace.apply(.span(AgentTraceSpan(
            kind: .model,
            title: "虚构模型步骤",
            status: .succeeded,
            startedAt: .now,
            endedAt: .now
        )))
        let assistantMessage = CoachMessage(
            sessionID: sessionID,
            isFromCoach: true,
            text: "虚构回复",
            agentTraceID: trace.id,
            agentStatus: .succeeded,
            turnID: turnID,
            attemptNumber: 1
        )
        modelContext.insert(userMessage)
        modelContext.insert(trace)
        modelContext.insert(assistantMessage)
        try modelContext.save()

        let context = try XCTUnwrap(
            AssistantFeedbackContextBuilder.make(
                messageID: assistantMessage.id,
                in: modelContext,
                bundle: Bundle(for: Self.self),
                operatingSystem: "Test OS"
            )
        )

        XCTAssertEqual(context.userText, "虚构提问")
        XCTAssertEqual(context.assistantText, "虚构回复")
        XCTAssertEqual(context.originalMediaSummary, "图片 1")
        XCTAssertEqual(context.traceID, trace.id)
        XCTAssertEqual(context.spans.map(\.title), ["虚构模型步骤"])
    }

    func testEmptyFeedbackAndUnreadableMediaAreRejected() {
        XCTAssertThrowsError(
            try FeedbackSubmissionPolicy.validatedMessage(
                "  ",
                attachments: []
            )
        ) { error in
            XCTAssertEqual(error as? FeedbackSubmissionError, .empty)
        }
        XCTAssertThrowsError(
            try FeedbackSubmissionPolicy.validatedMessage(
                "虚构反馈",
                attachments: [PendingAttachment(kind: .image)]
            )
        ) { error in
            XCTAssertEqual(
                error as? FeedbackSubmissionError,
                .attachmentUnavailable
            )
        }
    }

    func testMessageCountAttachmentCountAndByteLimitsAreEnforced() {
        XCTAssertThrowsError(
            try FeedbackSubmissionPolicy.validatedMessage(
                String(
                    repeating: "字",
                    count: FeedbackSubmissionPolicy.maximumMessageCharacters + 1
                ),
                attachments: []
            )
        ) { error in
            XCTAssertEqual(error as? FeedbackSubmissionError, .messageTooLong)
        }

        let tooMany = (0 ... FeedbackSubmissionPolicy.maximumAttachmentCount)
            .map { _ in
                PendingAttachment(kind: .image, imageData: Data([0x01]))
            }
        XCTAssertThrowsError(
            try FeedbackSubmissionPolicy.validatedMessage(
                "虚构反馈",
                attachments: tooMany
            )
        ) { error in
            XCTAssertEqual(
                error as? FeedbackSubmissionError,
                .tooManyAttachments
            )
        }

        XCTAssertThrowsError(
            try FeedbackSubmissionPolicy.validatedMessage(
                "虚构反馈",
                attachments: [
                    PendingAttachment(
                        kind: .image,
                        imageData: Data(
                            repeating: 0x01,
                            count: FeedbackSubmissionPolicy.maximumAttachmentBytes + 1
                        )
                    )
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? FeedbackSubmissionError,
                .attachmentsTooLarge
            )
        }
    }

    func testSMTPReplyWaitsForTerminatingLine() {
        XCTAssertNil(
            FeedbackSMTPReply(data: Data("250-smtp.qq.com\r\n250-PIPELINING\r\n".utf8))
        )
        XCTAssertEqual(
            FeedbackSMTPReply(
                data: Data("250-smtp.qq.com\r\n250 AUTH LOGIN PLAIN\r\n".utf8)
            )?.code,
            250
        )
        XCTAssertEqual(FeedbackSMTPReply.error(for: 535), .authenticationFailed)
        XCTAssertEqual(FeedbackSMTPReply.error(for: 421), .networkUnavailable)
    }
}

private actor CapturingFeedbackSMTPTransport: FeedbackSMTPTransport {
    struct Delivery: Sendable {
        let message: Data
        let sender: String
        let recipient: String
        let authorizationCode: String
    }

    private(set) var delivery: Delivery?

    func send(
        message: Data,
        sender: String,
        recipient: String,
        authorizationCode: String
    ) {
        delivery = Delivery(
            message: message,
            sender: sender,
            recipient: recipient,
            authorizationCode: authorizationCode
        )
    }
}

private struct FailingFeedbackSMTPTransport: FeedbackSMTPTransport {
    func send(
        message _: Data,
        sender _: String,
        recipient _: String,
        authorizationCode _: String
    ) async throws {
        throw URLError(.notConnectedToInternet)
    }
}
