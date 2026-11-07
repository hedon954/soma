@testable import Soma
import SwiftData
import XCTest

@MainActor
final class DailyTargetDeficitPersistenceTests: XCTestCase {
    func testLegacyProfileArchiveMissingPreferenceUses400() throws {
        let data = try JSONEncoder().encode(UserProfileDTO(UserProfile()))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "dailyTargetDeficitKilocalories")
        let decoded = try JSONDecoder().decode(UserProfileDTO.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.dailyTargetDeficitKilocalories)
        XCTAssertEqual(DailyTargetDeficit.resolve(decoded.makeModel().dailyTargetDeficitKilocalories), 400)
    }

    func testBackupRoundTripPreservesCustomAndExplicitZeroForBothGoals() throws {
        for goal in [FitnessGoal.fatLoss, .recomposition] {
            for value in [nil, 0.0, 625.5] as [Double?] {
                let profile = UserProfile(fitnessGoal: goal.rawValue)
                profile.dailyTargetDeficitKilocalories = value
                let data = try JSONEncoder().encode(UserProfileDTO(profile))
                let restored = try JSONDecoder().decode(UserProfileDTO.self, from: data).makeModel()
                XCTAssertEqual(restored.fitnessGoal, goal.rawValue)
                XCTAssertEqual(restored.dailyTargetDeficitKilocalories, value)
            }
        }
    }

    func testPreferenceSurvivesDiskReopenAndGoalChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("test.store"))
        do {
            let container = try ModelContainer(for: UserProfile.self, configurations: configuration)
            let profile = UserProfile(fitnessGoal: FitnessGoal.fatLoss.rawValue)
            profile.dailyTargetDeficitKilocalories = 625.5
            container.mainContext.insert(profile)
            try container.mainContext.save()
            profile.fitnessGoal = FitnessGoal.muscleGain.rawValue
            try container.mainContext.save()
        }
        let reopened = try ModelContainer(for: UserProfile.self, configurations: configuration)
        let profile = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertEqual(profile.dailyTargetDeficitKilocalories, 625.5)
        for goal in [FitnessGoal.recomposition, .fatLoss] {
            profile.fitnessGoal = goal.rawValue
            try reopened.mainContext.save()
            XCTAssertEqual(DailyTargetDeficit.resolve(profile.dailyTargetDeficitKilocalories), 625.5)
            XCTAssertEqual(NutritionTargetCalculator.targets(
                weightKG: nil, fitnessGoal: goal, totalKilocalories: 2200,
                dailyTargetDeficitKilocalories: profile.dailyTargetDeficitKilocalories
            ).calories, 1574.5)
        }
    }
}
