@testable import Soma
import SwiftData
import SwiftOpenAI
import XCTest

final class AgentV2Tests: XCTestCase {
    func testTypedDomainContractExposesTwentySevenVersionedTools() {
        let tools = AgentToolExposurePolicy.tools(
            names: AgentToolExposurePolicy.toolNames(
                for: [.exercises, .workouts, .meals, .body, .plans]
            )
        )

        XCTAssertEqual(tools.count, 27)
        XCTAssertEqual(
            Set(tools.filter { $0.schemaVersion == 4 }),
            [.searchExercises, .createExercise, .updateExercise, .createWorkout, .updateWorkout]
        )
        XCTAssertEqual(
            Set(tools.filter { $0.schemaVersion == 3 }),
            [.getProgram, .createProgram, .updateProgram]
        )
        XCTAssertTrue(tools.allSatisfy { (2 ... 4).contains($0.schemaVersion) })
        XCTAssertTrue(tools.contains(.updateMeal))
    }

    @MainActor
    func testCreateMealPersistsReviewableQualitativeGlycemicEstimate() throws {
        let context = try makeContext()
        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createMeal,
                arguments: AgentToolArguments(
                    mealType: MealType.snack.rawValue,
                    title: "虚构加餐",
                    glycemicSpeed: MealGlycemicSpeed.fast.rawValue,
                    glycemicAssessment: "精制碳水占比较高；实际反应因人而异。",
                    recommendedEatingOrder: "虚构莓果 → 虚构酸奶",
                    items: [
                        AgentMealItemInput(
                            name: "虚构酸奶",
                            portionDescription: "一杯",
                            calories: 120,
                            protein: 6,
                            carbs: 18,
                            fat: 3
                        ),
                        AgentMealItemInput(
                            name: "虚构莓果",
                            portionDescription: "一小份",
                            calories: 45,
                            protein: 1,
                            carbs: 10,
                            fat: 0.5
                        )
                    ]
                )
            ),
            sourceText: "记录这份虚构加餐",
            sourceDate: Date(timeIntervalSince1970: 1_787_200_000),
            sourceSessionID: UUID(),
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        let meal = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MealEntry>()).first
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(meal.glycemicSpeed, .fast)
        XCTAssertEqual(
            meal.glycemicAssessment,
            "精制碳水占比较高；实际反应因人而异。"
        )
        XCTAssertEqual(meal.recommendedEatingOrder, "虚构莓果 → 虚构酸奶")
        guard case let .object(payload)? = result.data else {
            return XCTFail("饮食 Tool 应返回结构化记录")
        }
        XCTAssertEqual(payload["glycemic_speed"], .string("fast"))
        XCTAssertEqual(
            payload["recommended_eating_order"],
            .string("虚构莓果 → 虚构酸奶")
        )
    }

    @MainActor
    func testUpdateMealKeepsItemsAsNutritionSourceAndRefreshesAssessment() throws {
        let context = try makeContext()
        let meal = MealEntry(
            mealType: .snack,
            title: "旧虚构加餐",
            glycemicSpeed: .slow,
            glycemicAssessment: "旧判断",
            recommendedEatingOrder: "旧顺序"
        )
        context.insert(meal)
        try BusinessIDAllocator.assignMissingIDs(in: context)
        let recordID = try XCTUnwrap(meal.businessID)

        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .updateMeal,
                arguments: AgentToolArguments(
                    title: "新虚构加餐",
                    glycemicSpeed: MealGlycemicSpeed.moderate.rawValue,
                    glycemicAssessment: "混合餐，仅作定性估算。",
                    recommendedEatingOrder: "虚构食物乙 → 虚构食物甲",
                    items: [
                        AgentMealItemInput(name: "虚构食物甲", protein: 2),
                        AgentMealItemInput(name: "虚构食物乙", protein: 3)
                    ],
                    recordID: recordID
                )
            ),
            sourceText: "修正这份虚构加餐",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(meal.nutritionSource, .derivedFromItems)
        XCTAssertEqual(meal.glycemicSpeed, .moderate)
        XCTAssertEqual(meal.glycemicAssessment, "混合餐，仅作定性估算。")
        XCTAssertEqual(meal.recommendedEatingOrder, "虚构食物乙 → 虚构食物甲")
    }

    @MainActor
    func testMutateMealKeepsUnknownNutritionNilAndDerivesCompleteFields() throws {
        let context = try makeContext()
        let result = ConversationRecorder.mutateUserData(
            AgentToolArguments(
                operation: "create",
                payload: AgentMutationPayload(
                    mealType: MealType.lunch.rawValue,
                    title: "鸡肉荞麦面",
                    items: [
                        AgentMealItemInput(
                            name: "鸡肉",
                            portionDescription: "一份",
                            calories: 220,
                            protein: 30,
                            carbs: 2,
                            fat: 9
                        ),
                        AgentMealItemInput(
                            name: "荞麦面",
                            portionDescription: "一碗",
                            protein: 8,
                            carbs: 52,
                            fat: 2
                        )
                    ]
                ),
                recordType: "meal"
            ),
            sourceText: "记录这份午餐",
            sourceDate: Date(timeIntervalSince1970: 1_786_000_000),
            sourceSessionID: UUID(),
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        let meal = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MealEntry>()).first
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.code, "ok")
        XCTAssertEqual(result.recordRefs?.first?.recordID, meal.businessID)
        XCTAssertNil(meal.calories)
        XCTAssertEqual(meal.protein, 38)
        XCTAssertEqual(meal.carbs, 54)
        XCTAssertEqual(meal.fat, 11)
        XCTAssertEqual(meal.nutritionSource, .derivedFromItems)
        XCTAssertEqual(meal.items.count, 2)

        let mismatched = ConversationRecorder.mutateUserData(
            AgentToolArguments(
                operation: "create",
                payload: AgentMutationPayload(title: "错误字段", weight: 70),
                recordType: "meal"
            ),
            sourceText: "",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        XCTAssertFalse(mismatched.ok)
        XCTAssertTrue(mismatched.message.contains("weight"))
    }

    @MainActor
    func testQueryV2AppliesDateFieldsPaginationAndExerciseSearch() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let base = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))
        )
        for day in 0 ..< 4 {
            try context.insert(MealEntry(
                date: XCTUnwrap(calendar.date(byAdding: .day, value: day, to: base)),
                mealType: .lunch,
                title: "虚构午餐 \(day)",
                calories: 400 + day
            ))
        }
        let exercise = ExerciseDefinition(canonicalName: "杠铃深蹲")
        context.insert(exercise)
        try context.save()

        let first = ConversationRecorder.queryUserData(
            AgentToolArguments(
                scope: "meals",
                limit: 1,
                fields: ["title"],
                dateFrom: "2026-08-02",
                dateTo: "2026-08-03"
            ),
            preferredGymID: nil,
            in: context
        )
        let firstJSON = try json(first.data)
        XCTAssertTrue(first.ok)
        XCTAssertTrue(firstJSON.contains("虚构午餐 2"))
        XCTAssertTrue(firstJSON.contains("record_id"))
        XCTAssertFalse(firstJSON.contains("calories"))
        XCTAssertNotNil(first.page?.nextCursor)

        let second = ConversationRecorder.queryUserData(
            AgentToolArguments(
                scope: "meals",
                limit: 1,
                cursor: first.page?.nextCursor,
                fields: ["title"],
                dateFrom: "2026-08-02",
                dateTo: "2026-08-03"
            ),
            preferredGymID: nil,
            in: context
        )
        XCTAssertTrue(try json(second.data).contains("虚构午餐 1"))
        XCTAssertNil(second.page?.nextCursor)

        let allExercises = query(
            AgentToolArguments(scope: "exercises"),
            in: context
        )
        XCTAssertFalse(allExercises.ok)
        let searchedExercises = query(
            AgentToolArguments(scope: "exercises", query: "深蹲"),
            in: context
        )
        XCTAssertTrue(searchedExercises.ok)
        XCTAssertTrue(
            try json(searchedExercises.data).contains(
                String(XCTUnwrap(exercise.businessID))
            )
        )
    }

    func testTrustedTimeFreezesLoopStartAndFormatsAtPromptTime() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let sent = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-09-01T22:12:00+08:00")
        )
        let attempt = sent.addingTimeInterval(90)
        let trusted = TrustedTurnContext.make(
            turnSentAt: sent,
            attemptStartedAt: sent,
            timeZone: zone,
            calendar: Calendar(identifier: .gregorian)
        )
        let frozen = trusted.freezingLoopStart(at: attempt)

        XCTAssertEqual(frozen.turnSentAt, sent)
        XCTAssertEqual(frozen.loopStartedAt, attempt)
        XCTAssertEqual(frozen.timeZoneIdentifier, "Asia/Shanghai")
        XCTAssertTrue(frozen.promptText.contains(
            "用户本次发送时间（权威本地时间）：2026-09-01 22:12:00 +08:00（Asia/Shanghai，晚上10点12分）"
        ))
        XCTAssertTrue(frozen.promptText.contains(
            "当前执行时间（仅用于处理延迟）：2026-09-01 22:13:30 +08:00"
        ))
        XCTAssertTrue(frozen.promptText.contains("省略 occurred_at 时的稳定记录时间"))
        XCTAssertFalse(frozen.promptText.contains("14:12:00Z"))
        let encoded = try JSONEncoder().encode(frozen)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(json.contains("localDate"))
        XCTAssertFalse(json.contains("weekday"))
    }

    func testTrustedTimeKeepsNonWholeHourOffsetAndDaylightSaving() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/St_Johns"))
        let sent = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-01T22:12:00-02:30")
        )
        let trusted = TrustedTurnContext.make(
            turnSentAt: sent,
            attemptStartedAt: sent,
            timeZone: zone
        )

        XCTAssertTrue(trusted.promptText.contains("2026-07-01 22:12:00 -02:30"))
        XCTAssertTrue(trusted.promptText.contains("America/St_Johns，晚上10点12分"))
    }

    func testDirectVideoRequiresExplicitCatalogVideoModality() {
        let explicitVideo = ModelCapability.assessment(
            inputModalities: ["text", "image", "video"],
            source: "input_modalities"
        )
        let imageOnly = ModelCapability.assessment(
            inputModalities: ["text", "image"],
            source: "input_modalities"
        )

        XCTAssertNotNil(ModelCapability.directVideoCapability(assessment: explicitVideo))
        XCTAssertNil(ModelCapability.directVideoCapability(assessment: imageOnly))
        XCTAssertNil(ModelCapability.directVideoCapability(assessment: .unknown))
    }

    @MainActor
    func testDirectVideoTTFTRetriesOnceWithKeyframes() async throws {
        let transport = RetryStreamTransport()
        let suiteName = "AgentV2Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key",
            agentStreamLoader: transport.load,
            streamDeadlinePolicy: AgentStreamDeadlinePolicy(
                textTTFT: 0.03,
                imageTTFT: 0.03,
                directVideoTTFT: 0.03,
                textLoopTotal: 1,
                imageLoopTotal: 1,
                videoLoopTotal: 1
            ),
            agentRetrySleeper: { _ in }
        )
        var messages = [
            ChatCompletionParameters.Message(
                role: .user,
                content: .text("分析视频")
            )
        ]
        let outcome = try await service.consumeAgentStepWithRetry(
            messages: &messages,
            request: AgentStreamStepRequest(
                tools: [],
                model: "qwen3-vl-plus",
                provider: .bailian,
                images: [],
                videos: [AgentVideoInput(data: Data([1]), mimeType: "video/mp4")],
                hasVideo: true,
                step: 1,
                route: AIModelRoute(
                    tier: .standard,
                    provider: .bailian,
                    baseURL: AIProvider.bailian.defaultBaseURL,
                    model: "qwen3-vl-plus",
                    reason: "test"
                ),
                apiKey: "test-key",
                userPrompt: "分析视频",
                textItemID: UUID(),
                enforceFirstStepDeadline: true
            ),
            maximumRetryCount: AgentStepRetryPolicy.maximumRetryCount,
            videoFrameFallback: { [Data([2, 3])] },
            trace: nil
        )

        XCTAssertEqual(transport.requestCount, 2)
        XCTAssertEqual(outcome.requestAttempt, 2)
        XCTAssertEqual(outcome.mediaMode, .keyframes)
        XCTAssertEqual(outcome.passage, "关键帧结果")
        XCTAssertNotNil(outcome.fallbackReason)
    }

    @MainActor
    func testTransientModelStepUsesExactlyThreeExponentialRetries() async throws {
        let transport = ThreeFailureStreamTransport()
        let delays = RetryDelayRecorder()
        let suiteName = "AgentV2Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key",
            agentStreamLoader: transport.load,
            agentRetrySleeper: { seconds in
                await delays.record(seconds)
            }
        )
        var messages = [
            ChatCompletionParameters.Message(role: .user, content: .text("测试重试"))
        ]

        let outcome = try await service.consumeAgentStepWithRetry(
            messages: &messages,
            request: AgentStreamStepRequest(
                tools: [],
                model: "gpt-test",
                provider: .openAI,
                images: [],
                videos: [],
                hasVideo: false,
                step: 2,
                route: AIModelRoute(
                    tier: .standard,
                    provider: .openAI,
                    baseURL: AIProvider.openAI.defaultBaseURL,
                    model: "gpt-test",
                    reason: "test"
                ),
                apiKey: "test-key",
                userPrompt: "测试重试",
                textItemID: UUID()
            ),
            maximumRetryCount: AgentStepRetryPolicy.maximumRetryCount,
            videoFrameFallback: nil,
            trace: nil
        )

        XCTAssertEqual(transport.requestCount, 4)
        XCTAssertEqual(outcome.requestAttempt, 4)
        XCTAssertEqual(outcome.passage, "第 4 次成功")
        let recordedDelays = await delays.values
        XCTAssertEqual(recordedDelays, [1, 2, 4])
    }

    func testLaterModelStepHasNoStandaloneFirstDeltaDeadline() async throws {
        let chunk = try streamChunk(content: "较晚返回")
        let stream = AsyncThrowingStream<ChatCompletionChunkObject, Error> { continuation in
            Task {
                try await Task.sleep(for: .milliseconds(40))
                continuation.yield(chunk)
                continuation.finish()
            }
        }
        var output = ""

        try await AgentStreamDeadline.consume(
            stream: stream,
            mode: .text,
            policy: AgentStreamDeadlinePolicy(textTTFT: 0.01),
            enforceFirstDelta: false
        ) { value in
            output += value.choices?.first?.delta?.content ?? ""
            return !output.isEmpty
        }

        XCTAssertEqual(output, "较晚返回")
    }

    func testOpenAICompatibleStreamNormalizesReasoningAliases() throws {
        for alias in ["reasoning", "analysis"] {
            let raw = try JSONSerialization.data(withJSONObject: [
                "id": "chatcmpl_reasoning_alias",
                "object": "chat.completion.chunk",
                "choices": [[
                    "index": 0,
                    "delta": [alias: "先核对事实。", "content": "再给结论。"],
                    "finish_reason": "stop"
                ]]
            ])

            let normalized = try OpenAICompatibleStreamPayload.normalize(raw)
            let chunk = try JSONDecoder().decode(
                ChatCompletionChunkObject.self,
                from: normalized
            )

            XCTAssertEqual(chunk.choices?.first?.delta?.reasoningContent, "先核对事实。")
            XCTAssertEqual(chunk.choices?.first?.delta?.content, "再给结论。")
        }
    }

    @MainActor
    func testAgentStreamWorkerProjectsReasoningSeparatelyFromAssistantText() async throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "chatcmpl_reasoning",
            "object": "chat.completion.chunk",
            "choices": [[
                "index": 0,
                "delta": [
                    "reasoning_content": "先分析事实。",
                    "content": "再给结论。"
                ],
                "finish_reason": "stop"
            ]]
        ])
        let chunk = try JSONDecoder().decode(ChatCompletionChunkObject.self, from: data)
        let stream = AsyncThrowingStream<ChatCompletionChunkObject, Error> { continuation in
            continuation.yield(chunk)
            continuation.finish()
        }
        let textItemID = UUID()
        let reasoningItemID = UUID()
        var events: [AgentTraceEvent] = []

        let outcome = try await AgentStreamWorker.consume(
            stream: stream,
            mediaMode: .text,
            policy: AgentStreamDeadlinePolicy(),
            enforceFirstDelta: false,
            textItemID: textItemID,
            reasoningItemID: reasoningItemID
        ) { event in
            events.append(event)
        }

        XCTAssertEqual(outcome.reasoning, "先分析事实。")
        XCTAssertEqual(outcome.passage, "再给结论。")
        XCTAssertTrue(events.contains(.reasoningDelta(
            itemID: reasoningItemID,
            delta: "先分析事实。"
        )))
        XCTAssertTrue(events.contains(.assistantTextDelta(
            itemID: textItemID,
            delta: "再给结论。"
        )))
    }

    @MainActor
    func testWholeLoopDeadlineStillAppliesAcrossLaterSteps() async {
        do {
            _ = try await AgentLoopDeadline.run(seconds: 0.01) {
                try await Task.sleep(for: .milliseconds(50))
                return "不应完成"
            }
            XCTFail("整个 ReAct Loop 必须受总时限控制")
        } catch let timeout as AgentStreamTimeoutError {
            XCTAssertEqual(timeout.phase, .loopTotal)
        } catch {
            XCTFail("应返回 loop_total 超时：\(error)")
        }
    }

    func testChatRecordReferencesAreStableAndDeduplicated() {
        let id: Int64 = 37
        let output = AgentTraceText.json(AgentToolResult.success(
            "已记录",
            recordRefs: [
                AgentRecordReference(
                    recordType: ConversationIntent.workout.rawValue,
                    recordID: id,
                    title: "深蹲"
                )
            ],
            recordType: .workout
        ))
        let items = (0 ..< 2).map { _ in
            AgentTurnItem(
                kind: .tool,
                status: .succeeded,
                title: "保存训练",
                output: output
            )
        }

        XCTAssertEqual(
            AgentTurnRecordReferences.make(from: items),
            [AgentRecordReference(
                recordType: ConversationIntent.workout.rawValue,
                recordID: id,
                title: "深蹲"
            )]
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
            CoachMessage.self,
            AgentMutationReceipt.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @MainActor
    private func query(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        ConversationRecorder.queryUserData(
            arguments,
            preferredGymID: nil,
            in: context
        )
    }

    private func json(_ value: AgentJSONValue?) throws -> String {
        let value = try XCTUnwrap(value)
        return try XCTUnwrap(
            String(data: JSONEncoder().encode(value), encoding: .utf8)
        )
    }

    private func streamChunk(content: String) throws -> ChatCompletionChunkObject {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "chatcmpl_delayed",
            "object": "chat.completion.chunk",
            "choices": [[
                "index": 0,
                "delta": ["content": content],
                "finish_reason": "stop"
            ]]
        ])
        return try JSONDecoder().decode(ChatCompletionChunkObject.self, from: data)
    }
}

