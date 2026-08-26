@testable import Soma
import SwiftData
import SwiftOpenAI
import UIKit
import XCTest

final class ConversationContextProjectionTests: XCTestCase {
    @MainActor
    func testAgentContextIncludesProfileAndLatestRecordedWeight() throws {
        let suiteName = "ConversationContextProjectionTests.profile.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        let context = spaces.personalContainer.mainContext
        context.insert(UserProfile(
            displayName: "虚构用户",
            biologicalSex: .female,
            birthDate: Calendar.current.date(byAdding: .year, value: -30, to: .now),
            height: 168,
            fitnessGoal: FitnessGoal.muscleGain.rawValue,
            healthNotes: "虚构限制：避免跳跃"
        ))
        context.insert(BodyEntry(
            date: Date(timeIntervalSince1970: 1_787_200_000),
            weight: 62.4
        ))

        let contextText = AgentContextPackBuilder.build(
            gyms: [],
            equipment: [],
            in: context,
            businessDate: Date(timeIntervalSince1970: 1_787_200_000)
        )

        XCTAssertTrue(contextText.contains("虚构用户"))
        XCTAssertTrue(contextText.contains("生理性别 女性"))
        XCTAssertTrue(contextText.contains("身高 168cm"))
        XCTAssertTrue(contextText.contains("最新体重 62.4kg"))
        XCTAssertTrue(contextText.contains("目标 增肌"))
        XCTAssertTrue(contextText.contains("限制 虚构限制：避免跳跃"))
    }

    func testHistoricalMediaRequiresExplicitReferenceAndCapsComparisonAtTwo() {
        let exchanges = (0 ..< 3).map { index in
            ConversationContextProjection.Exchange(
                turnID: UUID(),
                date: Date(timeIntervalSince1970: Double(index)),
                userText: "媒体 \(index)",
                mediaAttachments: [
                    .init(kind: .image, path: "image-\(index).jpg")
                ]
            )
        }

        XCTAssertTrue(HistoricalMediaSelectionPolicy.selectedTurnIDs(
            currentText: "继续聊饮食",
            hasCurrentMedia: false,
            exchanges: exchanges
        ).isEmpty)
        XCTAssertEqual(HistoricalMediaSelectionPolicy.selectedTurnIDs(
            currentText: "看看上一张",
            hasCurrentMedia: false,
            exchanges: exchanges
        ), [exchanges[2].turnID])
        XCTAssertEqual(HistoricalMediaSelectionPolicy.selectedTurnIDs(
            currentText: "比较这几张",
            hasCurrentMedia: false,
            exchanges: exchanges
        ), [exchanges[1].turnID, exchanges[2].turnID])
        XCTAssertTrue(HistoricalMediaSelectionPolicy.selectedTurnIDs(
            currentText: "比较上一张",
            hasCurrentMedia: true,
            exchanges: exchanges
        ).isEmpty)
    }

    @MainActor
    func testHistoryBudgetKeepsNewestCompleteExchangeWithoutHalfTurn() {
        let sessionID = UUID()
        let olderTurn = UUID()
        let newestTurn = UUID()
        let messages = [
            CoachMessage(
                date: Date(timeIntervalSince1970: 1),
                sessionID: sessionID,
                isFromCoach: false,
                text: String(repeating: "older ", count: 80),
                turnID: olderTurn
            ),
            CoachMessage(
                date: Date(timeIntervalSince1970: 2),
                sessionID: sessionID,
                isFromCoach: true,
                text: String(repeating: "reply ", count: 80),
                turnID: olderTurn
            ),
            CoachMessage(
                date: Date(timeIntervalSince1970: 3),
                sessionID: sessionID,
                isFromCoach: false,
                text: String(repeating: "newest ", count: 80),
                turnID: newestTurn
            ),
            CoachMessage(
                date: Date(timeIntervalSince1970: 4),
                sessionID: sessionID,
                isFromCoach: true,
                text: String(repeating: "answer ", count: 80),
                turnID: newestTurn
            )
        ]

        let projection = ConversationContextProjection.make(
            messages: messages,
            sessionID: sessionID,
            excludingTurnID: nil,
            maximumEstimatedTokens: 20
        )

        XCTAssertEqual(projection.exchanges.map(\.turnID), [newestTurn])
        XCTAssertNotNil(projection.exchanges.first?.assistantText)
    }

    @MainActor
    func testProjectionKeepsTenLatestExchangesAndLatestAssistantAttempt() {
        let sessionID = UUID()
        let otherSessionID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        var messages: [CoachMessage] = []

        for index in 1 ... 12 {
            let turnID = UUID()
            let attachments: [MediaAttachmentReference] = switch index {
            case 2:
                [.init(kind: .image, path: "outside-window.jpg")]
            case 11:
                [.init(kind: .image, path: "recent.jpg")]
            case 12:
                [.init(kind: .video, path: "recent.mov")]
            default:
                []
            }
            messages.append(CoachMessage(
                date: baseDate.addingTimeInterval(Double(index * 10)),
                sessionID: sessionID,
                isFromCoach: false,
                text: "用户 \(index)",
                mediaAttachments: attachments,
                turnID: turnID
            ))
            messages.append(CoachMessage(
                date: baseDate.addingTimeInterval(Double(index * 10 + 1)),
                sessionID: sessionID,
                isFromCoach: true,
                text: "回复 \(index)",
                agentStatus: .succeeded,
                turnID: turnID,
                attemptNumber: 1
            ))
            if index == 12 {
                messages.append(CoachMessage(
                    date: baseDate.addingTimeInterval(Double(index * 10 + 2)),
                    sessionID: sessionID,
                    isFromCoach: true,
                    text: "最终回复 12",
                    agentStatus: .succeeded,
                    turnID: turnID,
                    attemptNumber: 2
                ))
            }
        }
        messages.append(CoachMessage(
            date: baseDate.addingTimeInterval(1000),
            sessionID: otherSessionID,
            isFromCoach: false,
            text: "其他 Session",
            mediaAttachments: [.init(kind: .image, path: "other.jpg")],
            turnID: UUID()
        ))

        let projection = ConversationContextProjection.make(
            messages: messages,
            sessionID: sessionID,
            excludingTurnID: nil
        )

        XCTAssertEqual(projection.exchanges.count, 10)
        XCTAssertEqual(projection.exchanges.first?.userText, "用户 3")
        XCTAssertEqual(projection.exchanges.last?.userText, "用户 12")
        XCTAssertEqual(projection.exchanges.last?.assistantText, "最终回复 12")
        XCTAssertEqual(
            projection.exchanges.flatMap(\.mediaAttachments).map(\.path),
            ["recent.jpg", "recent.mov"]
        )
    }

