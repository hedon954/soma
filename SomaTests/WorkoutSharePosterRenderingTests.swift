@testable import Soma
import SwiftUI
import XCTest

final class WorkoutSharePosterRenderingTests: XCTestCase {
    @MainActor
    func testSelectedPosterHasStableExportAcrossAppAppearances() throws {
        XCTAssertNotNil(UIFont(name: "DINCondensed-Bold", size: 72))
        let model = referenceModel(exerciseCount: 6)
        let light = try render(model, scheme: .light, name: "workout-share-selected-light")
        let dark = try render(model, scheme: .dark, name: "workout-share-selected-dark")
        XCTAssertEqual(light.pngData(), dark.pngData(), "The selected white-paper export is independent of sheet appearance")
    }

    @MainActor
    func testPosterFitsIPhone17ProMaxCanvas() throws {
        let four = referenceModel(exerciseCount: 4)
        let filledFour = try render(four, scheme: .light, name: "workout-share-four")
        XCTAssertEqual(filledFour.size.width, WorkoutShareCanvas.width, accuracy: 0.5)
        XCTAssertEqual(filledFour.size.height, WorkoutShareCanvas.height, accuracy: 0.5)

        var model = referenceModel(exerciseCount: 6)
        let compact = try render(model, scheme: .light, name: "workout-share-compact")
        XCTAssertEqual(compact.size.width, WorkoutShareCanvas.width, accuracy: 0.5)
        XCTAssertEqual(compact.size.height, WorkoutShareCanvas.height, accuracy: 0.5)

        let seven = try render(referenceModel(exerciseCount: 7), scheme: .light, name: "workout-share-seven")
        XCTAssertEqual(seven.size.height, WorkoutShareCanvas.height, accuracy: 0.5)

        model.title = "虚构的长名称训练课程：全身力量与核心稳定训练"
        model.volumeValue = "1,234,567"
        model.estimatedCalories = nil
        model.partialSets = 2
        model.failedSets = 1
        model.exercises[3].name = "虚构哑铃交替保加利亚分腿深蹲长名称"
        model.exercises[3].partialSetCount = 2
        model.exercises[3].loadGroups = [
            "左 重量未记录 · 8次 / 右 10kg · 6次 × 1组",
            "左 12kg · 6次 / 右 10kg · 6次 × 1组"
        ]
        let long = try render(model, scheme: .dark, name: "workout-share-long-missing")
        XCTAssertEqual(long.size.width, WorkoutShareCanvas.width, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(long.size.height, WorkoutShareCanvas.height)
    }

    @MainActor
    func testPosterGrowsWhenExercisesOverflowProMaxPaper() throws {
        let overflowing = try render(
            referenceModel(exerciseCount: 16),
            scheme: .light,
            name: "workout-share-overflow"
        )
        XCTAssertEqual(overflowing.size.width, WorkoutShareCanvas.width, accuracy: 0.5)
        XCTAssertGreaterThan(overflowing.size.height, WorkoutShareCanvas.height + 0.5)
    }

    @MainActor
    func testManyDistinctGroupsIncreasePaperHeightWithoutTruncation() throws {
        var model = referenceModel(exerciseCount: 4)
        for index in model.exercises.indices {
            model.exercises[index].name = "虚构长名称哑铃交替保加利亚分腿深蹲与稳定控制训练动作 \(index + 1)"
            model.exercises[index].setCount = 8
            model.exercises[index].loadGroups = (0 ..< 8).map { group in
                "左 \(12 + group)kg · 8次 / 右 \(10 + group)kg · 6次 × 1组"
            }
        }
        model.completedSets = 32
        let image = try render(model, scheme: .light, name: "workout-share-many-groups")
        XCTAssertEqual(image.size.width, WorkoutShareCanvas.width, accuracy: 0.5)
        XCTAssertGreaterThan(image.size.height, WorkoutShareCanvas.height + 200)
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

    private func referenceModel(exerciseCount: Int) -> WorkoutSharePosterModel {
        let catalog: [(String, String, Int)] = [
            ("杠铃深蹲", "60kg · 5次 × 5组", 5),
            ("罗马尼亚硬拉", "50kg · 8次 × 5组", 5),
            ("俯卧勾腿", "25kg · 12次 × 3组", 3),
            ("保加利亚分腿蹲", "左右各 自重 · 12次 × 2组", 2),
            ("提踵", "30kg · 12次 × 4组", 4),
            ("平板支撑", "自重 · 30秒 × 3组", 3),
            ("侧平板支撑", "自重 · 30秒 × 3组", 3),
            ("弹力带单腿侧点地", "自重 · 12次 × 3组", 3),
            ("单腿硬拉", "16kg · 8次 × 3组", 3),
            ("哑铃高脚杯侧弓步", "12kg · 10次 × 3组", 3),
            ("坐姿腿屈伸", "25kg · 12次 × 3组", 3),
            ("髋外展", "20kg · 15次 × 3组", 3),
            ("反向腿弯举", "20kg · 12次 × 3组", 3),
            ("箱式深蹲", "40kg · 8次 × 3组", 3),
            ("箭步蹲", "左右各 12kg · 8次 × 2组", 2),
            ("山羊挺身", "自重 · 12次 × 3组", 3)
        ]
        let rows = (0 ..< exerciseCount).map { index in
            catalog[index % catalog.count]
        }
        return WorkoutSharePosterModel(
            dateText: "2026.09.05 周六", title: "下肢力量训练", focusMuscles: ["股四头肌", "臀大肌"],
            durationText: "约 35 分 38 秒", volumeValue: "5,840", exerciseCount: exerciseCount, completedSets: 22,
            estimatedCalories: 187, intensities: [.quadriceps: 5, .calves: 5],
            exercises: rows.map { name, summary, sets in
                WorkoutSharePosterModel.ExerciseLine(id: UUID(), name: name, setCount: sets, loadGroups: summary.components(separatedBy: "；"))
            }
        )
    }
}
