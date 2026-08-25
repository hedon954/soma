@testable import Soma
import XCTest

final class MediaStorePathTests: XCTestCase {
    func testMediaStoreUsesRelocationSafeRelativePath() throws {
        let image = try XCTUnwrap(UIImage(systemName: "dumbbell.fill"))
        let data = try XCTUnwrap(image.pngData())

        let path = try MediaStore.saveImage(data)
        defer { MediaStore.removeStoredFile(at: path) }

        XCTAssertTrue(path.hasPrefix("PrivateMedia/"))
        XCTAssertFalse(path.hasPrefix("/"))
        XCTAssertNotNil(MediaStore.image(at: path))
    }
}
