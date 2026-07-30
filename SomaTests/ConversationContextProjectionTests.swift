@testable import Soma
import SwiftData
import SwiftOpenAI
import UIKit
import XCTest

final class ConversationContextProjectionTests: XCTestCase {
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
        defaults.set(true, forKey: "ai.remoteEnabled")

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
            text: "那我的膝盖轨迹怎么样？",
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
