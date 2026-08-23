import Foundation
@testable import Soma
import XCTest

final class AppThemePaletteTests: XCTestCase {
    func testLightSemanticColorsMeetTextContrastOnPageSurface() {
        let foregrounds = [
            AppThemePalette.lightAccent,
            AppThemePalette.lightTraining,
            AppThemePalette.lightMeal,
            AppThemePalette.lightBody,
            AppThemePalette.lightTrend,
            AppThemePalette.lightConsistency,
            AppThemePalette.lightRecovery,
            AppThemePalette.lightVital,
            AppThemePalette.lightWarning
        ]

        for foreground in foregrounds {
            XCTAssertGreaterThanOrEqual(
                contrast(foreground, AppThemePalette.lightPage),
                4.5
            )
        }
    }

    func testDarkSemanticColorsMeetTextContrastOnCardSurface() {
        let foregrounds = [
            AppThemePalette.darkAccent,
            AppThemePalette.darkTraining,
            AppThemePalette.darkMeal,
            AppThemePalette.darkBody,
            AppThemePalette.darkTrend,
            AppThemePalette.darkConsistency,
            AppThemePalette.darkRecovery,
            AppThemePalette.darkVital,
            AppThemePalette.darkWarning
        ]

        for foreground in foregrounds {
            XCTAssertGreaterThanOrEqual(
                contrast(foreground, AppThemePalette.darkCard),
                4.5
            )
        }
    }

    func testDarkSemanticPaletteStaysUnchangedWhenLightAccentsAreCalibrated() {
        XCTAssertEqual(AppThemePalette.darkTraining, AppThemeRGB(hex: 0xFF922B))
        XCTAssertEqual(AppThemePalette.darkMeal, AppThemeRGB(hex: 0x24D77A))
        XCTAssertEqual(AppThemePalette.darkBody, AppThemeRGB(hex: 0x66B8F0))
        XCTAssertEqual(AppThemePalette.darkTrend, AppThemeRGB(hex: 0xB58CFF))
        XCTAssertEqual(AppThemePalette.darkConsistency, AppThemeRGB(hex: 0x31C9D1))
        XCTAssertEqual(AppThemePalette.darkRecovery, AppThemeRGB(hex: 0x6FD47A))
        XCTAssertEqual(AppThemePalette.darkVital, AppThemeRGB(hex: 0xFF6B5B))
        XCTAssertEqual(AppThemePalette.darkWarning, AppThemeRGB(hex: 0xF2C94C))
    }

    func testMonochromeFilledControlsUseInverseForeground() {
        let white = AppThemeRGB(hex: 0xFFFFFF)
        let black = AppThemeRGB(hex: 0x000000)
        let pairs = [
            (AppThemePalette.lightOnAccent, AppThemePalette.lightAccentEmphasis),
            (AppThemePalette.darkOnAccent, AppThemePalette.darkAccentEmphasis),
            (white, AppThemePalette.lightTrainingEmphasis),
            (white, AppThemePalette.darkTrainingEmphasis),
            (white, AppThemePalette.warningEmphasis)
        ]

        for (foreground, background) in pairs {
            XCTAssertGreaterThanOrEqual(contrast(foreground, background), 4.5)
        }
        XCTAssertEqual(AppThemePalette.lightAccent, black)
        XCTAssertEqual(AppThemePalette.darkAccent, white)
    }

    func testTrainingFilledControlsKeepWhiteForegroundReadable() {
        let white = AppThemeRGB(hex: 0xFFFFFF)
        let backgrounds = [
            AppThemePalette.lightTrainingEmphasis,
            AppThemePalette.darkTrainingEmphasis,
            AppThemePalette.warningEmphasis
        ]

        for background in backgrounds {
            XCTAssertGreaterThanOrEqual(contrast(white, background), 4.5)
        }
    }