    @MainActor
    func testRemoteTurnRehydratesHistoricalImageInsideSameSession() async throws {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(spaces.personalContainer)
        let transport = ContextProjectionMockTransport()
        let ai = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key",
            agentStreamLoader: transport.load
        )
        ai.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1",
            model: "gpt-4.1-mini"
        )
        let imageData = UIGraphicsImageRenderer(
            size: CGSize(width: 8, height: 8)
        ).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let mediaPath = try MediaStore.saveImage(imageData)
        defer { MediaStore.removeStoredFile(at: mediaPath) }

        let session = ConversationSession()
        let previousTurnID = UUID()
        context.insert(session)
        context.insert(CoachMessage(
            date: .now.addingTimeInterval(-2),
            sessionID: session.id,
            isFromCoach: false,
            text: "看看这张深蹲照片",
            mediaKind: .image,
            mediaPath: mediaPath,
            mediaAttachments: [.init(kind: .image, path: mediaPath)],
            turnID: previousTurnID
        ))
        context.insert(CoachMessage(
            date: .now.addingTimeInterval(-1),
            sessionID: session.id,
            isFromCoach: true,
            text: "我看到了你的深蹲姿势。",
            agentStatus: .succeeded,
            turnID: previousTurnID,
            attemptNumber: 1
        ))
        try context.save()

        let service = ConversationProcessingService()
        XCTAssertTrue(service.submit(
            text: "刚才那张照片里，我的膝盖轨迹怎么样？",
            attachments: [],
            context: ConversationProcessingContext(
                structuredContext: "测试上下文",
                session: session,
                dataSpace: .personal,
                gyms: [],
                equipment: [],
                ai: ai,
                modelContext: context
            ),
            includeLocation: false,
            locationService: LocationContextService()
        ))

        for _ in 0 ..< 100 where service.isProcessing {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertFalse(service.isProcessing)
        let request = try XCTUnwrap(transport.requests.first)
        let encoded = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let requestMessages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(
            requestMessages.compactMap { $0["role"] as? String },
            ["system", "user", "assistant", "user"]
        )
        let historicalContent = try XCTUnwrap(
            requestMessages[1]["content"] as? [[String: Any]]
        )
        XCTAssertTrue(historicalContent.contains {
            $0["type"] as? String == "image_url"
        })
        XCTAssertTrue(
            (historicalContent.first?["text"] as? String)?
                .contains("看看这张深蹲照片") == true
        )
        XCTAssertTrue(
            (historicalContent.first?["text"] as? String)?
                .contains("media_source=recent_gym_turn") == true
        )

        let trace = try XCTUnwrap(
            try context.fetch(FetchDescriptor<AgentTrace>()).first
        )
        XCTAssertEqual(trace.imageCount, 1)
        XCTAssertTrue(trace.contextSnapshot.contains("最近 1 个来回"))
        XCTAssertTrue(trace.contextSnapshot.contains("历史视觉帧 1 张"))
    }

    func testLatestInlineCorrectionIsProjectedIntoNextTurnHistory() {
        let sessionID = UUID()
        let turnID = UUID()
        let user = CoachMessage(
            sessionID: sessionID,
            isFromCoach: false,
            text: "记录深蹲",
            turnID: turnID
        )
        let assistant = CoachMessage(
            sessionID: sessionID,
            isFromCoach: true,
            text: "已记录深蹲。",
            agentStatus: .succeeded,
            turnID: turnID,
            attemptNumber: 1
        )
        assistant.recordManualCorrection("训练记录已改为 4组8次60kg")

        let projection = ConversationContextProjection.make(
            messages: [user, assistant],
            sessionID: sessionID,
            excludingTurnID: UUID()
        )

        XCTAssertTrue(
            projection.exchanges.first?.assistantText?
                .contains("用户在回复卡片中的最新修订") == true
        )
        XCTAssertTrue(
            projection.exchanges.first?.assistantText?
                .contains("4组8次60kg") == true
        )
    }
}

private final class ContextProjectionMockTransport {
    private(set) var requests: [ChatCompletionParameters] = []

    func load(
        _ parameters: ChatCompletionParameters,
        _: AIProvider,
        _: String,
        _: String
    ) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error> {
        requests.append(parameters)
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "chatcmpl_context",
            "object": "chat.completion.chunk",
            "choices": [[
                "index": 0,
                "delta": ["content": "膝盖轨迹需要结合刚才的画面继续判断。"],
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
