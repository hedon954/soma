@testable import Soma
import XCTest

final class MediaViewerPresentationTests: XCTestCase {
    func testZoomSourceIDsAreStableAttachmentIdentities() {
        let photo = MediaAttachmentReference(kind: .image, path: "media/demo-meal.jpg")
        XCTAssertEqual(photo.id, "image:media/demo-meal.jpg")
    }
}
