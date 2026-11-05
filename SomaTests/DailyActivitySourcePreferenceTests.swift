import Foundation
@testable import Soma
import XCTest

final class DailyActivitySourcePreferenceTests: XCTestCase {
    func testDefaultIsAppleAndVisibleOptionsHideCOROSWithoutSamples() throws {
        let suiteName = "DailyActivitySourcePreferenceTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        XCTAssertEqual(DailyActivitySourcePreference.stored(in: suite), .apple)
        XCTAssertEqual(
            DailyActivitySourcePreference.visibleOptions(corosAvailable: false),
            [.apple, .maxSteps]
        )
        XCTAssertEqual(
            DailyActivitySourcePreference.visibleOptions(corosAvailable: true),
            [.apple, .coros, .maxSteps]
        )
    }

    func testPersistedCOROSFallsBackAndDoesNotAutoRestore() throws {
        let suiteName = "DailyActivitySourcePreferenceTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        DailyActivitySourcePreference.set(.coros, in: suite)
        let effective = DailyActivitySourcePreference.resolveEffective(
            stored: .coros,
            corosAvailable: false,
            defaults: suite
        )
        XCTAssertEqual(effective, .apple)
        XCTAssertEqual(DailyActivitySourcePreference.stored(in: suite), .apple)
        // COROS 样本回来后不自动切回
        let again = DailyActivitySourcePreference.resolveEffective(
            stored: DailyActivitySourcePreference.stored(in: suite),
            corosAvailable: true,
            defaults: suite
        )
        XCTAssertEqual(again, .apple)
    }

    func testCOROSMatcherUsesBundleOrName() {
        XCTAssertTrue(DailyActivitySourceMatcher.isCOROS(.init(name: "COROS", bundleIdentifier: "com.coros.app")))
        XCTAssertTrue(DailyActivitySourceMatcher.isCOROS(.init(name: "高驰", bundleIdentifier: "example.other")))
        XCTAssertTrue(DailyActivitySourceMatcher.isCOROS(.init(name: "Watch", bundleIdentifier: "com.foo.coros.sync")))
        XCTAssertFalse(DailyActivitySourceMatcher.isCOROS(.init(name: "iPhone", bundleIdentifier: "com.apple.health")))
    }
}

final class DailyActivityPackageSelectorTests: XCTestCase {
    private var key: DailyActivityDayKey {
        DailyActivityDayKey(date: Date(timeIntervalSince1970: 1_735_689_600), calendar: .current)
    }

    private func apple(steps: Double?, distance: Double? = 1000, energy: Double? = 100) -> DailyActivityCandidatePackage {
        .init(
            key: key,
            winningSource: .appleHealth,
            steps: steps,
            walkingRunningDistance: distance,
            activeEnergy: energy,
            readAt: key.start
        )
    }

    private func coros(steps: Double?, distance: Double? = 2000, energy: Double? = 200) -> DailyActivityCandidatePackage {
        .init(
            key: key,
            winningSource: .coros,
            steps: steps,
            walkingRunningDistance: distance,
            activeEnergy: energy,
            readAt: key.start,
            sourceByMetric: [
                .steps: .init(sources: [.init(name: "COROS", bundleIdentifier: "com.coros.app")], readAt: key.start)!
            ]
        )
    }

    func testApplePreferenceDoesNotReselect() {
        let selected = DailyActivityPackageSelector.select(
            preference: .apple,
            apple: apple(steps: 1000),
            coros: coros(steps: 9000)
        )
        XCTAssertEqual(selected?.winningSource, .appleHealth)
        XCTAssertEqual(selected?.steps, 1000)
    }

    func testCOROSPreferenceUsesCOROSPackage() {
        let selected = DailyActivityPackageSelector.select(
            preference: .coros,
            apple: apple(steps: 1000),
            coros: coros(steps: 9000)
        )
        XCTAssertEqual(selected?.winningSource, .coros)
        XCTAssertEqual(selected?.steps, 9000)
        XCTAssertEqual(selected?.walkingRunningDistance, 2000)
    }

