@testable import Soma
import XCTest

final class FeedbackSubmissionTests: XCTestCase {
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
