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
    @ObservationIgnored private let isStoredInMemoryOnly: Bool
    @ObservationIgnored private(set) var demoContainer: ModelContainer!
    @ObservationIgnored private(set) var personalContainer: ModelContainer!
    private(set) var activeSpace: DataSpace
    private(set) var migrationState: DataMigrationState

    init(
        defaults: UserDefaults = .standard,
        isStoredInMemoryOnly: Bool = false
    ) {
        self.defaults = defaults
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        activeSpace = defaults.string(forKey: Self.defaultsKey)
            .flatMap(DataSpace.init(rawValue:))
            ?? .demo
        migrationState = .pending
        demoContainer = nil
        personalContainer = nil

        do {
            let containers = try Self.makeContainers(
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
            demoContainer = containers.demo
            personalContainer = containers.personal
            migrationState = isStoredInMemoryOnly ? .ready : .pending
        } catch {
            migrationState = .failed("无法打开本地数据：\(error.localizedDescription)")
        }
    }

    var activeContainer: ModelContainer {
        guard let container = activeSpace == .demo ? demoContainer : personalContainer else {
            preconditionFailure("迁移完成前不能访问业务数据容器。")
        }
        return container
    }

    func select(_ space: DataSpace) {
        guard activeSpace != space else { return }
        activeSpace = space
        defaults.set(space.rawValue, forKey: Self.defaultsKey)
    }

    func toggle() {
        select(activeSpace == .demo ? .personal : .demo)
    }

    func runLaunchMigration() async {
        guard migrationState != .running, migrationState != .ready else { return }
        migrationState = .running
        await Task.yield()
        do {
            if demoContainer == nil || personalContainer == nil {
                let containers = try Self.makeContainers(
                    isStoredInMemoryOnly: isStoredInMemoryOnly
                )
                demoContainer = containers.demo
                personalContainer = containers.personal
            }
            try SomaDataMigration.migrateIfNeeded(
                container: personalContainer,
                dataSpace: .personal
            )
            try SomaDataMigration.migrateIfNeeded(
                container: demoContainer,
                dataSpace: .demo
            )
            migrationState = .ready
        } catch {
            migrationState = .failed(error.localizedDescription)
        }
    }

    private static func makeContainers(
        isStoredInMemoryOnly: Bool
    ) throws -> (demo: ModelContainer, personal: ModelContainer) {
        let schema = Schema(versionedSchema: SomaDataSchemaV4.self)
        let demo = try ModelContainer(
            for: schema,
            migrationPlan: SomaSchemaMigrationPlan.self,
            configurations: [ModelConfiguration(
                nil,
                schema: schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudKitDatabase: .none
            )]
        )
        let personal = try ModelContainer(
            for: schema,
            migrationPlan: SomaSchemaMigrationPlan.self,
            configurations: [ModelConfiguration(
                "PersonalData",
                schema: schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudKitDatabase: .none
            )]
        )
        return (demo, personal)
    }
}

enum DataMigrationState: Equatable {
    case pending
    case running
    case ready
    case failed(String)
}

@main
struct SomaApp: App {
    @UIApplicationDelegateAdaptor(SomaAppDelegate.self)
    private var appDelegate
    @State private var aiService = AIService()
    @State private var dataSpace = DataSpaceController()
    @State private var conversationProcessor = ConversationProcessingService()
    @State private var conversationSessions = ConversationSessionController()
    @State private var locationContext = LocationContextService()
    @State private var captureRouter = SomaCaptureRouter.shared
    @State private var dataManagement = DataManagementCoordinator()
    @State private var workoutRuntime = WorkoutRuntime()
    @State private var agentSystemProjection =
        AgentSystemProjectionCoordinator()

    var body: some Scene {
        WindowGroup {
            Group {
                if dataSpace.migrationState == .ready {
                    RootView()
                        .id(dataSpace.activeSpace)
                        .modelContainer(dataSpace.activeContainer)
                } else {
                    DataMigrationGateView()
                }
            }
            .environment(aiService)
            .environment(dataSpace)
            .environment(conversationProcessor)
            .environment(conversationSessions)
            .environment(locationContext)
            .environment(captureRouter)
            .environment(dataManagement)
            .environment(workoutRuntime)
            .environment(workoutRuntime.coordinator)
            .environment(workoutRuntime.camera)
            .environment(agentSystemProjection)
            .onOpenURL { url in
                captureRouter.route(url)
            }
            .task {
                await dataSpace.runLaunchMigration()
            }
        }
    }
}

private struct DataMigrationGateView: View {
    @Environment(DataSpaceController.self) private var dataSpace

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.timemachine")
                .font(.system(size: 42))
                .foregroundStyle(AppTheme.tint)
                .accessibilityHidden(true)
            Text("正在准备 Soma 数据")
                .font(.title2.bold())
            switch dataSpace.migrationState {
            case .pending, .running:
                ProgressView()
                Text("迁移完成前不会打开记录，也不会继续 Agent 任务。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case let .failed(message):
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("重试迁移") {
                    Task { await dataSpace.runLaunchMigration() }
                }
                .buttonStyle(.borderedProminent)
                ShareLink(
                    item: "Soma 数据迁移失败：\(message)",
                    subject: Text("Soma 数据迁移诊断")
                ) {
                    Label("导出诊断", systemImage: "square.and.arrow.up")
                }
            case .ready:
                EmptyView()
            }
        }
        .padding(32)
        .accessibilityElement(children: .contain)
    }
}
