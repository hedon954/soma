@testable import Soma
import UIKit
import XCTest

final class ChatTextSelectionStyleTests: XCTestCase {
    func testUserBubbleSelectionTintUsesHighContrastSystemForeground() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let actual = ChatTextSelectionStyle.tintColor.resolvedColor(with: traits)
            let expected = UIColor.label.resolvedColor(with: traits)

            XCTAssertEqual(actual, expected)
        }
    }
}
