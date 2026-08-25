@testable import Soma
import SwiftData
import XCTest

final class DataSpaceSelectionTests: XCTestCase {
    @MainActor
    func testDataSpacesAreIsolatedAndPersistSelection() throws {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )

        let demoContext = ModelContext(spaces.demoContainer)
        demoContext.insert(WorkoutEntry(exercise: "演示深蹲", sets: 4, reps: 8, weight: 60))
        try demoContext.save()

        let personalContext = ModelContext(spaces.personalContainer)
        XCTAssertEqual(
            try demoContext.fetch(FetchDescriptor<WorkoutEntry>()).count,
            1
        )
        XCTAssertTrue(
            try personalContext.fetch(FetchDescriptor<WorkoutEntry>()).isEmpty
        )

        spaces.select(.personal)

        XCTAssertEqual(spaces.activeSpace, .personal)
        XCTAssertEqual(
            defaults.string(forKey: DataSpaceController.defaultsKey),
            DataSpace.personal.rawValue
        )
    }
}

