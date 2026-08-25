import AppIntents
import Observation
import OSLog

let somaCaptureLogger = Logger(
    subsystem: "top.hedon.soma",
    category: "CaptureRouting"
)

enum CaptureEntryMode: String, AppEnum, Sendable {
    case text
    case camera
    case media

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "记录方式"

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .text: "文字",
        .camera: "拍照或录像",
        .media: "照片与视频"
    ]

    var routeURL: URL {
        URL(string: "soma://capture/\(rawValue)")!
    }
}

struct CaptureEntryRequest: Equatable, Identifiable, Sendable {
    let id = UUID()
    let mode: CaptureEntryMode
}

struct CaptureMediaDelivery {
    let id = UUID()
    let media: [PickedMedia]
}

struct AgentTurnRoute: Equatable, Identifiable, Sendable {
    var id: UUID
    var turnID: UUID

    init(turnID: UUID) {
        id = UUID()
        self.turnID = turnID
    }
}

struct WorkoutSessionRoute: Equatable, Identifiable, Sendable {
    var id = UUID()
    var sessionID: UUID
}

@MainActor
@Observable
final class SomaCaptureRouter {
    static let shared = SomaCaptureRouter()

    private(set) var pendingRequest: CaptureEntryRequest?
    private(set) var mediaDelivery: CaptureMediaDelivery?
    private(set) var pendingAgentTurn: AgentTurnRoute?
    private(set) var pendingWorkoutSession: WorkoutSessionRoute?

    private init() {}

    func request(_ mode: CaptureEntryMode) {
        somaCaptureLogger.info("Received capture request: \(mode.rawValue, privacy: .public)")
        pendingRequest = CaptureEntryRequest(mode: mode)
    }

    func route(_ url: URL) {
        guard url.scheme?.lowercased() == "soma" else {
            somaCaptureLogger.error("Ignored unsupported capture URL")
            return
        }
        if url.host?.lowercased() == "capture",
           let rawMode = url.pathComponents.dropFirst().first,
           let mode = CaptureEntryMode(rawValue: rawMode)
        {
            request(mode)
        } else if url.host?.lowercased() == "agent",
                  url.pathComponents.dropFirst().first == "turn",
                  let rawID = url.pathComponents.dropFirst(2).first,
                  let turnID = UUID(uuidString: rawID)
        {
            requestAgentTurn(turnID)
        } else if url.host?.lowercased() == "workout",
                  url.pathComponents.dropFirst().first == "session",
                  let rawID = url.pathComponents.dropFirst(2).first,
                  let sessionID = UUID(uuidString: rawID)
        {
            requestWorkoutSession(sessionID)
        } else {
            somaCaptureLogger.error("Ignored unsupported Soma URL")
        }
    }

    func clear(_ requestID: UUID) {
        guard pendingRequest?.id == requestID else { return }
        pendingRequest = nil
    }

    func deliver(_ media: [PickedMedia]) {
        guard !media.isEmpty else { return }
        mediaDelivery = CaptureMediaDelivery(media: media)
    }

    func clearDelivery(_ deliveryID: UUID) {
        guard mediaDelivery?.id == deliveryID else { return }
        mediaDelivery = nil
    }

    func requestAgentTurn(_ turnID: UUID) {
        pendingAgentTurn = AgentTurnRoute(turnID: turnID)
    }

    func clearAgentTurn(_ routeID: UUID) {
        guard pendingAgentTurn?.id == routeID else { return }
        pendingAgentTurn = nil
    }

    func requestWorkoutSession(_ sessionID: UUID) {
        pendingWorkoutSession = WorkoutSessionRoute(sessionID: sessionID)
    }

    func clearWorkoutSession(_ routeID: UUID) {
        guard pendingWorkoutSession?.id == routeID else { return }
        pendingWorkoutSession = nil
    }
}

struct StartSomaCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "在 Soma 中记录"
    static let description = IntentDescription("打开 Soma，直接开始输入文字、拍照或选择照片与视频。")
    static let openAppWhenRun = true

    @Parameter(title: "记录方式")
    var mode: CaptureEntryMode

    init() {
        mode = .text
    }

    init(mode: CaptureEntryMode) {
        self.mode = mode
    }

    func perform() async throws -> some IntentResult {
        await SomaCaptureRouter.shared.request(mode)
        return .result()
    }
}

struct SomaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSomaCaptureIntent(mode: .text),
            phrases: [
                "用 \(.applicationName) 记录文字",
                "在 \(.applicationName) 里记录"
            ],
            shortTitle: "记录文字",
            systemImageName: "text.bubble"
        )

        AppShortcut(
            intent: StartSomaCaptureIntent(mode: .camera),
            phrases: [
                "用 \(.applicationName) 拍照记录",
                "打开 \(.applicationName) 相机"
            ],
            shortTitle: "拍照记录",
            systemImageName: "camera"
        )

        AppShortcut(
            intent: StartSomaCaptureIntent(mode: .media),
            phrases: [
                "给 \(.applicationName) 添加照片",
                "用 \(.applicationName) 选择视频"
            ],
            shortTitle: "选择照片与视频",
            systemImageName: "photo.on.rectangle.angled"
        )
    }
}
