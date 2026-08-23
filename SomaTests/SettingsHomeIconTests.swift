@testable import Soma
import UIKit
import XCTest

final class SettingsHomeIconTests: XCTestCase {
    func testEverySettingsHomeItemKeepsAValidDistinctSymbol() {
        let items = SettingsHomeItem.allCases

        XCTAssertEqual(Set(items.map(\.systemImage)).count, items.count)
        for item in items {
            XCTAssertNotNil(UIImage(systemName: item.systemImage), item.rawValue)
        }
    }

    func testSettingsHomeItemsUseAllFunctionalSemanticTones() {
        XCTAssertEqual(
            Set(SettingsHomeItem.allCases.map(\.tone)),
            Set(SettingsHomeIconTone.allCases)
        )
    }
}
