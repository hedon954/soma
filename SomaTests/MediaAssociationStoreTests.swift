@testable import Soma
import SwiftData
import XCTest

final class MediaAssociationStoreTests: XCTestCase {
    func testGymToolAttributesImmediatePreviousImagesToNameFollowup() {
        let olderImage = MediaAttachmentReference(
            kind: .image,
            path: "PrivateMedia/older.jpg"
        )
        let gymImage = MediaAttachmentReference(
            kind: .image,
            path: "PrivateMedia/gym.jpg"
        )
        let history = ConversationContextProjection(exchanges: [
            .init(
                turnID: UUID(),
                userText: "之前的照片",
                assistantText: "收到",
                mediaAttachments: [olderImage]
            ),
            .init(
                turnID: UUID(),
                userText: "这是新健身房",
                assistantText: "这个健身房叫什么？",
                mediaAttachments: [gymImage]
            )
        ])
        let call = AgentToolCall(
            name: .updateGym,
            arguments: AgentToolArguments(
                gymName: "趣极运动",
                equipment: [
                    AgentEquipmentInput(
                        name: "跑步机",
                        category: "有氧",
                        capabilities: "跑步",
                        confidence: 0.9
                    )
                ]
            )
        )

        XCTAssertEqual(
            AgentToolMediaAttribution.attachments(
                for: call,
                current: [],
                history: history
            ),
            [gymImage]
        )
    }

    func testGymToolDoesNotReachPastImmediatePreviousTurn() {
        let history = ConversationContextProjection(exchanges: [
            .init(
                turnID: UUID(),
                userText: "这是新健身房",
                assistantText: "收到",
                mediaAttachments: [
                    .init(kind: .image, path: "PrivateMedia/gym.jpg")
                ]
            ),
            .init(
                turnID: UUID(),
                userText: "先聊别的",
                assistantText: "可以",
                mediaAttachments: []
            )
        ])
        let call = AgentToolCall(
            name: .updateGym,
            arguments: AgentToolArguments(
                gymName: "趣极运动",
                mediaSource: AgentToolMediaAttribution.recentGymTurn
            )
        )

        XCTAssertTrue(
            AgentToolMediaAttribution.attachments(
                for: call,
                current: [],
                history: history
            ).isEmpty
        )
    }

    func testGymToolPrefersCurrentImages() {
        let historicalImage = MediaAttachmentReference(
            kind: .image,
            path: "PrivateMedia/history.jpg"
        )
        let currentImage = MediaAttachmentReference(
            kind: .image,
            path: "PrivateMedia/current.jpg"
        )
        let history = ConversationContextProjection(exchanges: [
            .init(
                turnID: UUID(),
                userText: "上一轮",
                assistantText: "收到",
                mediaAttachments: [historicalImage]
            )
        ])
        let call = AgentToolCall(
            name: .updateGym,
            arguments: AgentToolArguments(
                gymName: "趣极运动",
                mediaSource: AgentToolMediaAttribution.recentGymTurn
            )
        )

        XCTAssertEqual(
            AgentToolMediaAttribution.attachments(
                for: call,
                current: [currentImage],
                history: history
            ),
            [currentImage]
        )
    }

    @MainActor
    func testExplicitRecentGymMediaFailsWithoutCreatingGym() throws {
        let context = try makeContext()
        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .updateGym,
                arguments: AgentToolArguments(
                    gymName: "趣极运动",
                    mediaSource: AgentToolMediaAttribution.recentGymTurn
                )
            ),
            sourceText: "趣极运动",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.observation.contains("重新附加"))
        XCTAssertTrue(try context.fetch(FetchDescriptor<GymProfile>()).isEmpty)
    }

    @MainActor
    func testDetachingRecordMediaKeepsOtherAttachments() throws {
        let context = try makeContext()
        let first = MediaAttachmentReference(
            kind: .image,
            path: "PrivateMedia/front.jpg"
        )
        let second = MediaAttachmentReference(
            kind: .image,
            path: "PrivateMedia/side.jpg"
        )
        let workout = WorkoutEntry(
            exercise: "深蹲",
            mediaAttachments: [first, second]
        )
        let meal = MealEntry(
            mealType: .lunch,
            title: "午餐",
            calories: 500,
            protein: 30,
            carbs: 50,
            fat: 15,
            mediaAttachments: [first, second]
        )
        let body = BodyEntry(mediaAttachments: [first, second])
        context.insert(workout)
        context.insert(meal)
        context.insert(body)
        try context.save()

        XCTAssertTrue(MediaAssociationStore.detach(first, from: workout, in: context))
        XCTAssertTrue(MediaAssociationStore.detach(first, from: meal, in: context))
        XCTAssertTrue(MediaAssociationStore.detach(first, from: body, in: context))

        XCTAssertEqual(workout.mediaAttachments, [second])
        XCTAssertEqual(workout.mediaPath, second.path)
        XCTAssertEqual(meal.mediaAttachments, [second])
        XCTAssertEqual(meal.imagePath, second.path)
        XCTAssertEqual(body.mediaAttachments, [second])
        XCTAssertEqual(body.imagePath, second.path)
    }

    @MainActor
    func testDetachingGymCoverPromotesRemainingPhoto() throws {
        let context = try makeContext()
        let gym = GymProfile(
            name: "趣极运动",
            coverImagePath: "PrivateMedia/front.jpg",
            isCurrent: true
        )
        let front = GymMedia(
            gymID: gym.id,
            path: "PrivateMedia/front.jpg",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let side = GymMedia(
            gymID: gym.id,
            path: "PrivateMedia/side.jpg",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let equipment = GymEquipment(
            gymID: gym.id,
            name: "跑步机",
            category: "有氧",
            capabilities: "跑步",
            imagePath: front.path
        )
        context.insert(gym)
        context.insert(front)
        context.insert(side)
        context.insert(equipment)
        try context.save()

        XCTAssertTrue(MediaAssociationStore.detachGymPhoto(
            at: front.path,
            from: gym,
            equipment: [equipment],
            media: [front, side],
            in: context
        ))

        XCTAssertEqual(gym.coverImagePath, side.path)
        XCTAssertEqual(equipment.imagePath, side.path)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<GymMedia>()).map(\.path),
            [side.path]
        )
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: GymProfile.self,
            GymEquipment.self,
            GymMedia.self,
            MealEntry.self,
            BodyEntry.self,
            WorkoutEntry.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
