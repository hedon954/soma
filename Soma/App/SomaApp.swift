import Observation
import SwiftData
import SwiftUI

enum DataSpace: String, CaseIterable, Identifiable {
    case personal
    case demo

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .personal: "个人数据"
        case .demo: "演示数据"
        }
    }

    var shortTitle: String {
        switch self {
        case .personal: "个人"
        case .demo: "演示"
        }
    }

    var icon: String {
        switch self {
        case .personal: "person.fill"
        case .demo: "sparkles"
        }
    }
}

@MainActor
@Observable
final class DataSpaceController {
    static let defaultsKey = "data.activeSpace"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let demoContainer: ModelContainer
    @ObservationIgnored let personalContainer: ModelContainer
    private(set) var activeSpace: DataSpace

    init(
        defaults: UserDefaults = .standard,
        isStoredInMemoryOnly: Bool = false
    ) {
        self.defaults = defaults
        activeSpace = defaults.string(forKey: Self.defaultsKey)
            .flatMap(DataSpace.init(rawValue:))
            ?? .demo

        let schema = Schema([
            ExternalSyncCursor.self,
            UserProfile.self,
            GymProfile.self,
            GymEquipment.self,
            GymMedia.self,
            MealEntry.self,
            BodyEntry.self,
            WorkoutEntry.self,
            CoachMessage.self,
            AgentTrace.self
        ])
        let demoConfiguration = ModelConfiguration(
            nil,
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
        let personalConfiguration = ModelConfiguration(
            "PersonalData",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )

        do {
            demoContainer = try ModelContainer(
                for: schema,
                configurations: [demoConfiguration]
            )
            personalContainer = try ModelContainer(
                for: schema,
                configurations: [personalConfiguration]
            )
        } catch {
            fatalError("无法创建本地数据空间：\(error.localizedDescription)")
        }
    }

    var activeContainer: ModelContainer {
        activeSpace == .demo ? demoContainer : personalContainer
    }

    func select(_ space: DataSpace) {
        guard activeSpace != space else { return }
        activeSpace = space
        defaults.set(space.rawValue, forKey: Self.defaultsKey)
    }

    func toggle() {
        select(activeSpace == .demo ? .personal : .demo)
    }
}

@main
struct SomaApp: App {
    @State private var aiService = AIService()
    @State private var dataSpace = DataSpaceController()
    @State private var conversationProcessor = ConversationProcessingService()
    @State private var captureRouter = SomaCaptureRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(dataSpace.activeSpace)
                .environment(aiService)
                .environment(dataSpace)
                .environment(conversationProcessor)
                .environment(captureRouter)
                .modelContainer(dataSpace.activeContainer)
                .onOpenURL { url in
                    captureRouter.route(url)
                }
        }
    }
}