    func testCOROSMissingPackageFallsBackToApple() {
        let selected = DailyActivityPackageSelector.select(
            preference: .coros,
            apple: apple(steps: 1000),
            coros: nil
        )
        XCTAssertEqual(selected?.winningSource, .appleHealth)
        XCTAssertEqual(selected?.steps, 1000)
    }

    func testIncompleteCOROSWithoutStepsIsNotUsable() {
        XCTAssertFalse(coros(steps: nil).isUsable)
        let selected = DailyActivityPackageSelector.select(
            preference: .coros,
            apple: apple(steps: 1000),
            coros: coros(steps: nil)
        )
        XCTAssertEqual(selected?.winningSource, .appleHealth)
    }

    func testMaxStepsPicksLargerWholePackageWithoutMixing() {
        let selected = DailyActivityPackageSelector.select(
            preference: .maxSteps,
            apple: apple(steps: 8000, distance: 111, energy: 11),
            coros: coros(steps: 9000, distance: 222, energy: 22)
        )
        XCTAssertEqual(selected?.winningSource, .coros)
        XCTAssertEqual(selected?.walkingRunningDistance, 222)
        XCTAssertEqual(selected?.activeEnergy, 22)
    }

    func testMaxStepsTieBreaksPreferCOROS() {
        let selected = DailyActivityPackageSelector.select(
            preference: .maxSteps,
            apple: apple(steps: 9000, distance: 111, energy: 11),
            coros: coros(steps: 9000, distance: 222, energy: 22)
        )
        XCTAssertEqual(selected?.winningSource, .coros)
        XCTAssertEqual(selected?.walkingRunningDistance, 222)
    }

    func testMaxStepsWithoutCOROSUsesApple() {
        let selected = DailyActivityPackageSelector.select(
            preference: .maxSteps,
            apple: apple(steps: 1000),
            coros: nil
        )
        XCTAssertEqual(selected?.winningSource, .appleHealth)
    }

    func testCOROSPackageBuildsFromContributionsWithoutBorrowing() {
        let contributions: [DailyActivityMetricKind: [DailyActivitySourceContribution]] = [
            .steps: [
                .init(source: .init(name: "COROS", bundleIdentifier: "com.coros.app"), value: 5000),
                .init(source: .init(name: "iPhone", bundleIdentifier: "com.apple.health"), value: 9999)
            ],
            .walkingRunningDistance: [
                .init(source: .init(name: "iPhone", bundleIdentifier: "com.apple.health"), value: 8000)
            ],
            .activeEnergy: [
                .init(source: .init(name: "COROS", bundleIdentifier: "com.coros.app"), value: 300)
            ]
        ]
        let package = DailyActivityPackageSelector.corosPackage(
            key: key,
            contributions: contributions,
            readAt: key.start
        )
        XCTAssertEqual(package?.steps, 5000)
        XCTAssertNil(package?.walkingRunningDistance)
        XCTAssertEqual(package?.activeEnergy, 300)
        XCTAssertEqual(package?.winningSource, .coros)
    }

    func testIsDailyActivityUsesDailyPrefixRegardlessOfSource() {
        let corosDaily = WorkoutEntry(
            date: key.start,
            exercise: "日常活动",
            externalSource: "coros",
            externalID: "daily:2026-11-05"
        )
        XCTAssertTrue(corosDaily.isDailyActivity)
        let legacy = WorkoutEntry(
            date: key.start,
            exercise: "日常活动",
            externalSource: "appleHealth",
            externalID: "daily:2026-11-04"
        )
        XCTAssertTrue(legacy.isDailyActivity)
        let training = WorkoutEntry(date: key.start, exercise: "深蹲")
        XCTAssertFalse(training.isDailyActivity)
    }
}
