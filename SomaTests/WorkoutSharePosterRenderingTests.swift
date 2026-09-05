@testable import Soma
import SwiftUI
import XCTest

final class WorkoutSharePosterRenderingTests: XCTestCase {
    @MainActor
    func testSelectedPosterHasStableExportAcrossAppAppearances() throws {
        XCTAssertNotNil(UIFont(name: "DINCondensed-Bold", size: 110))
        let model = referenceModel
        let light = try render(model, scheme: .light, name: "workout-share-selected-light")
        let dark = try render(model, scheme: .dark, name: "workout-share-selected-dark")
        XCTAssertEqual(light.pngData(), dark.pngData(), "The selected white-paper export is independent of sheet appearance")
    }

    @MainActor
    func testLongAndMissingEvidenceExpandsInsteadOfClipping() throws {
        var model = referenceModel
        let reference = try render(model, scheme: .light, name: "workout-share-compact")
        model.title = "虚构的长名称训练计划：全身力量与核心稳定训练"
        model.volumeValue = "1,234,567"
        model.estimatedCalories = nil
        model.partialSets = 2
        model.failedSets = 1
        model.exercises[3].name = "虚构哑铃交替保加利亚分腿深蹲长名称"
        model.exercises[3].partialSetCount = 2
        model.exercises[3].loadGroups = ["左 重量未记录 · 8次 / 右 10kg · 6次 × 1组", "左 12kg · 6次 / 右 10kg · 6次 × 1组"]
        let expanded = try render(model, scheme: .dark, name: "workout-share-long-missing")
        XCTAssertEqual(expanded.size.width, 390)
        XCTAssertGreaterThan(expanded.size.height, reference.size.height)
    }

    @MainActor
    private func render(_ model: WorkoutSharePosterModel, scheme: ColorScheme, name: String) throws -> UIImage {
        let poster = WorkoutSharePosterView(model: model)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, .accessibility5)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }

    private var referenceModel: WorkoutSharePosterModel {
        let rows: [(String, String, Int)] = [
            ("杠铃深蹲", "60kg · 5次 × 5组", 5),
            ("罗马尼亚硬拉", "50kg · 8次 × 5组", 5),
            ("俯卧勾腿", "25kg · 12次 × 3组", 3),
            ("保加利亚分腿蹲", "左右各 自重 · 12次 × 2组", 2),
            ("提踵", "30kg · 12次 × 4组", 4),
            ("平板支撑", "自重 · 30秒 × 3组", 3)
        ]
        return WorkoutSharePosterModel(
            dateText: "2026.09.05 周六", title: "下肢力量训练", focusMuscles: ["股四头肌", "臀大肌"],
            durationText: "约 35 分 38 秒", volumeValue: "5,840", exerciseCount: 6, completedSets: 22,
            estimatedCalories: 187, intensities: [.quadriceps: 5, .calves: 5],
            exercises: rows.map { name, summary, sets in
                WorkoutSharePosterModel.ExerciseLine(id: UUID(), name: name, setCount: sets, loadGroups: summary.components(separatedBy: "；"))
            }
        )
    }
}
