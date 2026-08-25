@testable import Soma
import SwiftData
import XCTest

final class MediaMaintenanceTests: XCTestCase {
    func testContentAddressedMediaUsesIndependentHardLinks() throws {
        let data = Data("fictional-shared-media".utf8)
        let firstPath = try MediaStore.saveRestoredMedia(data, fileExtension: "bin")
        let secondPath = try MediaStore.saveRestoredMedia(data, fileExtension: "bin")
        defer {
            MediaStore.removeStoredFile(at: firstPath)
            MediaStore.removeStoredFile(at: secondPath)
        }

        XCTAssertNotEqual(firstPath, secondPath)
        let firstURL = try XCTUnwrap(MediaStore.url(at: firstPath))
        let secondURL = try XCTUnwrap(MediaStore.url(at: secondPath))
        let firstIdentifier = try firstURL.resourceValues(
            forKeys: [.fileResourceIdentifierKey]
        ).fileResourceIdentifier
        let secondIdentifier = try secondURL.resourceValues(
            forKeys: [.fileResourceIdentifierKey]
        ).fileResourceIdentifier
        XCTAssertEqual(
            String(describing: firstIdentifier),
            String(describing: secondIdentifier)
        )

        XCTAssertTrue(MediaStore.removeStoredFile(at: firstPath))
        XCTAssertEqual(try Data(contentsOf: secondURL), data)
    }

    @MainActor
    func testReferenceScanUnionsPersonalAndDemoMedia() throws {
        let suiteName = "MediaMaintenanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )

        let personalPath = "PrivateMedia/personal-fixture.jpg"
        let demoPath = "PrivateMedia/demo-fixture.mov"
        spaces.personalContainer.mainContext.insert(MealEntry(
            mealType: .lunch,
            title: "虚构午餐",
            mediaAttachments: [.init(kind: .image, path: personalPath)]
        ))
        spaces.demoContainer.mainContext.insert(BodyEntry(
            notes: "虚构体态",
            mediaAttachments: [.init(kind: .video, path: demoPath)]
        ))
        try spaces.personalContainer.mainContext.save()
        try spaces.demoContainer.mainContext.save()

        let retained = try MediaReferenceStore.referencedPaths(
            in: spaces.personalContainer
        ).union(MediaReferenceStore.referencedPaths(in: spaces.demoContainer))

        XCTAssertEqual(retained, [personalPath, demoPath])
    }

    func testOrphanSelectionUsesRelocatableFileNames() {
        let stored: Set = [
            "PrivateMedia/shared.jpg",
            "PrivateMedia/orphan.mov"
        ]
        let retained: Set = [
            "/old/device/container/PrivateMedia/shared.jpg"
        ]

        XCTAssertEqual(
            MediaStore.orphanedStoredPaths(stored, retaining: retained),
            ["PrivateMedia/orphan.mov"]
        )
    }

    func testCancelledCleanupLeavesFilesForTheNextPass() throws {
        let path = try MediaStore.saveRestoredMedia(
            Data("fictional-cancelled-cleanup".utf8),
            fileExtension: "bin"
        )
        defer { MediaStore.removeStoredFile(at: path) }

        let removed = MediaStore.removeOrphans(
            retaining: [],
            shouldCancel: { true }
        )

        XCTAssertEqual(removed, 0)
        XCTAssertNotNil(MediaStore.url(at: path))
    }
}