    func testSurfaceLuminanceBuildsTheSameHierarchyInBothThemes() {
        XCTAssertGreaterThan(
            relativeLuminance(AppThemePalette.lightPage),
            relativeLuminance(AppThemePalette.lightCard)
        )
        XCTAssertGreaterThan(
            relativeLuminance(AppThemePalette.lightCard),
            relativeLuminance(AppThemePalette.lightInset)
        )
        XCTAssertLessThan(
            relativeLuminance(AppThemePalette.darkPage),
            relativeLuminance(AppThemePalette.darkCard)
        )
        XCTAssertLessThan(
            relativeLuminance(AppThemePalette.darkCard),
            relativeLuminance(AppThemePalette.darkInset)
        )
        XCTAssertLessThan(
            relativeLuminance(AppThemePalette.darkInset),
            relativeLuminance(AppThemePalette.darkSeparator)
        )
    }

    func testLightThemeUsesPureWhiteAndDarkThemeUsesPureBlack() {
        XCTAssertEqual(AppThemePalette.lightPage, AppThemeRGB(hex: 0xFFFFFF))
        XCTAssertEqual(AppThemePalette.darkPage, AppThemeRGB(hex: 0x000000))
    }

    func testBusinessSemanticColorsStayDistinctFromMonochromeInteraction() {
        let lightSemanticColors = [
            AppThemePalette.lightTraining,
            AppThemePalette.lightMeal,
            AppThemePalette.lightBody,
            AppThemePalette.lightTrend,
            AppThemePalette.lightWarning
        ]
        let darkSemanticColors = [
            AppThemePalette.darkTraining,
            AppThemePalette.darkMeal,
            AppThemePalette.darkBody,
            AppThemePalette.darkTrend,
            AppThemePalette.darkWarning
        ]

        assertAllDistinct(lightSemanticColors)
        assertAllDistinct(darkSemanticColors)
        for color in lightSemanticColors {
            XCTAssertNotEqual(color, AppThemePalette.lightAccent)
        }
        for color in darkSemanticColors {
            XCTAssertNotEqual(color, AppThemePalette.darkAccent)
        }
    }

    func testSemanticRoleSetCoversEveryBusinessDataFamily() {
        XCTAssertEqual(
            Set(AppSemanticRole.allCases.map(\.rawValue)),
            Set(["training", "meal", "body", "trend", "warning"])
        )
    }

    func testMetricRolesStayDistinctAndUseSpecificIcons() {
        let lightMetricColors = [
            AppThemePalette.lightConsistency,
            AppThemePalette.lightTraining,
            AppThemePalette.lightRecovery,
            AppThemePalette.lightTrend,
            AppThemePalette.lightBody,
            AppThemePalette.lightVital
        ]
        let darkMetricColors = [
            AppThemePalette.darkConsistency,
            AppThemePalette.darkTraining,
            AppThemePalette.darkRecovery,
            AppThemePalette.darkTrend,
            AppThemePalette.darkBody,
            AppThemePalette.darkVital
        ]

        assertAllDistinct(lightMetricColors)
        assertAllDistinct(darkMetricColors)
        XCTAssertEqual(
            Set(AppMetricRole.allCases.map(\.rawValue)),
            Set(["consistency", "trainingLoad", "recovery", "performance", "body", "vital"])
        )
        XCTAssertEqual(
            Set(AppMetricRole.allCases.map(\.systemImage)).count,
            AppMetricRole.allCases.count
        )
    }

    func testStatusRolesCoverPositiveAttentionCriticalAndNeutral() {
        XCTAssertEqual(
            Set(AppStatusRole.allCases.map(\.rawValue)),
            Set(["positive", "attention", "critical", "neutral"])
        )
    }

    private func contrast(_ lhs: AppThemeRGB, _ rhs: AppThemeRGB) -> Double {
        let light = max(relativeLuminance(lhs), relativeLuminance(rhs))
        let dark = min(relativeLuminance(lhs), relativeLuminance(rhs))
        return (light + 0.05) / (dark + 0.05)
    }

    private func assertAllDistinct(
        _ colors: [AppThemeRGB],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for firstIndex in colors.indices {
            for secondIndex in colors.indices where secondIndex > firstIndex {
                XCTAssertNotEqual(
                    colors[firstIndex],
                    colors[secondIndex],
                    file: file,
                    line: line
                )
            }
        }
    }

    private func relativeLuminance(_ color: AppThemeRGB) -> Double {
        0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }

    private func linear(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}
