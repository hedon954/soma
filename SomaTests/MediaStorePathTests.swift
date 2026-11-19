@testable import Soma
import XCTest

final class MediaStorePathTests: XCTestCase {
    #if targetEnvironment(simulator)
        @MainActor
        func testInMemoryContainersDoNotRunPersistedMediaCleanup() async throws {
            let data = Data("synthetic-media-\(UUID())".utf8)
            let path = try MediaStore.saveRestoredMedia(data, fileExtension: "bin")
            defer { MediaStore.removeStoredFile(at: path) }
            let suiteName = "MediaStorePathTests.\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let spaces = DataSpaceController(isStoredInMemoryOnly: true)
            try await MediaMaintenance().reclaimOrphansIfNeeded(
                personalContainer: XCTUnwrap(spaces.personalContainer),
                demoContainer: XCTUnwrap(spaces.demoContainer),
                defaults: defaults
            )

            let media = try XCTUnwrap(MediaStore.url(at: path))
            XCTAssertEqual(try Data(contentsOf: media), data)
            XCTAssertFalse(defaults.bool(forKey: MediaMaintenance.currentCleanupKey))
        }
    #endif

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