private final class RetryStreamTransport: @unchecked Sendable {
    private var firstContinuation:
        AsyncThrowingStream<ChatCompletionChunkObject, Error>.Continuation?
    private(set) var requestCount = 0

    func load(
        _: ChatCompletionParameters,
        _: AIProvider,
        _: String,
        _: String
    ) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error> {
        requestCount += 1
        if requestCount == 1 {
            return AsyncThrowingStream { continuation in
                firstContinuation = continuation
            }
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "chatcmpl_retry",
            "object": "chat.completion.chunk",
            "choices": [[
                "index": 0,
                "delta": ["content": "关键帧结果"],
                "finish_reason": "stop"
            ]]
        ])
        let chunk = try JSONDecoder().decode(
            ChatCompletionChunkObject.self,
            from: data
        )
        return AsyncThrowingStream { continuation in
            continuation.yield(chunk)
            continuation.finish()
        }
    }
}

private actor RetryDelayRecorder {
    private(set) var values: [TimeInterval] = []

    func record(_ value: TimeInterval) {
        values.append(value)
    }
}

private final class ThreeFailureStreamTransport: @unchecked Sendable {
    private(set) var requestCount = 0

    func load(
        _: ChatCompletionParameters,
        _: AIProvider,
        _: String,
        _: String
    ) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error> {
        requestCount += 1
        guard requestCount > AgentStepRetryPolicy.maximumRetryCount else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: URLError(.networkConnectionLost))
            }
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "chatcmpl_retry_success",
            "object": "chat.completion.chunk",
            "choices": [[
                "index": 0,
                "delta": ["content": "第 4 次成功"],
                "finish_reason": "stop"
            ]]
        ])
        let chunk = try JSONDecoder().decode(ChatCompletionChunkObject.self, from: data)
        return AsyncThrowingStream { continuation in
            continuation.yield(chunk)
            continuation.finish()
        }
    }
}
