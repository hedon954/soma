@testable import Soma
import SwiftData
import XCTest

final class GymRecorderBoundaryTests: XCTestCase {
    @MainActor
    func testSwitchGymFindsTargetPastDisplayLimit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let gyms = insertGyms(count: 101, in: context)
        gyms[0].isCurrent = true
        gyms[100].name = "虚构边界目标馆"
        try context.save()

        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .switchGym,
                arguments: AgentToolArguments(gymName: "边界目标馆")
            ),
            sourceText: "切换到虚构边界目标馆",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertTrue(result.ok, result.message)
        let stored = try context.fetch(FetchDescriptor<GymProfile>())
        XCTAssertEqual(stored.filter(\.isCurrent).map(\.id), [gyms[100].id])
    }

    @MainActor
    func testUpdateGymDoesNotDuplicateTargetPastDisplayLimit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let gyms = insertGyms(count: 101, in: context)
        gyms[100].name = "虚构边界更新馆"
        try context.save()

        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .updateGym,
                arguments: AgentToolArguments(
                    gymName: "边界更新馆",
                    summary: "虚构更新后的环境说明"
                )
            ),
            sourceText: "更新虚构边界更新馆",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertTrue(result.ok, result.message)
        let stored = try context.fetch(FetchDescriptor<GymProfile>())
        XCTAssertEqual(stored.count, 101)
        XCTAssertEqual(
            stored.filter { $0.name == "虚构边界更新馆" }.map(\.notes),
            ["虚构更新后的环境说明"]
        )
    }

    @MainActor
    func testOverviewFindsCurrentGymPastDisplayLimit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let gyms = insertGyms(count: 101, in: context)
        gyms[100].name = "虚构窗口外当前馆"
        gyms[100].isCurrent = true
        try context.save()

        let result = ConversationRecorder.queryUserData(
            AgentToolArguments(scope: "overview"),
            preferredGymID: nil,
            in: context
        )

        XCTAssertTrue(result.ok, result.message)
        XCTAssertTrue(result.message.contains("当前健身房：虚构窗口外当前馆"), result.message)
    }

    @MainActor
    func testUpdateGymFindsEquipmentPastGlobalDisplayLimit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let decoyGym = GymProfile(name: "虚构干扰馆")
        let targetGym = GymProfile(name: "虚构器械目标馆", isCurrent: true)
        context.insert(decoyGym)
        context.insert(targetGym)
        for index in 0 ..< 1000 {
            let equipment = GymEquipment(
                gymID: decoyGym.id,
                name: "虚构干扰器械 \(index)",
                category: "干扰",
                capabilities: "无"
            )
            equipment.createdAt = baseDate.addingTimeInterval(Double(index))
            context.insert(equipment)
        }
        let targetEquipment = GymEquipment(
            gymID: targetGym.id,
            name: "虚构边界器械",
            category: "旧分类",
            capabilities: "旧能力"
        )
        targetEquipment.createdAt = baseDate.addingTimeInterval(1001)
        context.insert(targetEquipment)
        try context.save()

        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .updateGym,
                arguments: AgentToolArguments(
                    gymName: "虚构器械目标馆",
                    equipment: [
                        AgentEquipmentInput(
                            name: "虚构边界器械",
                            category: "新分类",
                            capabilities: "新能力"
                        )
                    ]
                )
            ),
            sourceText: "更新虚构边界器械",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertTrue(result.ok, result.message)
        let targetID = targetGym.id
        let matching = try context.fetch(FetchDescriptor<GymEquipment>(
            predicate: #Predicate {
                $0.gymID == targetID && $0.name == "虚构边界器械"
            }
        ))
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?.category, "新分类")
        XCTAssertEqual(matching.first?.capabilities, "新能力")
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(SomaDataSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    private func insertGyms(count: Int, in context: ModelContext) -> [GymProfile] {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        return (0 ..< count).map { index in
            let gym = GymProfile(name: "虚构健身房 \(index)")
            gym.createdAt = baseDate.addingTimeInterval(Double(index))
            context.insert(gym)
            return gym
        }
    }
}
