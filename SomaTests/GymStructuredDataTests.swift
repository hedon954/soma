@testable import Soma
import SwiftData
import XCTest

final class GymStructuredDataTests: XCTestCase {
    func testOnlySelectedGymBecomesCurrent() {
        let home = GymProfile(name: "家里", isCurrent: true)
        let office = GymProfile(name: "公司")

        GymSelection.activate(office, among: [home, office])

        XCTAssertFalse(home.isCurrent)
        XCTAssertTrue(office.isCurrent)
        XCTAssertEqual(GymSelection.current(in: [home, office])?.id, office.id)
    }

    @MainActor
    func testDeletingGymCascadesStructuredDataAndSelectsNextGym() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ExternalSyncCursor.self,
            UserProfile.self,
            GymProfile.self,
            GymEquipment.self,
            GymMedia.self,
            MealEntry.self,
            BodyEntry.self,
            WorkoutEntry.self,
            CoachMessage.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let home = GymProfile(name: "家里", isCurrent: true)
        let office = GymProfile(name: "公司")
        let rack = GymEquipment(
            gymID: home.id,
            name: "深蹲架",
            category: "力量",
            capabilities: "深蹲"
        )
        let photo = GymMedia(gymID: home.id, path: "PrivateMedia/gym.jpg")
        context.insert(home)
        context.insert(office)
        context.insert(rack)
        context.insert(photo)
        try context.save()

        StructuredDataStore.deleteGym(
            home,
            gyms: [home, office],
            equipment: [rack],
            media: [photo],
            in: context
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<GymProfile>()).count, 1)
        XCTAssertTrue(office.isCurrent)
        XCTAssertTrue(try context.fetch(FetchDescriptor<GymEquipment>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<GymMedia>()).isEmpty)
    }
}

