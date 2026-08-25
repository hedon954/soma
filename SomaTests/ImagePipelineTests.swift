@testable import Soma
import UIKit
import XCTest

final class ImagePipelineTests: XCTestCase {
    @MainActor
    func testDownsamplesLargeImageAndReadsMetadataAspectRatio() async throws {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 2400, height: 1200)
        )
        let data = try XCTUnwrap(renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
        })
        let path = try MediaStore.saveRestoredMedia(data, fileExtension: "jpg")
        defer { MediaStore.removeStoredFile(at: path) }

        let loadedImage = await ImagePipeline.shared.image(
            atStoredPath: path,
            maxPixelSize: 300
        )
        let image = try XCTUnwrap(loadedImage)
        let loadedRatio = await ImagePipeline.shared.aspectRatio(
            atStoredPath: path
        )
        let ratio = try XCTUnwrap(loadedRatio)

        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 300)
        XCTAssertEqual(ratio, 2, accuracy: 0.001)
    }

    func testMissingImageReturnsNilAndCacheCanBeCleared() async {
        let image = await ImagePipeline.shared.image(
            atStoredPath: "PrivateMedia/does-not-exist.jpg"
        )
        XCTAssertNil(image)
        await ImagePipeline.shared.removeAllCachedImages()
    }

    func testCorruptedImageReturnsNil() async throws {
        let path = try MediaStore.saveRestoredMedia(
            Data("not-an-image".utf8),
            fileExtension: "jpg"
        )
        defer { MediaStore.removeStoredFile(at: path) }

        let image = await ImagePipeline.shared.image(atStoredPath: path)
        let aspectRatio = await ImagePipeline.shared.aspectRatio(atStoredPath: path)

        XCTAssertNil(image)
        XCTAssertNil(aspectRatio)
    }
}
