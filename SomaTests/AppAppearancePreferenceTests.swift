@testable import Soma
import XCTest

final class AppAppearancePreferenceTests: XCTestCase {
    func testUnknownStoredValueFallsBackToSystem() {
        XCTAssertEqual(AppAppearancePreference.stored("future-value"), .system)
    }

    func testPreferredColorSchemeMapping() {
        XCTAssertNil(AppAppearancePreference.system.preferredColorScheme)
        XCTAssertEqual(AppAppearancePreference.light.preferredColorScheme, .light)
        XCTAssertEqual(AppAppearancePreference.dark.preferredColorScheme, .dark)
    }

    func testEveryPreferenceRoundTripsThroughUserDefaults() throws {
        let suiteName = "AppAppearancePreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for preference in AppAppearancePreference.allCases {
            defaults.set(preference.rawValue, forKey: AppAppearancePreference.defaultsKey)
            XCTAssertEqual(
                AppAppearancePreference.stored(
                    defaults.string(forKey: AppAppearancePreference.defaultsKey) ?? ""
                ),
                preference
            )
        }
    }

    func testRootAndMediaViewerPoliciesStayIndependent() {
        XCTAssertNil(
            AppAppearancePolicy.rootColorScheme(
                storedRawValue: AppAppearancePreference.system.rawValue
            )
        )
        XCTAssertEqual(
            AppAppearancePolicy.rootColorScheme(
                storedRawValue: AppAppearancePreference.light.rawValue
            ),
            .light
        )
        XCTAssertEqual(
            AppAppearancePolicy.rootColorScheme(
                storedRawValue: AppAppearancePreference.dark.rawValue
            ),
            .dark
        )
        XCTAssertEqual(AppAppearancePolicy.mediaViewerColorScheme, .dark)
    }
}
