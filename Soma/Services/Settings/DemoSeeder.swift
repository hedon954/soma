import Foundation
import SwiftData

@MainActor
enum DemoSeeder {
    private static let currentBaselineKey = "demo.currentBaseline.v1"

    static func seedIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: currentBaselineKey) else { return }
        seedTraceLogsIfNeeded(in: context)
        backfillDemoProfileAndCaloriesIfNeeded(in: context)
        backfillDemoAgentTurnIfNeeded(in: context)
        let descriptor = FetchDescriptor<GymProfile>()
        let existingGyms = (try? context.fetch(descriptor)) ?? []
        guard existingGyms.isEmpty else {
            backfillBundledMediaIfNeeded(in: context, gyms: existingGyms)
            UserDefaults.standard.set(true, forKey: currentBaselineKey)
            return
        }

        let media = installBundledMedia()

        let gym = GymProfile(
            name: "我的健身房",
            notes: "家附近 · 步行 8 分钟",
            coverImagePath: media.gymWide,
            isCurrent: true
        )
        let officeGym = GymProfile(name: "公司健身房", notes: "办公楼 B1 · 工作日", isCurrent: false)
        context.insert(gym)
        context.insert(officeGym)

        if let path = media.gymWide {
            context.insert(GymMedia(gymID: gym.id, path: path))
        }
        if let path = media.gymEquipment {
            context.insert(GymMedia(gymID: gym.id, path: path))
        }

        [
            ("深蹲架", "力量", "深蹲、卧推、肩推", media.gymWide),
            ("可调哑铃", "自由重量", "全身自由重量训练", media.gymEquipment),
            ("高位下拉机", "力量", "背部与手臂拉力训练", media.gymEquipment),
            ("跑步机", "有氧", "热身、慢跑与间歇", media.gymWide)
        ].forEach {
            context.insert(GymEquipment(
                gymID: gym.id,
                name: $0.0,
                category: $0.1,
                capabilities: $0.2,
                imagePath: $0.3
            ))
        }
        [
            ("史密斯机", "力量", "深蹲、卧推、提踵"),
            ("划船机", "有氧", "全身有氧与拉力训练")
        ].forEach {
            context.insert(GymEquipment(gymID: officeGym.id, name: $0.0, category: $0.1, capabilities: $0.2))
        }

        let calendar = Calendar.current
        for offset in 0 ..< 35 where offset % 3 != 1 {
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            context.insert(WorkoutEntry(
                date: date,
                exercise: offset % 2 == 0 ? "杠铃深蹲" : "高位下拉",
                sets: 4,
                reps: offset % 2 == 0 ? 8 : 10,
                weight: offset % 2 == 0 ? 60 + Double((35 - offset) / 7) * 2.5 : 45,
                restSeconds: 90,
                durationMinutes: 48,
                notes: offset == 0 ? "今天状态不错，最后两次略吃力。" : "",
                mediaKind: offset == 0 && media.workout != nil ? .image : .none,
                mediaPath: offset == 0 ? media.workout : nil,
                formScore: 82 + offset % 10,
                intensity: "适中",
                feedback: "节奏稳定，保持核心张力后再小幅加重。",
                estimatedCalories: offset % 2 == 0 ? 296 : 207,
                calorieMET: offset % 2 == 0 ? 5.0 : 3.5,
                calorieDurationMinutes: 48,
                calorieDurationEstimated: false
            ))
        }
        for offset in 0 ..< 14 {
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            context.insert(MealEntry(
                date: date,
                mealType: .dinner,
                title: offset % 2 == 0 ? "鸡胸肉杂粮饭" : "牛肉蔬菜面",
                calories: offset % 2 == 0 ? 568 : 625,
                protein: offset % 2 == 0 ? 46 : 38,
                carbs: 61,
                fat: 16,
                notes: offset == 0 ? "演示餐食照片 · AI 按可见份量估算" : "",
                imagePath: offset == 0 ? media.meal : nil
            ))
        }
        for offset in stride(from: 28, through: 0, by: -7) {
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            context.insert(BodyEntry(
                date: date,
                weight: 74.8 - Double(28 - offset) * 0.035,
                bodyFat: 19.2 - Double(28 - offset) * 0.02,
                notes: offset == 0 ? "保持相同距离和光线记录。" : "",
                imagePath: offset == 0 ? media.body : nil,
                analysis: offset == 0 ? "站姿整体自然；照片仅用于长期变化对照，不做外貌评价。" : ""
            ))
        }
        context.insert(CoachMessage(
            isFromCoach: true,
            text: "早上好。你本周已经训练 3 次，今天建议做轻强度恢复或完整休息。"
        ))
        try? context.save()
        UserDefaults.standard.set(true, forKey: "demo.bundledMedia.v1")
        UserDefaults.standard.set(true, forKey: currentBaselineKey)
    }

    private static func backfillDemoProfileAndCaloriesIfNeeded(in context: ModelContext) {
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        if profiles.isEmpty {
            context.insert(UserProfile(
                displayName: "Hedon",
                biologicalSex: .unspecified,
                birthDate: Calendar.current.date(
                    from: DateComponents(year: 1998, month: 5, day: 18)
                ),
                height: 178,
                fitnessGoal: "稳定提升力量与体能",
                healthNotes: ""
            ))
        }
        for profile in profiles where profile.birthDate == nil {
            if let age = profile.age {
                profile.birthDate = Calendar.current.date(
                    byAdding: .year,
                    value: -age,
                    to: .now
                )
                profile.age = nil
            }
        }

        let workouts = (try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? []
        for workout in workouts where workout.estimatedCalories == nil {
            let estimate = WorkoutCalorieCalculator.estimate(
                exercise: workout.exercise,
                intensity: workout.intensity,
                durationMinutes: workout.durationMinutes,
                sets: workout.setCount,
                reps: workout.representativeReps,
                restSeconds: workout.restSeconds,
                weightKG: 74
            )
            workout.estimatedCalories = estimate?.calories
            workout.calorieMET = estimate?.met
            workout.calorieScope = .metGross
            workout.calorieDurationMinutes = estimate?.durationMinutes
            workout.calorieDurationEstimated = estimate?.durationWasEstimated ?? false
        }
        try? context.save()
    }

    private static func backfillDemoAgentTurnIfNeeded(in context: ModelContext) {
        let messages = (try? context.fetch(FetchDescriptor<CoachMessage>())) ?? []
        guard !messages.contains(where: { !$0.agentTurnItems.isEmpty }) else { return }

        let startedAt = Date().addingTimeInterval(-120)
        let firstTextID = UUID()
        let skillID = UUID()
        let toolID = UUID()
        let finalTextID = UUID()
        context.insert(CoachMessage(
            date: startedAt,
            isFromCoach: false,
            text: "帮我看看这周的训练情况"
        ))
        context.insert(CoachMessage(
            date: startedAt.addingTimeInterval(1),
            isFromCoach: true,
            text: "我先读取本周训练记录。本周已经训练 3 次，训练容量保持稳定，今天适合轻强度恢复。",
            agentStatus: .succeeded,
            agentTurnItems: [
                AgentTurnItem(
                    id: firstTextID,
                    sequence: 1,
                    kind: .text,
                    status: .succeeded,
                    text: "我先读取本周训练记录。",
                    startedAt: startedAt,
                    endedAt: startedAt.addingTimeInterval(0.3)
                ),
                AgentTurnItem(
                    id: skillID,
                    sequence: 2,
                    kind: .skill,
                    status: .succeeded,
                    title: AgentSkill.trendAnalysis.title,
                    startedAt: startedAt.addingTimeInterval(0.3),
                    endedAt: startedAt.addingTimeInterval(0.5),
                    output: AgentSkill.trendAnalysis.defaultText
                ),
                AgentTurnItem(
                    id: toolID,
                    sequence: 3,
                    kind: .tool,
                    status: .succeeded,
                    title: AgentToolName.listWorkouts.displayTitle,
                    startedAt: startedAt.addingTimeInterval(0.5),
                    endedAt: startedAt.addingTimeInterval(0.8),
                    output: AgentTraceText.json(AgentToolResult.success(
                        "最近 7 天训练 3 次，训练容量保持稳定。"
                    ))
                ),
                AgentTurnItem(
                    id: finalTextID,
                    sequence: 4,
                    kind: .text,
                    status: .succeeded,
                    text: "本周已经训练 3 次，训练容量保持稳定，今天适合轻强度恢复。",
                    startedAt: startedAt.addingTimeInterval(0.8),
                    endedAt: startedAt.addingTimeInterval(1)
                )
            ]
        ))
        try? context.save()
    }

    private static func seedTraceLogsIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AgentTrace>())) ?? []
        if !existing.isEmpty {
            if let sample = existing.first(where: {
                $0.dataSpaceRaw == DataSpace.demo.rawValue
                    && $0.userInput == "我今天该怎么练？"
                    && !$0.spans.contains(where: { $0.kind == .skill })
            }) {
                sample.replaceSpans(demoSuccessSpans(startedAt: sample.startedAt))
                sample.apply(.completed(
                    answer: "今天建议做轻强度恢复或完整休息。",
                    at: sample.startedAt.addingTimeInterval(1.92)
                ))
                try? context.save()
            }
            return
        }

        let calendar = Calendar.current
        let successStart = calendar.date(byAdding: .minute, value: -18, to: .now) ?? .now
        let success = AgentTrace(
            startedAt: successStart,
            provider: "OpenAI",
            model: "gpt-4.1-mini",
            endpoint: "https://api.openai.com/v1/chat/completions",
            dataSpaceRaw: DataSpace.demo.rawValue,
            userInput: "我今天该怎么练？",
            contextSnapshot: "当前健身房：我的健身房；本周训练 3 次。",
            mediaKind: .none,
            imageCount: 0
        )
        success.replaceSpans(demoSuccessSpans(startedAt: successStart))
        let successEnd = successStart.addingTimeInterval(1.92)
        success.apply(.completed(
            answer: "今天建议做轻强度恢复或完整休息。",
            at: successEnd
        ))

        let failureStart = calendar.date(byAdding: .minute, value: -7, to: .now) ?? .now
        let failure = AgentTrace(
            startedAt: failureStart,
            provider: "DeepSeek",
            model: "deepseek-chat",
            endpoint: "https://api.deepseek.com/chat/completions",
            dataSpaceRaw: DataSpace.demo.rawValue,
            userInput: "分析这段训练视频",
            contextSnapshot: "当前健身房：我的健身房。",
            mediaKind: .video,
            imageCount: 4
        )
        let failureEnd = failureStart.addingTimeInterval(0.03)
        let failureMessage = "DeepSeek 的 deepseek-chat 不支持图片或视频分析。"
        failure.apply(.span(AgentTraceSpan(
            step: 1,
            kind: .model,
            title: "LLM 决策",
            status: .failed,
            startedAt: failureStart,
            endedAt: failureEnd,
            input: "完整视频 1 项；原始输入是视频：是。",
            errorMessage: failureMessage
        )))
        failure.apply(.span(AgentTraceSpan(
            kind: .output,
            title: "执行失败",
            status: .failed,
            startedAt: failureEnd,
            endedAt: failureEnd,
            errorMessage: failureMessage
        )))
        failure.apply(.failed(message: failureMessage, cancelled: false, at: failureEnd))

        context.insert(success)
        context.insert(failure)
        try? context.save()
    }

    private static func demoSuccessSpans(startedAt: Date) -> [AgentTraceSpan] {
        [
            AgentTraceSpan(
                step: 1,
                kind: .model,
                title: "LLM 推理",
                status: .succeeded,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(0.46),
                input: "[SYSTEM]\n\(ReActAgentPrompt.system)\n\n[USER]\n我今天该怎么练？",
                output: "生成 1 个原生 tool_call：load_skill",
                metadata: #"{"stream":true,"prompt_tokens":986,"completion_tokens":51,"total_tokens":1037}"#
            ),
            AgentTraceSpan(
                step: 1,
                kind: .skill,
                title: AgentSkill.trainingPlan.title,
                status: .succeeded,
                startedAt: startedAt.addingTimeInterval(0.47),
                endedAt: startedAt.addingTimeInterval(0.48),
                input: #"{"name":"load_skill","arguments":{"skill_id":"training_plan"}}"#,
                output: AgentSkill.trainingPlan.defaultText,
                metadata: #"{"deduplicated":false,"skill_customized":false,"skill_id":"training_plan"}"#
            ),
            AgentTraceSpan(
                step: 2,
                kind: .model,
                title: "LLM 推理",
                status: .succeeded,
                startedAt: startedAt.addingTimeInterval(0.49),
                endedAt: startedAt.addingTimeInterval(1.12),
                input: "继续处理上一轮 assistant.tool_calls 与 role=tool 结果。",
                output: "生成 1 个原生 tool_call：list_workouts",
                metadata: #"{"stream":true,"prompt_tokens":1458,"completion_tokens":55,"total_tokens":1513}"#
            ),
            AgentTraceSpan(
                step: 2,
                kind: .tool,
                title: AgentToolName.listWorkouts.rawValue,
                status: .succeeded,
                startedAt: startedAt.addingTimeInterval(1.13),
                endedAt: startedAt.addingTimeInterval(1.14),
                input: #"{"name":"list_workouts","arguments":{"limit":5}}"#,
                output: #"{"ok":true,"observation":"最近 7 天训练 3 次，最近一次为杠铃深蹲 4×8。"}"#
            ),
            AgentTraceSpan(
                step: 3,
                kind: .model,
                title: "LLM 推理",
                status: .succeeded,
                startedAt: startedAt.addingTimeInterval(1.15),
                endedAt: startedAt.addingTimeInterval(1.91),
                input: "继续处理上一轮 assistant.tool_calls 与 role=tool 结果。",
                output: "今天建议做轻强度恢复或完整休息。",
                metadata: #"{"stream":true,"prompt_tokens":1612,"completion_tokens":38,"total_tokens":1650}"#
            ),
            AgentTraceSpan(
                kind: .output,
                title: "最终回复",
                status: .succeeded,
                startedAt: startedAt.addingTimeInterval(1.92),
                endedAt: startedAt.addingTimeInterval(1.92),
                output: "今天建议做轻强度恢复或完整休息。"
            )
        ]
    }

    private static func backfillBundledMediaIfNeeded(
        in context: ModelContext,
        gyms: [GymProfile]
    ) {
        guard !UserDefaults.standard.bool(forKey: "demo.bundledMedia.v1"),
              let gym = gyms.first(where: {
                  $0.name == "我的健身房" && $0.notes == "家附近 · 步行 8 分钟"
              }) else { return }

        let equipment = (try? context.fetch(FetchDescriptor<GymEquipment>())) ?? []
        let missingEquipment = equipment.filter {
            $0.gymID == gym.id && $0.imagePath == nil
        }

        var workoutDescriptor = FetchDescriptor<WorkoutEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = 1
        let workout = (try? context.fetch(workoutDescriptor))?.first

        var mealDescriptor = FetchDescriptor<MealEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        mealDescriptor.fetchLimit = 1
        let meal = (try? context.fetch(mealDescriptor))?.first

        var bodyDescriptor = FetchDescriptor<BodyEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        bodyDescriptor.fetchLimit = 1
        let body = (try? context.fetch(bodyDescriptor))?.first

        let needsGymWide = gym.coverImagePath == nil
            || missingEquipment.contains {
                !["可调哑铃", "高位下拉机"].contains($0.name)
            }
        let needsGymEquipment = gym.coverImagePath == nil
            || missingEquipment.contains {
                ["可调哑铃", "高位下拉机"].contains($0.name)
            }
        let media = installBundledMedia(
            gymWide: needsGymWide,
            gymEquipment: needsGymEquipment,
            meal: meal != nil && meal?.imagePath == nil,
            workout: workout != nil && workout?.mediaPath == nil,
            body: body != nil && body?.imagePath == nil
        )
        guard media.hasAnyValue else {
            UserDefaults.standard.set(true, forKey: "demo.bundledMedia.v1")
            return
        }

        if gym.coverImagePath == nil {
            gym.coverImagePath = media.gymWide
            if let path = media.gymWide {
                context.insert(GymMedia(gymID: gym.id, path: path))
            }
            if let path = media.gymEquipment {
                context.insert(GymMedia(gymID: gym.id, path: path))
            }
        }

        for item in missingEquipment {
            item.imagePath = ["可调哑铃", "高位下拉机"].contains(item.name)
                ? media.gymEquipment
                : media.gymWide
        }

        if let workout,
           workout.mediaPath == nil,
           let path = media.workout
        {
            workout.mediaKind = .image
            workout.mediaPath = path
            workout.notes = "今天状态不错，最后两次略吃力。"
        }

        if let meal,
           meal.imagePath == nil
        {
            meal.imagePath = media.meal
            meal.notes = "演示餐食照片 · AI 按可见份量估算"
        }

        if let body,
           body.imagePath == nil
        {
            body.imagePath = media.body
            body.notes = "保持相同距离和光线记录。"
            body.analysis = "站姿整体自然；照片仅用于长期变化对照，不做外貌评价。"
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: "demo.bundledMedia.v1")
    }

    private static func installBundledMedia() -> DemoMediaPaths {
        installBundledMedia(
            gymWide: true,
            gymEquipment: true,
            meal: true,
            workout: true,
            body: true
        )
    }

    private static func installBundledMedia(
        gymWide: Bool,
        gymEquipment: Bool,
        meal: Bool,
        workout: Bool,
        body: Bool
    ) -> DemoMediaPaths {
        DemoMediaPaths(
            gymWide: gymWide ? installImage(named: "gym-wide") : nil,
            gymEquipment: gymEquipment ? installImage(named: "gym-equipment") : nil,
            meal: meal ? installImage(named: "meal-chicken-bowl") : nil,
            workout: workout ? installImage(named: "workout-squat") : nil,
            body: body ? installImage(named: "body-progress") : nil
        )
    }

    private static func installImage(named name: String) -> String? {
        let url = Bundle.main.url(
            forResource: name,
            withExtension: "jpg",
            subdirectory: "DemoMedia"
        ) ?? Bundle.main.url(forResource: name, withExtension: "jpg")
        guard let url,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? MediaStore.saveImage(data)
    }
}

private struct DemoMediaPaths {
    let gymWide: String?
    let gymEquipment: String?
    let meal: String?
    let workout: String?
    let body: String?

    var hasAnyValue: Bool {
        [gymWide, gymEquipment, meal, workout, body].contains { $0 != nil }
    }
}
