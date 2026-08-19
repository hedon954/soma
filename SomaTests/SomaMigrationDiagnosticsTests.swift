import Foundation
@testable import Soma
import SwiftData
import XCTest

final class SomaMigrationDiagnosticsTests: XCTestCase {
    func testReportIncludesStackDumpAndNestedMigrationStep() {
        let underlying = NSError(
            domain: "SwiftData.SwiftDataError",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "未能完成操作。",
                NSLocalizedFailureReasonErrorKey: "虚构失败原因",
                "NSDebugDescription": "loadIssue",
                NSUnderlyingErrorKey: NSError(
                    domain: NSCocoaErrorDomain,
                    code: 133_021,
                    userInfo: [
                        NSLocalizedDescriptionKey: "唯一约束冲突",
                        "NSValidationErrorKey": "projectionKey"
                    ]
                )
            ]
        )
        let error = DataMigrationError.stepFailed("打开个人数据容器", underlying)
        let report = SomaMigrationDiagnostics.report(
            error: error,
            context: "迁移失败",
            origin: "SomaMigrationDiagnosticsTests.testReportIncludesStackDumpAndNestedMigrationStep",
            isStoredInMemoryOnly: true,
            demoContainerPresent: false,
            personalContainerPresent: true
        )

        XCTAssertTrue(report.contains("=== Soma 迁移诊断 ==="))
        XCTAssertTrue(report.contains("--- 堆栈 ---"))
        XCTAssertTrue(report.contains("testReportIncludesStackDumpAndNestedMigrationStep"))
        XCTAssertTrue(report.contains("ErrorDump：") || report.contains("ErrorDump"))
        XCTAssertTrue(report.contains("MigrationStep：打开个人数据容器"))
        XCTAssertTrue(report.contains("133021"))
        XCTAssertTrue(report.contains("projectionKey"))
        XCTAssertTrue(report.contains("虚构失败原因"))
        XCTAssertFalse(report.contains("sk-live-secret"))
    }

    @MainActor
    func testReportIncludesWorkoutSamplesAndNilProjectionKeyCounts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SomaDiagnostics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("PersonalData.store")
        do {
            let schema = Schema(SomaDataSchema.models)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(
                    "DiagnosticsSource",
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: .none
                )]
            )
            for name in ["虚构诊断深蹲", "虚构诊断卧推", "虚构诊断硬拉"] {
                let workout = WorkoutEntry(exercise: name)
                workout.projectionKey = nil
                container.mainContext.insert(workout)
                try container.mainContext.save()
            }
            container.mainContext.insert(DataMigrationMarker(schemaVersion: 5))
            try container.mainContext.save()
        }

        let report = SomaMigrationDiagnostics.report(
            error: DataMigrationError.stepFailed(
                "补齐训练投影键",
                NSError(domain: "SwiftData.SwiftDataError", code: 1)
            ),
            context: "迁移失败",
            origin: "SomaMigrationDiagnosticsTests.testReportIncludesWorkoutSamplesAndNilProjectionKeyCounts",
            isStoredInMemoryOnly: false,
            demoContainerPresent: false,
            personalContainerPresent: false,
            storeURLs: [storeURL]
        )

        XCTAssertTrue(report.contains("ZWORKOUTENTRY"))
        XCTAssertTrue(report.contains("空 projectionKey：3") || report.contains("空 projectionKey：3\n") || report.contains("空 projectionKey：3"))
        XCTAssertTrue(report.contains("虚构诊断深蹲"))
        XCTAssertTrue(report.contains("虚构诊断卧推"))
        XCTAssertTrue(report.contains("虚构诊断硬拉"))
        XCTAssertTrue(report.contains("CREATE TABLE") || report.contains("table SQL"))
        XCTAssertTrue(report.contains("Z_METADATA") || report.contains("modelHashes"))
        XCTAssertFalse(report.contains("身体测量值"))
    }
}
