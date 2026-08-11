@testable import Soma
import SwiftData
import XCTest

final class RecordMutationTests: XCTestCase {
    @MainActor
    func testNewMealImageCreatesNewRecordWithoutGuessingHistoricalCandidate() throws {
        let context = try makeContext()
        let sessionID = UUID()
        let firstTurnID = UUID()
        let secondTurnID = UUID()
        let date = Date(timeIntervalSince1970: 1_785_386_220)
        let firstMedia = MediaAttachmentReference(
            kind: .image,
            path: "PrivateMedia/meal-overview.jpg"
        )
        let secondMedia = MediaAttachmentReference(
            kind: .image,
            path: "PrivateMedia/meal-closeup.jpg"
        )

        let firstResult = ConversationRecorder.executeAgentTool(
            mealCall(title: "荞麦面套餐（含鱼、蛋、蔬菜）+ 蔬菜清汤"),
            sourceText: "这是我的午餐",
            sourceDate: date,
            sourceSessionID: sessionID,
            sourceTurnID: firstTurnID,
            mediaKind: .image,
            mediaPath: firstMedia.path,
            mediaAttachments: [firstMedia],
            in: context
        )
        let correctionResult = ConversationRecorder.executeAgentTool(
            mealCall(title: "荞麦面套餐 + 蔬菜清汤"),
            sourceText: "不是鱼肉，是鸡肉和一块裹红酱的炸物",
            sourceDate: date.addingTimeInterval(90),
            sourceSessionID: sessionID,
            sourceTurnID: secondTurnID,
            mediaKind: .image,
            mediaPath: secondMedia.path,
            mediaAttachments: [secondMedia],
            in: context
        )
        let meals = try context.fetch(FetchDescriptor<MealEntry>())

        XCTAssertTrue(firstResult.ok)
        XCTAssertTrue(correctionResult.ok)
        XCTAssertEqual(meals.count, 2)
        XCTAssertEqual(Set(meals.map(\.title)), Set([
            "荞麦面套餐（含鱼、蛋、蔬菜）+ 蔬菜清汤",
            "荞麦面套餐 + 蔬菜清汤"
        ]))
        XCTAssertEqual(Set(meals.flatMap(\.mediaAttachments)), Set([firstMedia, secondMedia]))
    }

