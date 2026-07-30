import Foundation
@testable import Soma
import SwiftData

enum DataArchiveTestSupport {
    static let mealMediaPath = "PrivateMedia/test-meal.jpg"
    static let workoutMediaPath = "PrivateMedia/test-workout.mov"
    static let fixedDate = Date(timeIntervalSince1970: 1_785_390_240)

    @MainActor
    static func makeSnapshot() throws -> PersonalDataSnapshot {
        let suiteName = "DataArchiveTestSupport.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let context = spaces.personalContainer.mainContext
        let sessionID = UUID()
        let turnID = UUID()

        context.insert(ExternalSyncCursor(
            source: "healthkit",
            stream: "workouts",
            cursorData: Data([1, 2, 3]),
            updatedAt: fixedDate
        ))
        context.insert(UserProfile(
            updatedAt: fixedDate,
            displayName: "测试用户",
            biologicalSex: .unspecified,
            height: 170,
            referenceWeight: 65,
            fitnessGoal: "保持活力"
        ))
        let gym = GymProfile(
            name: "测试健身房",
            notes: "自由重量区",
            isCurrent: true,
            latitude: 31.23,
            longitude: 121.48,
            locationLabel: "测试地点"
        )
        context.insert(gym)
        context.insert(GymEquipment(
            gymID: gym.id,
            name: "深蹲架",
            category: "力量",
            capabilities: "深蹲"
        ))
        context.insert(GymMedia(
            gymID: gym.id,
            path: mealMediaPath,
            createdAt: fixedDate
        ))
        context.insert(BodyEntry(
            date: fixedDate,
            weight: 65,
            notes: "晨起"
        ))
        context.insert(MealEntry(
            date: fixedDate,
            mealType: .lunch,
            title: "测试午餐",
            calories: 520,
            protein: 32,
            carbs: 58,
            fat: 16,
            notes: "荞麦面和蔬菜",
            mediaAttachments: [
                MediaAttachmentReference(kind: .image, path: mealMediaPath)
            ],
            sourceTurnID: turnID,
            sourceSessionID: sessionID
        ))
        context.insert(WorkoutEntry(
            date: fixedDate.addingTimeInterval(3600),
            exercise: "深蹲",
            sets: 4,
            reps: 8,
            weight: 60,
            notes: "动作稳定",
            mediaAttachments: [
                MediaAttachmentReference(kind: .video, path: workoutMediaPath)
            ],
            formScore: 88,
            feedback: "保持核心稳定",
            sourceTurnID: turnID,
            sourceSessionID: sessionID
        ))
        context.insert(ConversationSession(
            id: sessionID,
            startedAt: fixedDate,
            updatedAt: fixedDate.addingTimeInterval(3600),
            title: "午餐与训练"
        ))
        context.insert(CoachMessage(
            date: fixedDate,
            sessionID: sessionID,
            isFromCoach: false,
            text: "午餐吃了荞麦面，之后做了深蹲",
            mediaAttachments: [
                MediaAttachmentReference(kind: .image, path: mealMediaPath),
                MediaAttachmentReference(kind: .video, path: workoutMediaPath)
            ],
            turnID: turnID
        ))
        context.insert(CoachMessage(
            date: fixedDate.addingTimeInterval(2),
            sessionID: sessionID,
            isFromCoach: true,
            text: "饮食与训练已记录。",
            agentStatus: .succeeded,
            turnID: turnID,
            attemptNumber: 1
        ))
        let trace = AgentTrace(
            startedAt: fixedDate,
            provider: "test",
            model: "test-model",
            endpoint: "https://example.invalid",
            dataSpaceRaw: DataSpace.personal.rawValue,
            userInput: "测试输入",
            contextSnapshot: "测试上下文",
            mediaKind: .image,
            imageCount: 1,
            imageAttachmentCount: 1,
            videoAttachmentCount: 1,
            turnID: turnID
        )
        trace.apply(.completed(
            answer: "饮食与训练已记录。",
            at: fixedDate.addingTimeInterval(2)
        ))
        context.insert(trace)
        context.insert(AgentMutationReceipt(
            turnID: turnID,
            signature: "record-test",
            result: .success("已记录", recordType: .meal),
            createdAt: fixedDate
        ))
        try context.save()
        return try PersonalDataSnapshot.capture(
            from: context,
            now: fixedDate.addingTimeInterval(7200)
        )
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SomaTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
        return url
    }
}
