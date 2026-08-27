@testable import Soma
import SwiftData
import SwiftOpenAI
import XCTest

final class AgentReActLoopTests: XCTestCase {
    @MainActor
    func testInvalidToolArgumentsReturnRoleToolFeedbackAndModelCanRetry() async throws {
        let suiteName = "SomaTests.invalid-tool-arguments.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let transport = MockAgentStreamTransport(responses: [
            .toolCall(
                name: "update_meal",
                argumentsFragments: [#"{"record_id":"不是数字","protein":"1/3"}"#]
            ),
            .toolCall(
                name: "update_meal",
                argumentsFragments: [#"{"record_id":42,"protein":12.5}"#]
            ),
            .text(["已按修正后的参数更新。"])
        ])
        let service = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key",
            agentStreamLoader: transport.load
        )
        service.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1",
            model: "gpt-4.1-mini"
        )
        var executedCalls: [AgentToolCall] = []

        let outcome = try await service.runAgent(
            text: "把这份虚构餐食改成三分之一份",
            images: [],
            hasVideo: false,
            context: "测试上下文"
        ) { call in
            executedCalls.append(call)
            return .success("饮食记录已更新。")
        }

        XCTAssertEqual(executedCalls.count, 1)
        XCTAssertEqual(executedCalls.first?.arguments.recordID, 42)
        XCTAssertEqual(outcome.finalAnswer, "已按修正后的参数更新。")
        XCTAssertEqual(outcome.observations.count, 2)
        XCTAssertFalse(outcome.observations[0].result.ok)
        XCTAssertEqual(outcome.observations[0].result.code, "invalid_tool_arguments")
        XCTAssertEqual(outcome.observations[0].result.retryable, true)

        let secondData = try JSONEncoder().encode(transport.requests[1])
        let secondJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: secondData) as? [String: Any]
        )
        let messages = try XCTUnwrap(secondJSON["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.suffix(2).first?["role"] as? String, "assistant")
        XCTAssertEqual(messages.last?["role"] as? String, "tool")
        XCTAssertEqual(messages.last?["tool_call_id"] as? String, "call_1")
        let content = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(content.contains("invalid_tool_arguments"))
        XCTAssertTrue(content.contains("retryable"))
    }

    @MainActor
    func testAIServiceRunsMultipleRemoteReActTurns() async throws {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let transport = MockAgentStreamTransport(responses: [
            .toolCall(
                name: "list_workouts",
                argumentsFragments: [#"{"limit":3}"#]
            ),
            .text(["你最近完成了深蹲，", "今天建议轻量恢复。"])
        ])
        let service = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key",
            agentStreamLoader: transport.load
        )
        service.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1",
            model: "gpt-4.1-mini"
        )
        var toolExecutions = 0

        let outcome = try await service.runAgent(
            text: "我今天该怎么练？",
            images: [],
            hasVideo: false,
            context: "当前健身房：我的健身房"
        ) { call in
            toolExecutions += 1
            XCTAssertEqual(call.name, .listWorkouts)
            return .success("最近训练：昨天杠铃深蹲 4×8。")
        }

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(toolExecutions, 1)
        XCTAssertEqual(outcome.finalAnswer, "你最近完成了深蹲，今天建议轻量恢复。")
        let firstBody = try JSONEncoder().encode(XCTUnwrap(transport.requests.first))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        XCTAssertEqual(json["store"] as? Bool, false)
        XCTAssertNotNil(json["tools"] as? [[String: Any]])
        XCTAssertNil(json["response_format"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "system")

        let secondBody = try JSONEncoder().encode(XCTUnwrap(transport.requests.last))
        let secondJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        let secondMessages = try XCTUnwrap(secondJSON["messages"] as? [[String: Any]])
        XCTAssertEqual(secondMessages.suffix(2).first?["role"] as? String, "assistant")
        XCTAssertEqual(secondMessages.last?["role"] as? String, "tool")
        XCTAssertEqual(secondMessages.last?["tool_call_id"] as? String, "call_1")
    }

    @MainActor
    func testAgentRetryContinuesAtFailedToolWithoutRepeatingCompletedSteps() async throws {
        let suiteName = "SomaTests.checkpoint.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = MockAgentStreamTransport(responses: [
            .toolCalls([
                ("list_workouts", #"{"limit":1}"#),
                ("list_meals", #"{"limit":1}"#)
            ])
        ])
        let firstService = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key",
            agentStreamLoader: firstTransport.load
        )
        firstService.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1",
            model: "gpt-4.1-mini"
        )
        var checkpoint: AgentLoopCheckpoint?
        var firstAttemptNames: [AgentToolName] = []

        do {
            _ = try await firstService.runAgent(
                text: "总结最近记录",
                images: [],
                hasVideo: false,
                context: "测试上下文",
                onCheckpoint: { checkpoint = $0 }
            ) { call in
                firstAttemptNames.append(call.name)
                if call.name == .listMeals {
                    throw URLError(.networkConnectionLost)
                }
                return .success("训练查询成功")
            }
            XCTFail("第二个工具应中断第一次 Attempt")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }

        let saved = try XCTUnwrap(checkpoint)
        XCTAssertEqual(firstAttemptNames, [.listWorkouts, .listMeals])
        XCTAssertEqual(saved.lastCompletedStep, 2, "模型 invoke 与第一个工具各完成一步")
        XCTAssertEqual(saved.nextModelStep, 1)
        XCTAssertEqual(saved.toolBatches?.last?.completedResults.count, 1)

        let retryTransport = MockAgentStreamTransport(responses: [
            .text(["已根据两项查询完成总结。"])
        ])
        let retryService = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key",
            agentStreamLoader: retryTransport.load
        )
        retryService.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1",
            model: "gpt-4.1-mini"
        )
        var retryNames: [AgentToolName] = []
        let outcome = try await retryService.runAgent(
            text: "总结最近记录",
            images: [],
            hasVideo: false,
            context: "测试上下文",
            checkpoint: saved,
            firstStepDeadlineEnabled: false
        ) { call in
            retryNames.append(call.name)
            return .success("饮食查询成功")
        }

        XCTAssertEqual(retryNames, [.listMeals])
        XCTAssertEqual(outcome.observations.count, 2)
        XCTAssertEqual(outcome.finalAnswer, "已根据两项查询完成总结。")
        XCTAssertEqual(firstTransport.requests.count, 1)
        XCTAssertEqual(retryTransport.requests.count, 1)

        let firstData = try JSONEncoder().encode(XCTUnwrap(firstTransport.requests.first))
        let retryData = try JSONEncoder().encode(XCTUnwrap(retryTransport.requests.first))
        let firstJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: firstData) as? [String: Any]
        )
        let retryJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: retryData) as? [String: Any]
        )
        let firstMessages = try XCTUnwrap(firstJSON["messages"] as? [[String: Any]])
        let retryMessages = try XCTUnwrap(retryJSON["messages"] as? [[String: Any]])
        XCTAssertEqual(firstMessages[0]["content"] as? String, retryMessages[0]["content"] as? String)
        XCTAssertEqual(firstMessages[1]["content"] as? String, retryMessages[1]["content"] as? String)
        XCTAssertEqual(retryMessages.suffix(3).map { $0["role"] as? String }, [
            "assistant", "tool", "tool"
        ])
    }

    @MainActor
    func testAIServiceLoadsSkillWithoutCallingExternalDataToolAndTracesSkillSpan() async throws {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let customizedSkill = "自定义健身计划 Skill：先查训练和当前健身房，再输出两天训练安排。"
        AgentSkill.trainingPlan.save(customizedSkill, in: defaults)
        let transport = MockAgentStreamTransport(responses: [
            .toolCall(
                name: "load_skill",
                argumentsFragments: [#"{"skill_id":"training_plan"}"#]
            ),
            .text(["我会先核对你的目标", "和可训练时间。"])
        ])
        let service = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key",
            agentStreamLoader: transport.load
        )
        service.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1",
            model: "gpt-4.1-mini"
        )
        var externalToolExecutions = 0
        var events: [AgentTraceEvent] = []

        let outcome = try await service.runAgent(
            text: "帮我制定训练计划",
            images: [],
            hasVideo: false,
            context: "当前健身房：我的健身房",
            trace: { events.append($0) }
        ) { _ in
            externalToolExecutions += 1
            return .failure("不应调用外部数据工具")
        }

        let spans = events.compactMap { event -> AgentTraceSpan? in
            guard case let .span(span) = event else { return nil }
            return span
        }
        let skillSpan = try XCTUnwrap(
            spans.last(where: { $0.kind == .skill && $0.status == .succeeded })
        )

        XCTAssertEqual(outcome.finalAnswer, "我会先核对你的目标和可训练时间。")
        XCTAssertEqual(externalToolExecutions, 0)
        XCTAssertEqual(skillSpan.title, AgentSkill.trainingPlan.title)
        XCTAssertTrue(skillSpan.output?.contains(customizedSkill) == true)
        XCTAssertTrue(skillSpan.metadata?.contains(#""skill_id" : "training_plan""#) == true)
        XCTAssertEqual(transport.requests.count, 2)
        let textEvents = events.compactMap { event -> (UUID, String)? in
            guard case let .assistantTextDelta(itemID, delta) = event else { return nil }
            return (itemID, delta)
        }
        XCTAssertEqual(Set(textEvents.map(\.0)).count, 1)
        XCTAssertEqual(textEvents.map(\.1).joined(), outcome.finalAnswer)
        let skillFinishedIndex = try XCTUnwrap(events.lastIndex(where: { event in
            guard case let .span(span) = event else { return false }
            return span.kind == .skill && span.status == .succeeded
        }))
        let firstTextIndex = try XCTUnwrap(events.firstIndex(where: { event in
            if case .assistantTextDelta = event {
                return true
            }
            return false
        }))
        XCTAssertLessThan(skillFinishedIndex, firstTextIndex)

        let firstBody = try JSONEncoder().encode(XCTUnwrap(transport.requests.first))
        let firstJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        let firstMessages = try XCTUnwrap(firstJSON["messages"] as? [[String: Any]])
        let firstSystem = try XCTUnwrap(firstMessages.first?["content"] as? String)
        XCTAssertFalse(firstSystem.contains(customizedSkill))
        XCTAssertFalse(firstSystem.contains("决策 JSON"))

        let secondBody = try JSONEncoder().encode(XCTUnwrap(transport.requests.last))
        let secondJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        let secondMessages = try XCTUnwrap(secondJSON["messages"] as? [[String: Any]])
        let secondTool = try XCTUnwrap(secondMessages.last)
        XCTAssertEqual(secondTool["role"] as? String, "tool")
        XCTAssertTrue((secondTool["content"] as? String)?.contains(customizedSkill) == true)
    }

    @MainActor
    func testAgentTracePersistsSuccessAndFailureSpanState() {
        let startedAt = Date()
        let trace = AgentTrace(
            startedAt: startedAt,
            provider: "OpenAI",
            model: "test-model",
            endpoint: "https://example.com/v1/chat/completions",
            dataSpaceRaw: DataSpace.personal.rawValue,
            userInput: "帮我分析动作",
            contextSnapshot: "",
            mediaKind: .video,
            imageCount: 4
        )
        trace.apply(.span(AgentTraceSpan(
            step: 1,
            kind: .skill,
            title: AgentSkill.movementAnalysis.title,
            status: .succeeded,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(0.01),
            input: #"{"skill_id":"movement_analysis"}"#,
            output: AgentSkill.movementAnalysis.defaultText
        )))
        trace.apply(.span(AgentTraceSpan(
            step: 2,
            kind: .model,
            title: "LLM 决策",
            status: .failed,
            startedAt: startedAt.addingTimeInterval(0.02),
            endedAt: startedAt.addingTimeInterval(0.03),
            errorMessage: "模型不支持视频关键帧"
        )))
        trace.apply(.failed(
            message: "模型不支持视频关键帧",
            cancelled: false,
            at: startedAt.addingTimeInterval(0.03)
        ))

        XCTAssertEqual(trace.status, .failed)
        XCTAssertEqual(trace.spans.map(\.sequence), [1, 2])
        XCTAssertEqual(trace.spans.first?.kind, .skill)
        XCTAssertEqual(trace.spans.last?.status, .failed)
        XCTAssertEqual(trace.errorMessage, "模型不支持视频关键帧")
    }
}
