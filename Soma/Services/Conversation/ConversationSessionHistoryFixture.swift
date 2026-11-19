import Foundation
import SwiftData

@MainActor
enum ConversationSessionHistoryFixture {
    static func seedIfRequested(in context: ModelContext) {
        #if DEBUG
            if AppTestRuntime.isRunning,
               context.container.configurations.allSatisfy(\.isStoredInMemoryOnly),
               let mode = ProcessInfo.processInfo.environment["SOMA_UI_COACH_NEXT_ACTIONS"]
            {
                seedNextActions(in: context, missingWorkout: mode == "missing-workout", habitualRoutine: mode == "habitual")
            }
        #endif
        guard AppTestRuntime.isRunning,
              ProcessInfo.processInfo.environment["SOMA_UI_SESSION_HISTORY_FIXTURE"] == "1"
        else { return }
        let now = Date.now
        for index in 1 ... 35 {
            let session = ConversationSession(
                startedAt: now.addingTimeInterval(Double(-index) * 86400),
                title: String(format: "虚构分页对话 %02d", index)
            )
            context.insert(session)
            context.insert(CoachMessage(sessionID: session.id, isFromCoach: false, text: "虚构分页验证消息"))
        }
        try? context.save()
    }

    #if DEBUG
        private static func seedNextActions(in context: ModelContext, missingWorkout: Bool, habitualRoutine: Bool) {
            let now = Date.now
            let calendar = Calendar.current
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let today = ConversationSession(startedAt: now, title: "虚构今日建议")
            let history = ConversationSession(startedAt: yesterday, title: "虚构历史建议")
            context.insert(today)
            context.insert(history)
            context.insert(UserProfile(updatedAt: now, displayName: "虚构建议用户", biologicalSex: .male,
                                       birthDate: calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)),
                                       height: 170, fitnessGoal: FitnessGoal.fatLoss.rawValue))
            context.insert(BodyEntry(date: now, weight: 70))
            let squatID = UUID()
            let pressID = UUID()
            if habitualRoutine {
                for offset in [-3, -6, -9] {
                    guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                    context.insert(WorkoutEntry(date: date, exercise: "虚构训练建议深蹲", exerciseID: squatID, sets: 3, reps: 8, weight: 40))
                    context.insert(WorkoutEntry(date: date, exercise: "虚构训练建议推举", exerciseID: pressID, sets: 2, reps: 8, weight: 20))
                }
                context.insert(WorkoutEntry(date: now, exercise: "虚构训练建议推举", exerciseID: pressID, sets: 2, reps: 8, weight: 20))
            }
            for (session, offset, recordDate) in [(history, 0, yesterday), (today, 1, now)] {
                let turn = UUID()
                let workoutID = Int64(9001 + offset * 2)
                let mealID = workoutID + 1
                if !missingWorkout {
                    let workout = WorkoutEntry(date: recordDate, exercise: "虚构训练建议深蹲", exerciseID: squatID, sets: 3, reps: 8, weight: 40,
                                               sourceTurnID: turn, sourceSessionID: session.id)
                    workout.businessID = workoutID
                    context.insert(workout)
                }
                let meal = MealEntry(date: recordDate, mealType: .breakfast, title: "虚构建议餐食", calories: 550,
                                     sourceTurnID: turn, sourceSessionID: session.id)
                meal.businessID = mealID
                context.insert(meal)
                let sentAt = now.addingTimeInterval(Double(offset - 2))
                let userText = habitualRoutine ? "记录这一轮训练和一餐。" : "今天练完了，顺便记录一餐。"
                context.insert(CoachMessage(date: sentAt, sessionID: session.id, isFromCoach: false, text: userText, turnID: turn))
                let result = AgentToolResult(ok: true, code: "success", message: "虚构保存结果", recordRefs: [
                    .init(recordType: "workout", recordID: workoutID, title: "虚构训练建议深蹲"),
                    .init(recordType: "meal", recordID: mealID, title: "虚构建议餐食")
                ])
                let item = AgentTurnItem(sequence: 1, kind: .tool, status: .succeeded, title: "虚构记录",
                                         startedAt: sentAt, endedAt: sentAt, output: AgentTraceText.json(result))
                context.insert(CoachMessage(date: sentAt.addingTimeInterval(0.01), sessionID: session.id, isFromCoach: true,
                                            text: "已保存虚构记录。", agentStatus: .succeeded, agentTurnItems: [item], turnID: turn))
            }
            do { try context.save() } catch { assertionFailure("Could not seed coach suggestion fixture") }
        }
    #endif
}
