import Foundation
@testable import Soma
import SwiftData

enum DataArchiveTestSupport {
    static let mealMediaPath = "PrivateMedia/test-meal.jpg"
    static let workoutMediaPath = "PrivateMedia/test-workout.mov"
    static let exerciseImagePath = "PrivateMedia/test-exercise.jpg"
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
        let exercise = ExerciseDefinition(
            canonicalName: "杠铃前蹲",
            createdAt: fixedDate
        )
        exercise.userDemoVideos = [
            MediaAttachmentReference(
                kind: .video,
                path: workoutMediaPath
            )
        ]
        exercise.imageReferences = [
            ExerciseImageReference(
                kind: .actionIllustration,
                source: .generated,
                title: "测试动作图",
                localPath: exerciseImagePath,
                createdAt: fixedDate
            ),
            ExerciseImageReference(
                kind: .muscleMap,
                source: .bundled,
                title: "测试内置肌群图",
                resourceName: "soma_muscle_squat.png",
                createdAt: fixedDate
            )
        ]
        context.insert(exercise)
        context.insert(MealEntry(
            date: fixedDate,
            mealType: .lunch,
            title: "测试午餐",
            calories: 520,
            protein: 32,
            carbs: 58,
            fat: 16,
            totalSugar: 7,
            glycemicSpeed: .moderate,
            glycemicAssessment: "虚构餐食含完整谷物与蔬菜，组成升糖速度估计为中等。",
            notes: "荞麦面和蔬菜",
            mediaAttachments: [
                MediaAttachmentReference(kind: .image, path: mealMediaPath)
            ],
            sourceTurnID: turnID,
            sourceSessionID: sessionID
        ))
        let workout = WorkoutEntry(
            date: fixedDate.addingTimeInterval(3600),
            exercise: exercise.canonicalName,
            exerciseID: exercise.id,
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
        )
        context.insert(workout)
        let program = TrainingProgram(
            name: "测试计划",
            goal: "稳定训练",
            createdAt: fixedDate
        )
        let template = WorkoutTemplateVersion(
            programID: program.id,
            version: 1,
            name: "训练 A",
            createdAt: fixedDate
        )
        program.currentTemplateVersionID = template.id
        let prescription = TemplateExercisePrescription(
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            targetSets: 1,
            targetReps: 8,
            targetWeightKG: 60,
            targetRestSeconds: 90
        )
        let templateExercise = TemplateExercise(
            id: prescription.id,
            templateVersionID: template.id,
            exerciseID: exercise.id,
            order: 1,
            targetSets: 1,
            targetReps: 8,
            targetWeightKG: 60,
            targetRestSeconds: 90
        )
        let setPrescription = TemplateSetPrescription(
            templateExerciseID: templateExercise.id,
            order: 1,
            targetReps: 8,
            targetWeightKG: 60,
            restAfterSetSeconds: 90
        )
        let workoutSession = WorkoutSession(
            startedAt: fixedDate.addingTimeInterval(3600),
            sourceTemplateFamilyID: template.familyID,
            sourceTemplateVersion: 1,
            prescriptionSnapshot: [prescription],
            status: .completed,
            guidedPhase: .completed,
            autoRecordingPolicy: .enabled,
            queuedRecordingEffortID: UUID(),
            automaticRecordingPaused: true,
            automaticRecordingPauseCode: .permissionDenied,
            automaticRecordingPauseReason: "没有相机权限；可在系统设置中开启。"
        )
        let performance = ExercisePerformance(
            sessionID: workoutSession.id,
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            prescriptionSnapshot: prescription,
            status: .completed,
            activeVideoPath: workoutMediaPath,
            activeVideoKind: .partial
        )
        workout.sourceWorkoutSessionID = workoutSession.id
        workout.sourcePerformanceID = performance.id
        let workoutSet = WorkoutSet(
            performanceID: performance.id,
            order: 1,
            plannedReps: 8,
            plannedWeightKG: 60,
            plannedRestSeconds: 90,
            actualReps: 8,
            actualWeightKG: 60,
            actualRestSeconds: 90,
            status: .completed,
            startedAt: fixedDate.addingTimeInterval(3600),
            completedAt: fixedDate.addingTimeInterval(3660),
            recordedVideoPath: workoutMediaPath,
            recordedVideoKind: .partial
        )
        let workoutEffort = WorkoutEffort(
            workoutSetID: workoutSet.id,
            order: 1,
            plannedReps: 8,
            plannedWeightKG: 60,
            actualReps: 8,
            actualWeightKG: 60,
            actualRestSeconds: 90,
            status: .completed,
            startedAt: fixedDate.addingTimeInterval(3600),
            completedAt: fixedDate.addingTimeInterval(3660),
            recordedVideoPath: workoutMediaPath,
            recordedVideoKind: .partial
        )
        context.insert(program)
        context.insert(template)
        context.insert(templateExercise)
        context.insert(setPrescription)
        context.insert(workoutSession)
        context.insert(performance)
        context.insert(workoutSet)
        context.insert(workoutEffort)
        context.insert(RecommendationSnapshot(
            targetKind: "template",
            targetID: template.id,
            inputFingerprint: "test-plan-fingerprint",
            advice: "测试建议",
            createdAt: fixedDate
        ))
        context.insert(PerformanceAnalysis(
            performanceID: performance.id,
            sourceMediaPath: workoutMediaPath,
            inputFingerprint: "test-video-fingerprint",
            evidence: "躯干角度稳定",
            limitations: "仅分析一个视角",
            feedback: "继续保持",
            createdAt: fixedDate
        ))
        let mergedSource = ExerciseDefinition(
            canonicalName: "杠铃蹲",
            createdAt: fixedDate
        )
        mergedSource.archivedAt = fixedDate
        mergedSource.mergedIntoID = exercise.id
        context.insert(mergedSource)
        context.insert(ExerciseMergeRecord(
            sourceExerciseID: mergedSource.id,
            targetExerciseID: exercise.id,
            sourceName: mergedSource.canonicalName,
            affectedWorkoutIDs: [workout.id],
            affectedTemplateExerciseIDs: [templateExercise.id],
            affectedPerformanceIDs: [performance.id],
            affectedRecommendationIDs: [],
            transferredContentRevisionIDs: [UUID()],
            transferredUserDemoVideos: [
                MediaAttachmentReference(
                    kind: .video,
                    path: workoutMediaPath
                )
            ],
            createdAt: fixedDate
        ))
        insertConversationFixtures(
            in: context,
            sessionID: sessionID,
            turnID: turnID
        )
        try BusinessIDAllocator.repairAndAssignAllIDs(in: context)
        try context.save()
        return try PersonalDataSnapshot.capture(
            from: context,
            now: fixedDate.addingTimeInterval(7200)
        )
    }

    @MainActor
    private static func insertConversationFixtures(
        in context: ModelContext,
        sessionID: UUID,
        turnID: UUID
    ) {
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
