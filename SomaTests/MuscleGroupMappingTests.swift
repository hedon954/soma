@testable import Soma
import XCTest

final class MuscleGroupMappingTests: XCTestCase {
    func testMapsChinesePrimaryAndSecondaryMuscles() {
        let values = MuscleGroupMapping.intensityMap(
            primary: ["股四头肌", "臀大肌"],
            secondary: ["腘绳肌", "核心"]
        )

        XCTAssertEqual(values[.quadriceps], 1)
        XCTAssertEqual(values[.gluteal], 1)
        XCTAssertEqual(values[.hamstring], 0.45)
        XCTAssertEqual(values[.abs], 0.45)
        XCTAssertNil(values[.chest])
    }

    func testUnmappedNamesStayDark() {
        let values = MuscleGroupMapping.intensityMap(
            primary: ["不存在的肌群XYZ"],
            secondary: []
        )
        XCTAssertTrue(values.isEmpty)
    }

    func testMultiExerciseIntensityAccumulatesAndNormalizes() {
        let merged = MuscleGroupMapping.merge([
            MuscleGroupMapping.intensityMap(
                primary: ["胸大肌"],
                secondary: ["肱三头肌"],
                primaryWeight: 5,
                secondaryWeight: 2.25
            ),
            MuscleGroupMapping.intensityMap(
                primary: ["胸大肌"],
                secondary: [],
                primaryWeight: 3,
                secondaryWeight: 0
            )
        ])
        let normalized = MuscleGroupMapping.normalized(merged)

        XCTAssertEqual(merged[.chest], 8)
        XCTAssertEqual(try XCTUnwrap(normalized[.chest]), 1, accuracy: 0.001)
        XCTAssertLessThan(try XCTUnwrap(normalized[.triceps]), 1)
        XCTAssertGreaterThan(try XCTUnwrap(normalized[.triceps]), 0)
    }

    func testPathDataCoversDrawableCanonicalMuscles() {
        let keys = Set(
            (MuscleMapPathData.anterior + MuscleMapPathData.posterior)
                .map(\.muscleRaw)
        )
        // Abductors currently have label slots only; SVG dataset has no dedicated path.
        let drawable = MuscleGroup.allCases.filter { $0 != .abductors }
        for group in drawable {
            XCTAssertFalse(
                Set(group.pathKeys).isDisjoint(with: keys),
                "\(group.rawValue) missing from path data"
            )
        }
    }

    func testLabelAnchorsCoverEveryMuscleGroup() {
        XCTAssertTrue(MuscleMapLabels.coversAllGroups())
    }

    func testSVGPathParsesCubicAndClose() {
        let path = SVGPath.makeCGPath(
            from: "M10 10 C 20 20, 40 20, 50 10 Z"
        )
        XCTAssertNotNil(path)
        XCTAssertFalse(try XCTUnwrap(path).isEmpty)
    }

    func testAllMuscleMapSVGPathsParse() {
        for side in MuscleMapSide.allCases {
            XCTAssertNotNil(
                SVGPath.makeCGPath(from: MuscleMapPathData.outline(for: side)),
                "outline \(side.rawValue)"
            )
            for part in MuscleMapPathData.parts(for: side) {
                for (index, data) in part.pathData.enumerated() {
                    XCTAssertNotNil(
                        SVGPath.makeCGPath(from: data),
                        "\(side.rawValue) \(part.muscleRaw)#\(index)"
                    )
                }
            }
        }
    }

    func testDeltoidPathKeyDependsOnBodySide() {
        XCTAssertEqual(
            MuscleGroup.group(forPathKey: "deltoids", side: .anterior),
            .frontDeltoids
        )
        XCTAssertEqual(
            MuscleGroup.group(forPathKey: "deltoids", side: .posterior),
            .backDeltoids
        )
    }
}
