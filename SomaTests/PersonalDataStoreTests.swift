@testable import Soma
import SwiftData
import XCTest

final class PersonalDataStoreTests: XCTestCase {
    @MainActor
    func testClearDeletesOnlyPersonalModelsAndUnsharedMedia() throws {
        for storedPath in MediaStore.allStoredPaths() {
            MediaStore.removeStoredFile(at: storedPath)
        }
        let suiteName = "PersonalDataStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let sharedPath = try MediaStore.saveRestoredMedia(
            Data("shared".utf8),
            fileExtension: "jpg"
        )
        let personalOnlyPath = try MediaStore.saveRestoredMedia(
            Data("personal".utf8),
            fileExtension: "jpg"
        )
        let legacyAbsoluteSharedPath = try XCTUnwrap(
            MediaStore.url(at: sharedPath)
        ).path
        defer {
            MediaStore.removeStoredFile(at: sharedPath)
            MediaStore.removeStoredFile(at: personalOnlyPath)
        }
        let personalContext = spaces.personalContainer.mainContext
        personalContext.insert(MealEntry(
            mealType: .lunch,
            title: "个人午餐",
            calories: 500,
            protein: 30,
            carbs: 50,
            fat: 15,
            mediaAttachments: [
                MediaAttachmentReference(kind: .image, path: legacyAbsoluteSharedPath),
                MediaAttachmentReference(kind: .image, path: personalOnlyPath)
            ]
        ))
        try personalContext.save()
        let demoContext = spaces.demoContainer.mainContext
        demoContext.insert(BodyEntry(
            notes: "演示",
            mediaAttachments: [
                MediaAttachmentReference(kind: .image, path: sharedPath)
            ]
        ))
        try demoContext.save()

        let result = try PersonalDataStore.clear(
            personalContext: personalContext,
            demoContext: demoContext
        )

        XCTAssertEqual(result.deletedModelCount, 1)
        XCTAssertEqual(result.deletedMediaCount, 1)
        XCTAssertTrue(try personalContext.fetch(FetchDescriptor<MealEntry>()).isEmpty)
        XCTAssertEqual(try demoContext.fetch(FetchDescriptor<BodyEntry>()).count, 1)
        XCTAssertNotNil(MediaStore.url(at: sharedPath))
        XCTAssertNil(MediaStore.url(at: personalOnlyPath))
    }
}
