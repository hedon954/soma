@testable import Soma
import XCTest

final class FoldedMediaLayoutTests: XCTestCase {
    func testFoldedMediaLayoutPreservesCommonAspectRatiosInsideBounds() {
        XCTAssertEqual(
            FoldedMediaLayout.cardHeight(forAspectRatio: 3 / 4),
            FoldedMediaLayout.cardWidth / (3 / 4),
            accuracy: 0.001
        )
        XCTAssertEqual(
            FoldedMediaLayout.cardHeight(forAspectRatio: 3 / 2),
            FoldedMediaLayout.minimumHeight,
            accuracy: 0.001
        )
        XCTAssertEqual(
            FoldedMediaLayout.cardHeight(forAspectRatio: 1 / 4),
            FoldedMediaLayout.maximumHeight,
            accuracy: 0.001
        )
        XCTAssertEqual(FoldedMediaLayout.scale(forLayer: 0), 1)
        XCTAssertEqual(
            FoldedMediaLayout.scale(forLayer: 1),
            0.90,
            accuracy: 0.001
        )
        XCTAssertEqual(
            FoldedMediaLayout.scale(forLayer: 2),
            0.80,
            accuracy: 0.001
        )
        XCTAssertEqual(
            FoldedMediaLayout.foldedFrontSize(forAspectRatio: 3 / 4),
            FoldedMediaLayout.portraitCardSize
        )
        XCTAssertEqual(
            FoldedMediaLayout.foldedFrontSize(forAspectRatio: 1),
            FoldedMediaLayout.squareCardSize
        )
        XCTAssertEqual(
            FoldedMediaLayout.foldedFrontSize(forAspectRatio: 3 / 2),
            FoldedMediaLayout.landscapeCardSize
        )
        let frontSize = FoldedMediaLayout.portraitCardSize
        let middleSize = FoldedMediaLayout.scaledSize(
            forLayer: 1,
            frontSize: frontSize
        )
        XCTAssertEqual(
            middleSize.width,
            frontSize.width * 0.9,
            accuracy: 0.001
        )
        XCTAssertEqual(
            middleSize.height,
            frontSize.height * 0.9,
            accuracy: 0.001
        )
        let backSize = FoldedMediaLayout.scaledSize(
            forLayer: 2,
            frontSize: frontSize
        )
        XCTAssertEqual(
            backSize.width,
            frontSize.width * 0.8,
            accuracy: 0.001
        )
        XCTAssertEqual(FoldedMediaLayout.rotation(forLayer: 0), 0)
        XCTAssertEqual(
            FoldedMediaLayout.rotation(forLayer: 2),
            FoldedMediaLayout.layerRotationStep * 2
        )
        XCTAssertGreaterThan(
            FoldedMediaLayout.rotation(forLayer: 1),
            0
        )
        XCTAssertEqual(
            FoldedMediaLayout.targetExposure(
                forLayer: 1,
                frontWidth: frontSize.width
            ),
            frontSize.width * 0.10,
            accuracy: 0.001
        )
        XCTAssertEqual(
            FoldedMediaLayout.targetExposure(
                forLayer: 2,
                frontWidth: frontSize.width
            ),
            frontSize.width * 0.165,
            accuracy: 0.001
        )
        XCTAssertEqual(
            FoldedMediaLayout.rightEdge(
                forLayer: 1,
                size: FoldedMediaLayout.scaledSize(
                    forLayer: 1,
                    frontSize: frontSize
                ),
                frontSize: frontSize
            ),
            frontSize.width +
                FoldedMediaLayout.targetExposure(
                    forLayer: 1,
                    frontWidth: frontSize.width
                ),
            accuracy: 0.001
        )
        XCTAssertEqual(
            FoldedMediaLayout.rightEdge(
                forLayer: 2,
                size: backSize,
                frontSize: frontSize
            ),
            frontSize.width +
                FoldedMediaLayout.targetExposure(
                    forLayer: 2,
                    frontWidth: frontSize.width
                ),
            accuracy: 0.001
        )
        XCTAssertEqual(
            FoldedMediaLayout.stackOverflowWidth(
                frontWidth: frontSize.width
            ),
            FoldedMediaLayout.targetExposure(
                forLayer: 2,
                frontWidth: frontSize.width
            ),
            accuracy: 0.001
        )
    }
}

