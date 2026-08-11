import Foundation
@testable import Soma
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
                .deliveryUnavailable
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
