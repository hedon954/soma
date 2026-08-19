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

enum DataMigrationRecovery: Equatable {
    case none
    case clearPersonalOnly
    case clearAllStores
}

@MainActor
@Observable
final class DataSpaceController {
    static let defaultsKey = "data.activeSpace"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isStoredInMemoryOnly: Bool
    @ObservationIgnored private let migrationStoreNames = [
        "default.store",
        "PersonalData.store"
    ]
    @ObservationIgnored private(set) var demoContainer: ModelContainer!
    @ObservationIgnored private(set) var personalContainer: ModelContainer!
    private(set) var activeSpace: DataSpace
    private(set) var migrationState: DataMigrationState
    private(set) var recoveryMode: DataMigrationRecovery = .none
    private(set) var migrationFailureDetail: String?

    init(
        defaults: UserDefaults = .standard,
        isStoredInMemoryOnly: Bool = ProcessInfo.processInfo.environment[
            "XCTestConfigurationFilePath"
        ] != nil
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
            recoveryMode = .clearAllStores
            migrationFailureDetail = SomaMigrationDiagnostics.report(
                error: error,
                context: "无法打开本地数据",
                origin: "DataSpaceController.init",
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                demoContainerPresent: false,
                personalContainerPresent: false
            )
            migrationState = .failed(
                "无法打开本地数据：\(error.localizedDescription)"
            )
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
        recoveryMode = .none
        migrationState = .running
        migrationFailureDetail = nil
        await Task.yield()
        do {
            try ensureContainers()
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
            recoveryMode = .clearPersonalOnly
            migrationFailureDetail = SomaMigrationDiagnostics.report(
                error: error,
                context: "迁移失败",
                origin: "DataSpaceController.runLaunchMigration",
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                demoContainerPresent: demoContainer != nil,
                personalContainerPresent: personalContainer != nil
            )
            migrationState = .failed(error.localizedDescription)
        }
    }

    func recoverWithStoreResetAndRetry(
        clearAllStores: Bool
    ) async {
        guard migrationState != .running, migrationState != .ready else {
            return
        }
        migrationState = .running
        recoveryMode = .none
        migrationFailureDetail = nil
        await Task.yield()
        do {
            clearStoreFiles(
                clearAll: clearAllStores
            )
            demoContainer = nil
            personalContainer = nil
            let containers = try Self.makeContainers(
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
            demoContainer = containers.demo
            personalContainer = containers.personal
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
            recoveryMode = clearAllStores ? .clearAllStores : .clearPersonalOnly
            migrationFailureDetail = SomaMigrationDiagnostics.report(
                error: error,
                context: "清理后重试失败",
                origin: "DataSpaceController.recoverWithStoreResetAndRetry",
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                demoContainerPresent: demoContainer != nil,
                personalContainerPresent: personalContainer != nil
            )
            migrationState = .failed("清理后重试失败：\(error.localizedDescription)")
        }
    }

    private func ensureContainers() throws {
        if demoContainer == nil || personalContainer == nil {
            let containers = try Self.makeContainers(
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
            demoContainer = containers.demo
            personalContainer = containers.personal
        }
    }

    private static func applicationSupportDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    private func clearStoreFiles(clearAll: Bool) {
        let supportDirectory = try? Self.applicationSupportDirectory()
        guard let supportDirectory else { return }

        let backupDirectory = supportDirectory
            .appendingPathComponent(".soma-migration-recovery")
            .appendingPathComponent(
                Self.iso8601DateFormatter.string(from: Date())
            )
        try? FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )

        let targetStores = clearAll ? migrationStoreNames : ["PersonalData.store"]
        for baseName in targetStores {
            for candidate in [baseName, "\(baseName)-wal", "\(baseName)-shm"] {
                let candidateURL = supportDirectory.appendingPathComponent(candidate)
                if FileManager.default.fileExists(atPath: candidateURL.path) {
                    let backupURL = backupDirectory.appendingPathComponent(candidate)
                    try? FileManager.default.removeItem(at: backupURL)
                    do {
                        try FileManager.default.moveItem(at: candidateURL, to: backupURL)
                    } catch {
                        try? FileManager.default.removeItem(at: candidateURL)
                    }
                }
            }
        }
    }

    private static let iso8601DateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.timeZone = .current
        return formatter
    }()

    private static func makeContainers(
        isStoredInMemoryOnly: Bool
    ) throws -> (demo: ModelContainer, personal: ModelContainer) {
        if !isStoredInMemoryOnly {
            let support = try applicationSupportDirectory()
            do {
                try SomaStorePreflight.repairProjectionKeysIfNeeded(
                    at: support.appendingPathComponent("default.store")
                )
                try SomaStorePreflight.repairProjectionKeysIfNeeded(
                    at: support.appendingPathComponent("PersonalData.store")
                )
            } catch {
                throw DataMigrationError.stepFailed("打开容器前补齐训练投影键", error)
            }
        }
        let schema = Schema(SomaDataSchema.models)
        let demo = try SomaStoreOpening.makeContainer(
            configurationName: nil,
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            stepName: "打开演示数据容器"
        )
        let personal = try SomaStoreOpening.makeContainer(
            configurationName: "PersonalData",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            stepName: "打开个人数据容器"
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
        ScrollView {
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
                    if dataSpace.recoveryMode != .none {
                        Divider()
                        Text("如果迁移仍持续失败，可先清理旧数据库再重试（会清空对应数据）。")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if dataSpace.recoveryMode == .clearPersonalOnly {
                            Button("清空个人数据并重试") {
                                Task {
                                    await dataSpace.recoverWithStoreResetAndRetry(
                                        clearAllStores: false
                                    )
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        } else if dataSpace.recoveryMode == .clearAllStores {
                            Button("清空个人与演示数据并重试") {
                                Task {
                                    await dataSpace.recoverWithStoreResetAndRetry(
                                        clearAllStores: true
                                    )
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }
                        if dataSpace.recoveryMode == .clearPersonalOnly {
                            Button("清空全部数据并重试") {
                                Task {
                                    await dataSpace.recoverWithStoreResetAndRetry(
                                        clearAllStores: true
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                    if let detail = dataSpace.migrationFailureDetail, !detail.isEmpty {
                        Divider()
                        Text("完整诊断")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("可选择复制。含训练记录结构样例，不含身体测量、饮食原文和聊天正文。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(detail)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("迁移诊断报告")
                    }
                    ShareLink(
                        item: {
                            var exportText = "Soma 数据迁移失败：\(message)"
                            if let detail = dataSpace.migrationFailureDetail,
                               !detail.isEmpty
                            {
                                exportText += "\n\n\(detail)"
                            }
                            return exportText
                        }(),
                        subject: Text("Soma 数据迁移诊断")
                    ) {
                        Label("导出诊断", systemImage: "square.and.arrow.up")
                    }
                case .ready:
                    EmptyView()
                }
            }
            .padding(32)
        }
        .accessibilityElement(children: .contain)
    }
}
