@testable import Soma
import XCTest

final class ExerciseLibraryFilterTests: XCTestCase {
    func testFacetsIntersectAndSearchStillApplies() {
        let item = ExerciseLibraryClassification(name: "虚构推举", primary: ["胸大肌"], secondary: ["肱三头肌"], patterns: ["水平推"])
        var filter = ExerciseLibraryFilter()
        filter.region = .chest
        filter.pattern = "水平推"
        filter.muscle = "肱三头肌"
        XCTAssertTrue(filter.matches(item, search: " 推举 "))
        XCTAssertFalse(filter.matches(item, search: "深蹲"))
        filter.primaryOnly = true
        XCTAssertFalse(filter.matches(item, search: ""))
        filter.primaryOnly = false
        filter.region = .arms
        XCTAssertFalse(filter.matches(item, search: ""), "辅助肌群不能改变主要训练部位")
    }

    func testMultiplePrimaryRegionsAndUnknownMetadataStayVisible() {
        let item = ExerciseLibraryClassification(name: "虚构蹲", primary: ["股四头肌", "臀大肌"], secondary: [], patterns: [" 蹲 ", "蹲", ""])
        XCTAssertEqual(item.regions, [.legs, .glutes])
        XCTAssertEqual(item.patterns, ["蹲"])
        let unknown = ExerciseLibraryClassification(name: "自定义", primary: ["尚未确认的肌群"], secondary: [], patterns: [])
        XCTAssertEqual(unknown.regions, [.unclassified])
        XCTAssertEqual(unknown.primary, ["尚未确认的肌群"])
        var filter = ExerciseLibraryFilter()
        filter.pattern = ExerciseLibraryClassification.unspecified
        XCTAssertTrue(filter.matches(unknown, search: ""))
        XCTAssertFalse(filter.matches(item, search: ""))
    }

    func testMuscleLabelsPreserveAnatomicalIdentity() {
        let item = ExerciseLibraryClassification(name: "虚构侧平举", primary: ["三角肌中束"], secondary: ["三角肌前束"], patterns: [])
        XCTAssertEqual(item.regions, [.shoulders])
        XCTAssertEqual(item.primary, ["三角肌中束"])
        XCTAssertEqual(item.secondary, ["三角肌前束"])
    }
}
