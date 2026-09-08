@testable import Soma
import SwiftData
import XCTest

final class ConversationRecorderToolTests: XCTestCase {
    @MainActor
    func testAgentWorkoutToolWritesSwiftDataRecord() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ExternalSyncCursor.self,
            UserProfile.self,
            GymProfile.self,
            GymEquipment.self,
            GymMedia.self,
            MealEntry.self,
            BodyEntry.self,
            WorkoutEntry.self,
            CoachMessage.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        context.insert(BodyEntry(weight: 70))
        let result = ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exercise: "杠铃深蹲",
                setEntries: (0 ..< 4).map { _ in
                    AgentWorkoutSetInput(reps: 8, externalWeightKG: 62.5)
                },
                restSeconds: 90,
                // Mistaken Agent formula 4×8×90/60=48 must be discarded.
                durationMinutes: 48,
                formScore: 86,
                intensity: "适中",
                feedback: "动作稳定"
            ),
            sourceText: "深蹲 4组8次 62.5kg",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let records = try context.fetch(FetchDescriptor<WorkoutEntry>())

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.recordType, .workout)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.exercise, "杠铃深蹲")
        XCTAssertEqual(records.first?.setCount, 4)
        XCTAssertEqual(records.first?.setEntries.map(\.restSeconds), [90, 90, 90, nil])
        XCTAssertEqual(records.first?.representativeWeight, 62.5)
        XCTAssertNil(records.first?.durationMinutes)
        XCTAssertEqual(records.first?.estimatedCalories, 39)
        XCTAssertEqual(records.first?.calorieMET, 5.0)
        XCTAssertTrue(records.first?.calorieDurationEstimated ?? false)
    }

    @MainActor
    func testAgentWorkoutToolKeepsMissingMetricsNil() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ExternalSyncCursor.self,
            UserProfile.self,
            GymProfile.self,
            GymEquipment.self,
            GymMedia.self,
            MealEntry.self,
            BodyEntry.self,
            WorkoutEntry.self,
            CoachMessage.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let result = ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exercise: "俯卧撑",
                setEntries: (0 ..< 4).map { _ in
                    AgentWorkoutSetInput(reps: 12, externalWeightKG: nil)
                }
            ),
            sourceText: "俯卧撑 12x4",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutEntry>()).first)

        XCTAssertTrue(result.ok)
        XCTAssertEqual(record.setCount, 4)
        XCTAssertEqual(record.representativeReps, 12)
        XCTAssertEqual(record.setEntries.map(\.externalWeightKG), [0, 0, 0, 0])
        XCTAssertEqual(record.setEntries.map(\.restSeconds), [0, 0, 0, nil])
        XCTAssertNil(record.weight)
        XCTAssertNil(record.restSeconds)
        XCTAssertNil(record.durationMinutes)
        XCTAssertNil(record.intensity)
        XCTAssertNil(record.feedback)
    }

    @MainActor
    func testDurationExerciseStoresSecondsInsteadOfRepetitions() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ExternalSyncCursor.self,
            UserProfile.self,
            GymProfile.self,
            GymEquipment.self,
            GymMedia.self,
            MealEntry.self,
            BodyEntry.self,
            WorkoutEntry.self,
            ExerciseDefinition.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let exercise = ExerciseDefinition(canonicalName: "虚构平板支撑")
        exercise.targetKind = .duration
        context.insert(exercise)
        try BusinessIDAllocator.assignMissingIDs(in: context)

        let result = try ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exerciseID: XCTUnwrap(exercise.businessID),
                setEntries: [
                    AgentWorkoutSetInput(durationSeconds: 30),
                    AgentWorkoutSetInput(durationSeconds: 45)
                ]
            ),
            sourceText: "平板支撑 30 秒、45 秒",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertTrue(result.ok, result.message)
        let workout = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutEntry>()).first)
        XCTAssertEqual(workout.setEntries.map(\.targetKind), [.duration, .duration])
        XCTAssertEqual(workout.setEntries.map(\.durationSeconds), [30, 45])
        XCTAssertTrue(workout.setEntries.allSatisfy { $0.reps == nil })
    }

    @MainActor
    func testAgentWorkoutToolEstimatesOnlyCalorieDurationFromCompleteResistanceData() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ExternalSyncCursor.self,
            UserProfile.self,
            GymProfile.self,
            GymEquipment.self,
            GymMedia.self,
            MealEntry.self,
            BodyEntry.self,
            WorkoutEntry.self,
            CoachMessage.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        context.insert(BodyEntry(weight: 70))
        let result = ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exercise: "杠铃卧推",
                sets: 4,
                reps: 8,
                weight: 60,
                restSeconds: 90
            ),
            sourceText: "杠铃卧推 4x8 60kg，组间 90 秒",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutEntry>()).first)

        XCTAssertTrue(result.ok)
        XCTAssertNil(record.durationMinutes)
        XCTAssertEqual(record.estimatedCalories, 27)
        XCTAssertEqual(record.calorieDurationMinutes ?? 0, 398.0 / 60.0, accuracy: 0.001)
        XCTAssertTrue(record.calorieDurationEstimated)
        XCTAssertTrue(result.observation.contains("推算"))
    }

    @MainActor
    func testAgentToolsPersistGymMealAndBodyMedia() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ExternalSyncCursor.self,
            UserProfile.self,
            GymProfile.self,
            GymEquipment.self,
            GymMedia.self,
            MealEntry.self,
            BodyEntry.self,
            WorkoutEntry.self,
            CoachMessage.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let mediaPath = "PrivateMedia/evidence.jpg"

        let gymResult = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .updateGym,
                arguments: AgentToolArguments(
                    gymName: "公司健身房",
                    summary: "有自由重量与拉力器区域",
                    equipment: [
                        AgentEquipmentInput(
                            name: "可调哑铃",
                            category: "自由重量",
                            capabilities: "推、拉与单侧训练",
                            confidence: 0.92
                        )
                    ]
                )
            ),
            sourceText: "这是公司健身房",
            mediaKind: .image,
            mediaPath: mediaPath,
            in: context
        )
        let mealResult = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createMeal,
                arguments: AgentToolArguments(
                    mealType: MealType.lunch.rawValue,
                    title: "鸡胸肉杂粮饭",
                    calories: 560,
                    protein: 45,
                    carbs: 60,
                    fat: 15,
                    note: "按可见份量估算"
                )
            ),
            sourceText: "午餐",
            mediaKind: .image,
            mediaPath: mediaPath,
            in: context
        )
        let bodyResult = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createBodyEntry,
                arguments: AgentToolArguments(
                    postureNote: "正面站姿整体对称",
                    safetyNote: "拍摄条件不同会影响比较"
                )
            ),
            sourceText: "今天的体型照",
            mediaKind: .image,
            mediaPath: mediaPath,
            in: context
        )

        XCTAssertTrue(gymResult.ok)
        XCTAssertTrue(mealResult.ok)
        XCTAssertTrue(bodyResult.ok)

        let gym = try XCTUnwrap(context.fetch(FetchDescriptor<GymProfile>()).first)
        XCTAssertTrue(gym.isCurrent)
        XCTAssertEqual(gym.coverImagePath, mediaPath)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<GymEquipment>()).first?.name,
            "可调哑铃"
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<GymMedia>()).first?.path,
            mediaPath
        )

        let meal = try XCTUnwrap(context.fetch(FetchDescriptor<MealEntry>()).first)
        XCTAssertEqual(meal.imagePath, mediaPath)
        XCTAssertEqual(meal.calories, 560)

        let body = try XCTUnwrap(context.fetch(FetchDescriptor<BodyEntry>()).first)
        XCTAssertEqual(body.imagePath, mediaPath)
        XCTAssertNil(body.weight)
        XCTAssertTrue(body.analysis.contains("拍摄条件不同"))
    }
}

extension ConversationRecorderToolTests {
    @MainActor
    func testAgentToolsPersistMixedMediaCollections() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ExternalSyncCursor.self,
            UserProfile.self,
            GymProfile.self,
            GymEquipment.self,
            GymMedia.self,
            MealEntry.self,
            BodyEntry.self,
            WorkoutEntry.self,
            CoachMessage.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let attachments = [
            MediaAttachmentReference(kind: .image, path: "PrivateMedia/front.jpg"),
            MediaAttachmentReference(kind: .video, path: "PrivateMedia/set.mov"),
            MediaAttachmentReference(kind: .image, path: "PrivateMedia/side.jpg")
        ]

        let result = ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exercise: "杠铃深蹲",
                sets: 3,
                reps: 5
            ),
            sourceText: "三组动作，从正面和侧面拍了照片与视频",
            mediaKind: .image,
            mediaPath: attachments.first?.path,
            mediaAttachments: attachments,
            in: context
        )
        let workout = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkoutEntry>()).first
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(workout.mediaAttachments, attachments)
        XCTAssertEqual(workout.mediaAttachments.map(\.kind), [.image, .video, .image])
        XCTAssertEqual(workout.mediaPath, attachments.first?.path)
    }
}