    @MainActor
    func testExplicitUpdateMealUsesRecordIDAndMergesMedia() throws {
        let context = try makeContext()
        let originalMedia = MediaAttachmentReference(
            kind: .image,
            path: "PrivateMedia/original.jpg"
        )
        let correctionMedia = MediaAttachmentReference(
            kind: .image,
            path: "PrivateMedia/correction.jpg"
        )
        let meal = MealEntry(
            mealType: .lunch,
            title: "鱼肉荞麦面",
            calories: 520,
            protein: 32,
            carbs: 58,
            fat: 16,
            mediaAttachments: [originalMedia]
        )
        context.insert(meal)
        try context.save()

        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .updateMeal,
                arguments: AgentToolArguments(
                    title: "鸡肉荞麦面",
                    recordID: meal.id.uuidString
                )
            ),
            sourceText: "不是鱼肉，改成鸡肉",
            mediaKind: .image,
            mediaPath: correctionMedia.path,
            mediaAttachments: [correctionMedia],
            in: context
        )
        let meals = try context.fetch(FetchDescriptor<MealEntry>())

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.recordRefs?.first?.recordID, meal.id.uuidString)
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals[0].title, "鸡肉荞麦面")
        XCTAssertEqual(meals[0].mediaAttachments, [originalMedia, correctionMedia])
    }

    @MainActor
    func testDeleteRecordRequiresCurrentExplicitUserIntent() throws {
        let context = try makeContext()
        let meal = MealEntry(
            mealType: .lunch,
            title: "测试午餐",
            calories: 500,
            protein: 30,
            carbs: 55,
            fat: 15
        )
        context.insert(meal)
        try context.save()
        let call = AgentToolCall(
            name: .deleteRecord,
            arguments: AgentToolArguments(
                recordID: meal.id.uuidString,
                recordType: "meal"
            )
        )

        let rejected = ConversationRecorder.executeAgentTool(
            call,
            sourceText: "这条午餐好像不对",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        XCTAssertFalse(rejected.ok)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).count, 1)

        let deleted = ConversationRecorder.executeAgentTool(
            call,
            sourceText: "删除这条午餐记录",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        XCTAssertTrue(deleted.ok)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
    }

    @MainActor
    func testMutationReceiptMakesSameTurnToolRetryIdempotent() throws {
        let context = try makeContext()
        let turnID = UUID()
        let call = mealCall(title: "鸡肉荞麦面")
        var mutationCount = 0

        let first = AgentMutationStore.execute(
            call,
            turnID: turnID,
            in: context
        ) {
            mutationCount += 1
            return ConversationRecorder.executeAgentTool(
                call,
                sourceText: "午餐",
                sourceTurnID: turnID,
                mediaKind: .none,
                mediaPath: nil,
                in: context
            )
        }
        let retry = AgentMutationStore.execute(
            call,
            turnID: turnID,
            in: context
        ) {
            mutationCount += 1
            return .failure("不应再次执行")
        }

        XCTAssertTrue(first.ok)
        XCTAssertEqual(retry, first)
        XCTAssertEqual(mutationCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AgentMutationReceipt>()).count, 1)
    }

    @MainActor
    func testLegacyMealDuplicatesMergeIntoOneMultiImageRecord() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 1_785_386_220)
        let firstMedia = MediaAttachmentReference(
            kind: .image,
            path: "PrivateMedia/legacy-1.jpg"
        )
        let secondMedia = MediaAttachmentReference(
            kind: .image,
            path: "PrivateMedia/legacy-2.jpg"
        )
        context.insert(MealEntry(
            date: date,
            mealType: .lunch,
            title: "荞麦面套餐（含鱼、蛋、蔬菜）+ 蔬菜清汤",
            calories: 520,
            protein: 32,
            carbs: 58,
            fat: 16,
            mediaAttachments: [firstMedia]
        ))
        context.insert(MealEntry(
            date: date,
            mealType: .lunch,
            title: "荞麦面套餐 + 蔬菜清汤",
            calories: 520,
            protein: 32,
            carbs: 58,
            fat: 16,
            mediaAttachments: [secondMedia]
        ))
        try context.save()

        DataIntegrityRepair.mergeObviousDuplicateRecords(in: context)
        let meals = try context.fetch(FetchDescriptor<MealEntry>())

        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(
            Set(meals[0].mediaAttachments.map(\.path)),
            Set([firstMedia.path, secondMedia.path])
        )
    }

    @MainActor
    func testWorkoutAndBodyCorrectionsDoNotCreateDuplicateRecords() throws {
        let context = try makeContext()
        let sessionID = UUID()
        let date = Date(timeIntervalSince1970: 1_785_386_220)
        let firstWorkout = AgentToolCall(
            name: .recordWorkout,
            arguments: AgentToolArguments(
                exercise: "杠铃深蹲",
                sets: 4,
                reps: 8,
                weight: 60
            )
        )
        let correctedWorkout = AgentToolCall(
            name: .recordWorkout,
            arguments: AgentToolArguments(
                exercise: "高杠深蹲",
                sets: 4,
                reps: 8,
                weight: 62.5
            )
        )
        _ = ConversationRecorder.executeAgentTool(
            firstWorkout,
            sourceText: "深蹲 4组8次 60kg",
            sourceDate: date,
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            correctedWorkout,
            sourceText: "刚才说错了，是高杠深蹲 62.5kg",
            sourceDate: date.addingTimeInterval(120),
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordBody,
                arguments: AgentToolArguments(weight: 70.2, bodyFat: 18)
            ),
            sourceText: "今天体重 70.2kg，体脂 18%",
            sourceDate: date,
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordBody,
                arguments: AgentToolArguments(weight: 70.2, bodyFat: 17.8)
            ),
            sourceText: "更正一下，体脂是 17.8%",
            sourceDate: date.addingTimeInterval(120),
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEntry>()).count, 1)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<WorkoutEntry>()).first?.representativeWeight,
            62.5
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyEntry>()).count, 1)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<BodyEntry>()).first?.bodyFat,
            17.8
        )
    }

    func testLocationResolverRequiresUniqueNearbyGymAndGoodAccuracy() {
        let nearby = GymProfile(
            name: "附近健身房",
            latitude: 31.2304,
            longitude: 121.4737
        )
        let far = GymProfile(
            name: "远处健身房",
            isCurrent: true,
            latitude: 31.2404,
            longitude: 121.4837
        )
        let snapshot = LocationSnapshot(
            latitude: 31.2305,
            longitude: 121.4738,
            horizontalAccuracy: 30,
            capturedAt: .now,
            placeName: "人民广场"
        )

        XCTAssertEqual(
            GymLocationResolver.resolve(text: "练完了", snapshot: snapshot, gyms: [nearby, far]),
            GymContextResolution(gymID: nearby.id, source: .nearby)
        )
        let ambiguous = GymProfile(
            name: "同楼健身房",
            latitude: 31.23045,
            longitude: 121.47375
        )
        XCTAssertEqual(
            GymLocationResolver.resolve(
                text: "练完了",
                snapshot: snapshot,
                gyms: [nearby, ambiguous, far]
            ),
            GymContextResolution(gymID: far.id, source: .current)
        )
        let inaccurate = LocationSnapshot(
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            horizontalAccuracy: 500,
            capturedAt: .now
        )
        XCTAssertEqual(
            GymLocationResolver.resolve(text: "练完了", snapshot: inaccurate, gyms: [nearby, far]),
            GymContextResolution(gymID: far.id, source: .current)
        )
    }

    func testWeatherContextIsOnlyRequestedForRelevantActivity() {
        XCTAssertTrue(WeatherContextProvider.isRelevant(to: "今晚适合户外跑步吗？"))
        XCTAssertFalse(WeatherContextProvider.isRelevant(to: "午餐吃了荞麦面"))
    }

    @MainActor
    func testSameDayMealsRemainIndependentWhileWorkoutAndBodyDeduplicate() throws {
        // ADR 0059：新餐不再按同日标题/热量猜测；其他既有业务键规则保持兼容。
        let context = try makeContext()
        let sessionID = UUID()
        let date = Date(timeIntervalSince1970: 1_785_386_220)

        for offset in [0.0, 300.0] {
            let meal = ConversationRecorder.executeAgentTool(
                mealCall(title: "鸡肉荞麦面"),
                sourceText: "吃了一份鸡肉荞麦面",
                sourceDate: date.addingTimeInterval(offset),
                sourceSessionID: sessionID,
                sourceTurnID: UUID(),
                mediaKind: .none,
                mediaPath: nil,
                in: context
            )
            let workout = ConversationRecorder.executeAgentTool(
                AgentToolCall(
                    name: .recordWorkout,
                    arguments: AgentToolArguments(
                        exercise: "俯卧撑",
                        sets: 4,
                        reps: 12
                    )
                ),
                sourceText: "做了俯卧撑 4 组 12 次",
                sourceDate: date.addingTimeInterval(offset),
                sourceSessionID: sessionID,
                sourceTurnID: UUID(),
                mediaKind: .none,
                mediaPath: nil,
                in: context
            )
            let body = ConversationRecorder.executeAgentTool(
                AgentToolCall(
                    name: .recordBody,
                    arguments: AgentToolArguments(weight: 70.2)
                ),
                sourceText: "体重 70.2kg",
                sourceDate: date.addingTimeInterval(offset),
                sourceSessionID: sessionID,
                sourceTurnID: UUID(),
                mediaKind: .none,
                mediaPath: nil,
                in: context
            )
            if offset > 0 {
                XCTAssertFalse(meal.observation.contains("疑似重复"))
                XCTAssertTrue(workout.observation.contains("疑似重复"))
                XCTAssertTrue(body.observation.contains("疑似重复"))
            }
        }

        DataIntegrityRepair.mergeObviousDuplicateRecords(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEntry>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyEntry>()).count, 1)
    }

    @MainActor
    func testDifferingNearbyEventsRemainIndependentWithoutCorrectionEvidence() throws {
        // 业务键不同时仍保持独立；纠错合并仍只在有纠错语义时发生。
        let context = try makeContext()
        let sessionID = UUID()
        let date = Date(timeIntervalSince1970: 1_785_386_220)

        _ = ConversationRecorder.executeAgentTool(
            mealCall(title: "鸡肉荞麦面"),
            sourceText: "吃了一份鸡肉荞麦面",
            sourceDate: date,
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            mealCall(title: "牛肉荞麦面"),
            sourceText: "又吃了一份牛肉荞麦面",
            sourceDate: date.addingTimeInterval(300),
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordWorkout,
                arguments: AgentToolArguments(exercise: "俯卧撑", sets: 4, reps: 12)
            ),
            sourceText: "做了俯卧撑 4 组 12 次",
            sourceDate: date,
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordWorkout,
                arguments: AgentToolArguments(exercise: "俯卧撑", sets: 3, reps: 10)
            ),
            sourceText: "又做了俯卧撑 3 组 10 次",
            sourceDate: date.addingTimeInterval(300),
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordBody,
                arguments: AgentToolArguments(weight: 70.2)
            ),
            sourceText: "体重 70.2kg",
            sourceDate: date,
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordBody,
                arguments: AgentToolArguments(weight: 70.5)
            ),
            sourceText: "体重 70.5kg",
            sourceDate: date.addingTimeInterval(300),
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        DataIntegrityRepair.mergeObviousDuplicateRecords(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEntry>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyEntry>()).count, 2)
    }

    func testFailedTurnCanRetryUntilAnAttemptSucceeds() {
        let turnID = UUID()
        let failed = CoachMessage(
            isFromCoach: true,
            text: "这次没有处理成功",
            agentStatus: .failed,
            turnID: turnID,
            attemptNumber: 1
        )
        XCTAssertTrue(ConversationTurnProjection.canRetry(failed, in: [failed]))

        let succeeded = CoachMessage(
            isFromCoach: true,
            text: "已记录",
            agentStatus: .succeeded,
            turnID: turnID,
            attemptNumber: 2
        )
        XCTAssertFalse(
            ConversationTurnProjection.canRetry(
                failed,
                in: [failed, succeeded]
            )
        )
        XCTAssertEqual(
            ConversationTurnProjection.successfulTurnIDs(in: [failed, succeeded]),
            Set([turnID])
        )
    }

    func testAgentPolicyPrefersExplicitUpdateToolsForCorrections() {
        let policy = ReActPromptSection.policy.defaultText

        XCTAssertTrue(policy.contains("record_id"))
        XCTAssertTrue(policy.contains("mutate_user_data(operation=update)"))
        XCTAssertTrue(policy.contains("mutate_user_data(operation=delete)"))
    }

    private func mealCall(title: String) -> AgentToolCall {
        AgentToolCall(
            name: .recordMeal,
            arguments: AgentToolArguments(
                mealType: MealType.lunch.rawValue,
                title: title,
                calories: 520,
                protein: 32,
                carbs: 58,
                fat: 16
            )
        )
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            UserProfile.self,
            GymProfile.self,
            GymEquipment.self,
            GymMedia.self,
            MealEntry.self,
            BodyEntry.self,
            WorkoutEntry.self,
            ExerciseDefinition.self,
            CoachMessage.self,
            AgentMutationReceipt.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
