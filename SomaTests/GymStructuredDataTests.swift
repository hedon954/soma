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
            in: context
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<GymProfile>()).count, 1)
        XCTAssertTrue(office.isCurrent)
        XCTAssertTrue(try context.fetch(FetchDescriptor<GymEquipment>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<GymMedia>()).isEmpty)
    }

    @MainActor
    func testActivatingGymClearsCurrentFlagPastDisplayLimit() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: GymProfile.self,
            GymEquipment.self,
            GymMedia.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        var gyms: [GymProfile] = []
        for index in 0 ... 100 {
            let gym = GymProfile(
                name: "虚构健身房 \(index)",
                isCurrent: index == 100
            )
            gym.createdAt = baseDate.addingTimeInterval(Double(index))
            context.insert(gym)
            gyms.append(gym)
        }
        try context.save()

        StructuredDataStore.activateGym(gyms[0], in: context)

        let stored = try context.fetch(FetchDescriptor<GymProfile>())
        XCTAssertEqual(stored.filter(\.isCurrent).map(\.id), [gyms[0].id])
    }
}
