import Foundation

enum AgentQuestionFixture {
    static var isRequested: Bool {
        AppTestRuntime.isRunning && PerformanceTestFixture.requestedStreamScenario == .agentStages
            && ["questions", "questions-long"].contains(ProcessInfo.processInfo.environment["SOMA_UI_AGENT_STAGE"] ?? "")
    }

    static func items(long: Bool, at date: Date) -> [AgentTurnItem] {
        let question = AgentUserQuestion(
            id: "next", question: long ? "今天的训练安排需要结合你的精力和可用时间，你希望先从哪个方向开始？" : "接下来想做什么？",
            options: [
                AgentQuestionOption(id: "talk", text: long ? "我今天时间比较紧，希望先结合最近的训练聊聊恢复安排，再决定接下来要做哪些动作" : "我想聊聊恢复"),
                AgentQuestionOption(id: "save", text: "帮我记录体重 68 千克", action: .init(toolName: .createBodyEntry, argumentsJSON: #"{"weight":68}"#))
            ], allowsCustomInput: true
        )
        let result = AgentUserQuestionsTool.result(questions: [question])
        return [AgentTurnItem(
            kind: .tool, status: .succeeded, operationID: "fixture-question", phase: .completed,
            title: "等待你的回答", startedAt: date, endedAt: date, output: AgentTraceText.json(result)
        )]
    }
}
