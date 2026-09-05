@testable import Soma
import SwiftData
import XCTest

@MainActor
final class EnergyLifestyleStorageTests: XCTestCase {
    func testLegacyProfileArchiveWithoutFieldDecodesAsUnconfigured() throws {
        let model = UserProfile(displayName: "测试用户")
        let encoded = try JSONEncoder().encode(UserProfileDTO(model))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "energyBaselinesData")
        let oldJSON = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(UserProfileDTO.self, from: oldJSON)
        XCTAssertNil(decoded.energyBaselinesData)
        XCTAssertEqual(try EnergyLifestyleStorage.decode(decoded.makeModel().energyBaselinesData), [])
    }

    func testArchiveRoundTripPreservesEffectiveDatesAndValues() throws {
        let baseline = EnergyLifestyleBaseline(effectiveFrom: Date(timeIntervalSince1970: 100), factor: 1.45, label: "本人确认")
        let model = UserProfile()
        model.energyBaselinesData = try JSONEncoder().encode([baseline])
        let restored = try JSONDecoder().decode(UserProfileDTO.self, from: JSONEncoder().encode(UserProfileDTO(model))).makeModel()
        XCTAssertEqual(try EnergyLifestyleStorage.decode(restored.energyBaselinesData), [baseline])
    }

    func testCorruptBaselineIsNotSilentlyReplacedWithDefault() {
        XCTAssertThrowsError(try EnergyLifestyleStorage.decode(Data("broken".utf8)))
    }

    func testSavingNewBaselinePreservesOlderHistoryAndSpaceIsolation() throws {
        let container = try ModelContainer(for: UserProfile.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let other = try ModelContainer(for: UserProfile.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let first = Date(timeIntervalSince1970: 86400)
        let second = Date(timeIntervalSince1970: 172_800)
        try EnergyLifestyleStore.save(factor: 1.4, label: "久坐", effectiveFrom: first, in: container.mainContext, now: second, calendar: calendar)
        try EnergyLifestyleStore.save(factor: 1.6, label: "走动较多", effectiveFrom: second, in: container.mainContext, now: second, calendar: calendar)
        let profile = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertEqual(try EnergyLifestyleStorage.decode(profile.energyBaselinesData).map(\.factor), [1.4, 1.6])
        XCTAssertEqual(try other.mainContext.fetchCount(FetchDescriptor<UserProfile>()), 0)
        XCTAssertThrowsError(try EnergyLifestyleStore.save(
            factor: .infinity, label: "错误", effectiveFrom: first, in: container.mainContext, now: second, calendar: calendar
        ))
        XCTAssertEqual(try EnergyLifestyleStorage.decode(profile.energyBaselinesData).count, 2)
    }
}
