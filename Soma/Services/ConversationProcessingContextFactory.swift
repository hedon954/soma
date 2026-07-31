import Foundation
import SwiftData

@MainActor
enum ConversationProcessingContextFactory {
    static func make(
        sessionID: UUID,
        dataSpace: DataSpace,
        ai: AIService,
        in context: ModelContext
    ) -> ConversationProcessingContext? {
        let sessions = (try? context.fetch(FetchDescriptor<ConversationSession>())) ?? []
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return nil
        }
        let gyms = (
            try? context.fetch(
                FetchDescriptor<GymProfile>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        let equipment = (
            try? context.fetch(
                FetchDescriptor<GymEquipment>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        return ConversationProcessingContext(
            structuredContext: structuredContext(
                gyms: gyms,
                equipment: equipment,
                in: context
            ),
            session: session,
            dataSpace: dataSpace,
            gyms: gyms,
            equipment: equipment,
            ai: ai,
            modelContext: context
        )
    }

    static func structuredContext(in context: ModelContext) -> String {
        let gyms = (
            try? context.fetch(
                FetchDescriptor<GymProfile>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        let equipment = (
            try? context.fetch(
                FetchDescriptor<GymEquipment>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        return structuredContext(
            gyms: gyms,
            equipment: equipment,
            in: context
        )
    }

    private static func structuredContext(
        gyms: [GymProfile],
        equipment: [GymEquipment],
        in context: ModelContext
    ) -> String {
        let workouts = (
            try? context.fetch(
                FetchDescriptor<WorkoutEntry>(
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            )
        ) ?? []
        let meals = (
            try? context.fetch(
                FetchDescriptor<MealEntry>(
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            )
        ) ?? []
        let bodyEntries = (
            try? context.fetch(
                FetchDescriptor<BodyEntry>(
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            )
        ) ?? []
        let profiles = (
            try? context.fetch(
                FetchDescriptor<UserProfile>(
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
            )
        ) ?? []
        let gym = GymSelection.current(in: gyms)
        let currentEquipment = gym.map { target in
            equipment
                .filter { $0.gymID == target.id }
                .map(\.name)
                .joined(separator: "、")
        } ?? "无"
        let latestWorkout = workouts.first.map(workoutSummary) ?? "暂无"
        let todayCalories = meals
            .filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.calories }
        let weight = bodyEntries.compactMap(\.weight).first.map {
            String(format: "%.1fkg", $0)
        } ?? "暂无"
        let profile = profiles.first.map(profileSummary) ?? "未填写"
        return """
        身体信息：\(profile)
        健身房：\(gym?.name ?? "无")；器械：\(currentEquipment)；最近训练：\(latestWorkout)；今日饮食：\(todayCalories)kcal；体重：\(weight)
        """
    }

    private static func workoutSummary(_ workout: WorkoutEntry) -> String {
        var parts = [workout.exercise]
        if let setEvidenceSummary = workout.setEvidenceSummary {
            parts.append(setEvidenceSummary)
        } else if let sets = workout.sets, let reps = workout.reps {
            parts.append("\(sets)×\(reps)")
        }
        if workout.setEntries.isEmpty, let weight = workout.weight {
            parts.append(weight == 0 ? "自重" : String(format: "%.1fkg", weight))
        }
        return parts.joined(separator: " ")
    }

    private static func profileSummary(_ profile: UserProfile) -> String {
        var parts: [String] = []
        if !profile.displayName.isEmpty {
            parts.append("称呼 \(profile.displayName)")
        }
        if let birthDate = profile.birthDate {
            parts.append("出生日期 \(birthDate.formatted(date: .numeric, time: .omitted))")
        }
        if let currentAge = profile.currentAge {
            parts.append("当前 \(currentAge) 岁")
        }
        if let height = profile.height {
            parts.append(String(format: "%.1fcm", height))
        }
        if !profile.fitnessGoal.isEmpty {
            parts.append("目标 \(profile.fitnessGoal)")
        }
        if !profile.healthNotes.isEmpty {
            parts.append("限制 \(profile.healthNotes)")
        }
        return parts.isEmpty ? "未填写" : parts.joined(separator: "；")
    }
}
