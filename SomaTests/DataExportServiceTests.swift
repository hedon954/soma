import Foundation
@testable import Soma
import XCTest

final class DataExportServiceTests: XCTestCase {
    @MainActor
    func testExportCreatesReadableYearMonthDayRecordsAndOrderedMedia() throws {
        let snapshot = try DataArchiveTestSupport.makeSnapshot()
        let root = try DataArchiveTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appending(path: "source.jpg")
        let exerciseImage = root.appending(path: "exercise.jpg")
        let video = root.appending(path: "source.mov")
        try Data("image-content".utf8).write(to: image)
        try Data("exercise-image-content".utf8).write(to: exerciseImage)
        try Data("video-content".utf8).write(to: video)
        let sources = [
            DataArchiveTestSupport.mealMediaPath: image,
            DataArchiveTestSupport.exerciseImagePath: exerciseImage,
            DataArchiveTestSupport.workoutMediaPath: video
        ]
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let payload = PortableExportPayload(
            snapshot: snapshot,
            timeZone: timeZone
        )

        let result = try DataExportService.export(
            payload,
            to: root,
            mediaURL: { sources[$0] }
        )

        XCTAssertEqual(result.mealCount, 1)
        XCTAssertEqual(result.workoutCount, 1)
        XCTAssertEqual(result.copiedMediaCount, 3)
        XCTAssertEqual(result.missingMediaCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: result.directoryURL.appending(path: "manifest.json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: result.directoryURL.appending(path: "说明.txt").path
        ))

        let dayDirectory = result.directoryURL
            .appending(path: "2026", directoryHint: .isDirectory)
            .appending(path: "07", directoryHint: .isDirectory)
            .appending(path: "30", directoryHint: .isDirectory)
        let mealRoot = dayDirectory.appending(path: "饮食", directoryHint: .isDirectory)
        let workoutRoot = dayDirectory.appending(path: "训练", directoryHint: .isDirectory)
        let mealDirectory = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(
                at: mealRoot,
                includingPropertiesForKeys: nil
            ).first
        )
        let workoutDirectory = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(
                at: workoutRoot,
                includingPropertiesForKeys: nil
            ).first
        )
        let mealText = try String(
            contentsOf: mealDirectory.appending(path: "原始记录.txt"),
            encoding: .utf8
        )
        XCTAssertTrue(mealText.contains("午餐吃了荞麦面"))
        XCTAssertTrue(mealText.contains("饮食与训练已记录"))
        let mealMedia = try FileManager.default.contentsOfDirectory(
            at: mealDirectory.appending(path: "媒体"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(mealMedia.map(\.lastPathComponent), ["001-image.jpg"])
        let workoutMedia = try FileManager.default.contentsOfDirectory(
            at: workoutDirectory.appending(path: "媒体"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(workoutMedia.map(\.lastPathComponent), ["001-video.mov"])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let analysis = try decoder.decode(
            PortableMealAnalysis.self,
            from: Data(contentsOf: mealDirectory.appending(path: "分析结果.json"))
        )
        XCTAssertEqual(analysis.title, "测试午餐")
        XCTAssertEqual(analysis.glycemicSpeed, "moderate")
        XCTAssertEqual(
            analysis.glycemicAssessment,
            "虚构餐食含完整谷物与蔬菜，组成升糖速度估计为中等。"
        )
        XCTAssertEqual(analysis.media.map(\.kind), ["image"])
        XCTAssertEqual(analysis.sourceText, "午餐吃了荞麦面，之后做了深蹲")
    }

    @MainActor
    func testExportReportsMissingMediaWithoutExposingSandboxPath() throws {
        let snapshot = try DataArchiveTestSupport.makeSnapshot()
        let root = try DataArchiveTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try DataExportService.export(
            PortableExportPayload(snapshot: snapshot),
            to: root,
            mediaURL: { _ in nil }
        )

        XCTAssertEqual(result.copiedMediaCount, 0)
        XCTAssertEqual(result.missingMediaCount, 3)
        let manifestData = try Data(
            contentsOf: result.directoryURL.appending(path: "manifest.json")
        )
        let manifestText = try XCTUnwrap(String(data: manifestData, encoding: .utf8))
        XCTAssertFalse(manifestText.contains("PrivateMedia"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            PortableExportManifest.self,
            from: manifestData
        )
        XCTAssertEqual(manifest.missingMedia.count, 3)
    }

    @MainActor
    func testExportIncludesStructuredTrainingModelsAndSupplementalVideo() throws {
        var snapshot = try DataArchiveTestSupport.makeSnapshot()
        let supplementalPath = "PrivateMedia/exercise-demo.mov"
        snapshot.exerciseDefinitions?[0].userDemoVideos = [
            MediaAttachmentReference(kind: .video, path: supplementalPath)
        ]
        let root = try DataArchiveTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appending(path: "source.jpg")
        let exerciseImage = root.appending(path: "exercise.jpg")
        let workoutVideo = root.appending(path: "source.mov")
        let demoVideo = root.appending(path: "demo.mov")
        try Data("image".utf8).write(to: image)
        try Data("exercise-image".utf8).write(to: exerciseImage)
        try Data("workout-video".utf8).write(to: workoutVideo)
        try Data("demo-video".utf8).write(to: demoVideo)
        let sources = [
            DataArchiveTestSupport.mealMediaPath: image,
            DataArchiveTestSupport.exerciseImagePath: exerciseImage,
            DataArchiveTestSupport.workoutMediaPath: workoutVideo,
            supplementalPath: demoVideo
        ]

        let result = try DataExportService.export(
            PortableExportPayload(snapshot: snapshot),
            to: root,
            mediaURL: { sources[$0] }
        )

        XCTAssertEqual(result.copiedMediaCount, 4)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: result.directoryURL.appending(
                path: "结构化数据.json"
            ).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: result.directoryURL.appending(
                path: "结构化媒体索引.json"
            ).path
        ))
        let supplemental = try FileManager.default.contentsOfDirectory(
            at: result.directoryURL.appending(path: "其他媒体"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(supplemental.count, 2)
    }
}
