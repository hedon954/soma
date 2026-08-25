@testable import Soma
import XCTest

final class CoachMessageAgentEventTests: XCTestCase {
    func testCoachMessageKeepsLiveToolAndSkillEventsAfterCompletion() {
        let message = CoachMessage(
            isFromCoach: true,
            text: "",
            agentTraceID: UUID(),
            agentStatus: .running
        )
        let id = UUID()
        let startedAt = Date()
        message.applyAgentEvent(AgentTraceSpan(
            id: id,
            step: 1,
            kind: .skill,
            title: AgentSkill.gymAnalysis.title,
            status: .running,
            startedAt: startedAt,
            endedAt: startedAt
        ))
        message.applyAgentEvent(AgentTraceSpan(
            id: id,
            step: 1,
            kind: .skill,
            title: AgentSkill.gymAnalysis.title,
            status: .succeeded,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(0.1),
            output: "已加载"
        ))
        message.applyAgentEvent(AgentTraceSpan(
            step: 2,
            kind: .tool,
            title: AgentToolName.updateGym.displayTitle,
            status: .succeeded,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(0.2),
            output: AgentTraceText.json(AgentToolResult.success("已更新健身房。"))
        ))
        message.agentStatus = .succeeded

        XCTAssertEqual(message.agentEvents.count, 2)
        XCTAssertEqual(message.agentEvents.first?.status, .succeeded)
        XCTAssertEqual(message.agentEvents.last?.title, "更新健身房")
        XCTAssertEqual(message.agentStatus, .succeeded)
    }

    func testCoachMessagePreservesInterleavedAgentTurnItems() {
        let message = CoachMessage(
            isFromCoach: true,
            text: "",
            agentTraceID: UUID(),
            agentStatus: .running
        )
        let firstTextID = UUID()
        let toolID = UUID()
        let finalTextID = UUID()
        let startedAt = Date()

        message.applyAgentEvent(.assistantTextDelta(
            itemID: firstTextID,
            delta: "我先检查最近的训练。"
        ))
        message.applyAgentEvent(.assistantTextCompleted(
            itemID: firstTextID,
            at: startedAt
        ))
        message.applyAgentEvent(.span(AgentTraceSpan(
            id: toolID,
            step: 1,
            kind: .tool,
            title: AgentToolName.listWorkouts.displayTitle,
            status: .running,
            startedAt: startedAt,
            endedAt: startedAt
        )))
        message.applyAgentEvent(.span(AgentTraceSpan(
            id: toolID,
            step: 1,
            kind: .tool,
            title: AgentToolName.listWorkouts.displayTitle,
            status: .succeeded,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(0.1),
            output: AgentTraceText.json(AgentToolResult.success("最近训练 3 次。"))
        )))
        message.applyAgentEvent(.assistantTextDelta(
            itemID: finalTextID,
            delta: "本周已经训练 3 次，今天适合恢复。"
        ))
        message.applyAgentEvent(.assistantTextCompleted(
            itemID: finalTextID,
            at: startedAt.addingTimeInterval(0.2)
        ))
        message.applyAgentEvent(.completed(
            answer: "本周已经训练 3 次，今天适合恢复。",
            at: startedAt.addingTimeInterval(0.2)
        ))

        XCTAssertEqual(message.agentTurnItems.map(\.kind), [.text, .tool, .text])
        XCTAssertEqual(message.agentTurnItems.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(message.agentTurnItems[0].text, "我先检查最近的训练。")
        XCTAssertEqual(message.agentTurnItems[1].id, toolID)
        XCTAssertEqual(message.agentTurnItems[1].status, .succeeded)
        XCTAssertEqual(
            message.agentTurnItems[2].text,
            "本周已经训练 3 次，今天适合恢复。"
        )
    }

    func testCoachMessageCoalescesTextDeltasWithinOneTurnItem() {
        let message = CoachMessage(
            isFromCoach: true,
            text: "",
            agentTraceID: UUID(),
            agentStatus: .running
        )
        let textID = UUID()

        message.applyAgentEvent(.assistantTextDelta(itemID: textID, delta: "训练"))
        message.applyAgentEvent(.assistantTextDelta(itemID: textID, delta: "已记录"))

        XCTAssertEqual(message.agentTurnItems.count, 1)
        XCTAssertEqual(message.agentTurnItems.first?.kind, .text)
        XCTAssertEqual(message.agentTurnItems.first?.text, "训练已记录")
        XCTAssertEqual(message.agentTurnItems.first?.status, .running)
    }

    func testCoachMessageKeepsFailedOperationAndErrorAsSeparateCards() {
        let message = CoachMessage(
            isFromCoach: true,
            text: "",
            agentTraceID: UUID(),
            agentStatus: .running
        )
        let toolID = UUID()
        let startedAt = Date()

        message.applyAgentEvent(.span(AgentTraceSpan(
            id: toolID,
            kind: .tool,
            title: AgentToolName.createMeal.displayTitle,
            status: .running,
            startedAt: startedAt,
            endedAt: startedAt
        )))
        message.applyAgentEvent(.failed(
            message: "模型不支持图片分析",
            cancelled: false,
            at: startedAt.addingTimeInterval(0.1)
        ))

        XCTAssertEqual(message.agentTurnItems.map(\.kind), [.tool, .error])
        XCTAssertEqual(message.agentTurnItems.first?.status, .failed)
        XCTAssertEqual(message.agentTurnItems.last?.errorMessage, "模型不支持图片分析")
    }
}
