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
        try BusinessIDAllocator.assign(meal, namespace: "meal", in: context)
        try context.save()

        let result = try ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .updateMeal,
                arguments: AgentToolArguments(
                    title: "鸡肉荞麦面",
                    recordID: XCTUnwrap(meal.businessID)
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
        XCTAssertEqual(result.recordRefs?.first?.recordID, meal.businessID)
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
        try BusinessIDAllocator.assign(meal, namespace: "meal", in: context)
        try context.save()
        let call = try AgentToolCall(
            name: .deleteMeal,
            arguments: AgentToolArguments(
                recordID: XCTUnwrap(meal.businessID),
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
    func testCreateDoesNotAbsorbCorrectionsAndUpdateUsesRecordID() throws {
        let context = try makeContext()
        let sessionID = UUID()
        let date = Date(timeIntervalSince1970: 1_785_386_220)
        let firstWorkout = ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exercise: "杠铃深蹲",
                sets: 4,
                reps: 8,
                weight: 60
            ),
            sourceText: "深蹲 4组8次 60kg",
            sourceDate: date,
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exercise: "高杠深蹲",
                sets: 4,
                reps: 8,
                weight: 62.5
            ),
            sourceText: "刚才说错了，是高杠深蹲 62.5kg",
            sourceDate: date.addingTimeInterval(120),
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let firstBody = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createBodyEntry,
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
                name: .createBodyEntry,
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

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEntry>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyEntry>()).count, 2)

        let workoutID = try XCTUnwrap(firstWorkout.recordRefs?.first?.recordID)
        let bodyID = try XCTUnwrap(firstBody.recordRefs?.first?.recordID)
        _ = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .updateWorkout,
                arguments: AgentToolArguments(
                    sets: 4,
                    reps: 8,
                    weight: 62.5,
                    recordID: workoutID
                )
            ),
            sourceText: "刚才说错了，是 62.5kg",
            sourceDate: date.addingTimeInterval(180),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .updateBody,
                arguments: AgentToolArguments(bodyFat: 17.8, recordID: bodyID)
            ),
            sourceText: "更正一下，体脂是 17.8%",
            sourceDate: date.addingTimeInterval(180),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEntry>()).count, 2)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<WorkoutEntry>()).first {
                $0.businessID == workoutID
            }?.representativeWeight,
            62.5
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyEntry>()).count, 2)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<BodyEntry>()).first {
                $0.businessID == bodyID
            }?.bodyFat,
            17.8
        )
    }

    @MainActor
    func testSameTurnDifferentExercisesStayIndependentRecords() throws {
        let context = try makeContext()
        let turnID = UUID()
        let date = Date(timeIntervalSince1970: 1_785_386_220)
        let deadlift = ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exercise: "杠铃硬拉",
                sets: 4,
                reps: 5,
                weight: 60,
                restSeconds: 120
            ),
            sourceText: "今天练了杠铃硬拉和辅助引体向上",
            sourceDate: date,
            sourceTurnID: turnID,
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let pullUp = ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exercise: "辅助引体向上",
                sets: 5,
                reps: 5,
                weight: 29,
                restSeconds: 60
            ),
            sourceText: "今天练了杠铃硬拉和辅助引体向上",
            sourceDate: date,
            sourceTurnID: turnID,
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let workouts = try context.fetch(FetchDescriptor<WorkoutEntry>())
            .sorted { $0.exercise < $1.exercise }

        XCTAssertTrue(deadlift.ok)
        XCTAssertTrue(pullUp.ok)
        XCTAssertEqual(workouts.count, 2)
        XCTAssertEqual(Set(workouts.map(\.exercise)), ["杠铃硬拉", "辅助引体向上"])
        XCTAssertEqual(
            workouts.first { $0.exercise == "杠铃硬拉" }?.representativeWeight,
            60
        )
        XCTAssertEqual(
            workouts.first { $0.exercise == "辅助引体向上" }?.representativeWeight,
            29
        )
        XCTAssertEqual(deadlift.recordRefs?.first?.recordID, workouts.first {
            $0.exercise == "杠铃硬拉"
        }?.businessID)
        XCTAssertEqual(pullUp.recordRefs?.first?.recordID, workouts.first {
            $0.exercise == "辅助引体向上"
        }?.businessID)
        XCTAssertNotEqual(
            deadlift.recordRefs?.first?.recordID,
            pullUp.recordRefs?.first?.recordID
        )
    }

    @MainActor
    func testSameTurnRepeatedCreatesStayIndependentRecords() throws {
        let context = try makeContext()
        let turnID = UUID()
        let date = Date(timeIntervalSince1970: 1_785_386_220)
        _ = ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exercise: "杠铃深蹲",
                sets: 4,
                reps: 8,
                weight: 60
            ),
            sourceText: "深蹲 4组8次 60kg，接着又做了一组 62.5",
            sourceDate: date,
            sourceTurnID: turnID,
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exercise: "杠铃深蹲",
                sets: 4,
                reps: 8,
                weight: 62.5
            ),
            sourceText: "深蹲 4组8次 60kg，接着又做了一组 62.5",
            sourceDate: date,
            sourceTurnID: turnID,
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            mealCall(title: "鸡肉荞麦面"),
            sourceText: "午餐荞麦面，下午加了酸奶",
            sourceDate: date,
            sourceTurnID: turnID,
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            mealCall(title: "鸡肉荞麦面"),
            sourceText: "午餐荞麦面，下午加了酸奶",
            sourceDate: date,
            sourceTurnID: turnID,
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createBodyEntry,
                arguments: AgentToolArguments(weight: 70.2)
            ),
            sourceText: "体重 70.2kg",
            sourceDate: date,
            sourceTurnID: turnID,
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createBodyEntry,
                arguments: AgentToolArguments(weight: 70.2)
            ),
            sourceText: "体重 70.2kg",
            sourceDate: date,
            sourceTurnID: turnID,
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEntry>()).count, 2)
        XCTAssertEqual(
            try Set(
                context.fetch(FetchDescriptor<WorkoutEntry>()).compactMap(\.representativeWeight)
            ),
            [60, 62.5]
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyEntry>()).count, 2)
    }

    @MainActor
    func testSameTurnDifferentMealsStayIndependentRecords() throws {
        let context = try makeContext()
        let turnID = UUID()
        let date = Date(timeIntervalSince1970: 1_785_386_220)
        _ = ConversationRecorder.executeAgentTool(
            mealCall(title: "鸡肉荞麦面"),
            sourceText: "午餐荞麦面，下午加了酸奶",
            sourceDate: date,
            sourceTurnID: turnID,
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createMeal,
                arguments: AgentToolArguments(
                    mealType: MealType.snack.rawValue,
                    title: "原味酸奶",
                    calories: 120
                )
            ),
            sourceText: "午餐荞麦面，下午加了酸奶",
            sourceDate: date,
            sourceTurnID: turnID,
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).count, 2)
        XCTAssertEqual(
            try Set(context.fetch(FetchDescriptor<MealEntry>()).map(\.title)),
            ["鸡肉荞麦面", "原味酸奶"]
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
            let workout = ConversationRecorder.recordWorkout(
                AgentToolArguments(
                    exercise: "俯卧撑",
                    sets: 4,
                    reps: 12
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
                    name: .createBodyEntry,
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
        // 业务键不同时 create 保持独立；纠正应走更新工具，不再靠创建路径猜测合并。
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
        _ = ConversationRecorder.recordWorkout(
            AgentToolArguments(exercise: "俯卧撑", sets: 4, reps: 12),
            sourceText: "做了俯卧撑 4 组 12 次",
            sourceDate: date,
            sourceSessionID: sessionID,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        _ = ConversationRecorder.recordWorkout(
            AgentToolArguments(exercise: "俯卧撑", sets: 3, reps: 10),
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
                name: .createBodyEntry,
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
                name: .createBodyEntry,
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

    @MainActor
    func testCancelledAutomaticRecoveryDoesNotOfferManualRetry() {
        let turnID = UUID()
        let cancelled = CoachMessage(
            isFromCoach: true,
            text: "网络暂时不可用，任务已保留，将在网络恢复后继续。",
            agentStatus: .cancelled,
            turnID: turnID,
            attemptNumber: 1
        )
        XCTAssertFalse(ConversationTurnProjection.canRetry(cancelled, in: [cancelled]))

        let job = AgentJob(
            turnID: turnID,
            sessionID: UUID(),
            userMessageID: UUID(),
            dataSpace: .personal,
            userText: "记录深蹲",
            mediaAttachments: [],
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: "",
                includeLocation: false
            )
        )
        XCTAssertTrue(job.state.awaitsAutomaticRecovery)
        XCTAssertFalse(
            ConversationTurnProjection.canRetry(cancelled, in: [cancelled], job: job)
        )
    }

    @MainActor
    func testFailedBubbleOffersManualRetryOnlyAfterAutomaticRecoveryStops() throws {
        let turnID = UUID()
        let failed = CoachMessage(
            isFromCoach: true,
            text: "这次没有处理成功",
            agentStatus: .failed,
            turnID: turnID,
            attemptNumber: 1
        )
        let job = AgentJob(
            turnID: turnID,
            sessionID: UUID(),
            userMessageID: UUID(),
            dataSpace: .personal,
            userText: "记录深蹲",
            mediaAttachments: [],
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: "",
                includeLocation: false
            )
        )
        try job.transition(to: .waitingForNetwork)
        XCTAssertFalse(
            ConversationTurnProjection.canRetry(failed, in: [failed], job: job)
        )

        try job.transition(to: .waitingForUser)
        XCTAssertFalse(job.state.awaitsAutomaticRecovery)
        XCTAssertTrue(
            ConversationTurnProjection.canRetry(failed, in: [failed], job: job)
        )
    }

    @MainActor
    func testAutomaticRecoveryClearsFailureCardsAndHidesRetry() {
        let turnID = UUID()
        let message = CoachMessage(
            isFromCoach: true,
            text: "半截回复",
            agentStatus: .failed,
            turnID: turnID,
            attemptNumber: 1
        )
        message.applyAgentEvent(.span(AgentTraceSpan(
            kind: .tool,
            title: "保存训练记录",
            status: .succeeded,
            startedAt: .now,
            endedAt: .now
        )))
        message.applyAgentEvent(.failed(
            message: "网络中断",
            cancelled: false,
            at: .now
        ))
        XCTAssertTrue(message.agentTurnItems.contains { $0.kind == .error })

        let waitingText = "网络暂时不可用，任务已保留，将在网络恢复后继续。"
        message.presentAutomaticRecovery(waitingText: waitingText)

        XCTAssertEqual(message.agentStatus, .cancelled)
        XCTAssertEqual(message.text, waitingText)
        XCTAssertFalse(message.agentTurnItems.contains { $0.kind == .error })
        XCTAssertTrue(message.agentTurnItems.contains {
            $0.kind == .tool && $0.status == .succeeded
        })
        XCTAssertFalse(ConversationTurnProjection.canRetry(message, in: [message]))
    }

    func testSystemContractKeepsToolNamesOutOfPrompt() {
        let policy = ReActPromptSection.policy.defaultText

        XCTAssertTrue(policy.contains("明确授权"))
        XCTAssertTrue(policy.contains("创建、修改、删除"))
        XCTAssertTrue(policy.contains("不能把创建当更新"))
        XCTAssertFalse(policy.contains("mutate_user_data"))
        XCTAssertFalse(policy.contains("record_id"))
    }

    private func mealCall(title: String) -> AgentToolCall {
        AgentToolCall(
            name: .createMeal,
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
            BusinessIDSequence.self,
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
