import OSLog
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case coach, training, insights, settings
}

private enum RootSheet: Identifiable {
    case settings(
        initialRoute: SettingsRoute?,
        showsAIConfigurationReminder: Bool
    )

    var id: String {
        "settings"
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DataSpaceController.self) private var dataSpace
    @Environment(AIService.self) private var ai
    @Environment(ConversationProcessingService.self) private var processor
    @Environment(ConversationSessionController.self) private var conversationSessions
    @Environment(LocationContextService.self) private var locationContext
    @Environment(SomaCaptureRouter.self) private var captureRouter
    @Environment(DataManagementCoordinator.self) private var dataManagement
    @Query(sort: \AgentJob.createdAt) private var agentJobs: [AgentJob]
    @AppStorage(AppAppearancePreference.defaultsKey)
    private var appearanceRaw = AppAppearancePreference.system.rawValue
    @State private var selectedTab: AppTab = .coach
    @State private var tabStackIDs: [AppTab: UUID] = [
        .coach: UUID(),
        .training: UUID(),
        .insights: UUID(),
        .settings: UUID()
    ]
    @State private var sheet: RootSheet?
    @State private var routedWorkoutSession: WorkoutSession?

    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack {
                CoachView {
                    sheet = .settings(
                        initialRoute: .llm,
                        showsAIConfigurationReminder: true
                    )
                }
            }
            .id(tabStackIDs[.coach])
            .tabItem {
                Label(
                    "教练",
                    systemImage: selectedTab == .coach
                        ? "bubble.left.and.bubble.right.fill"
                        : "bubble.left.and.bubble.right"
                )
            }
            .tag(AppTab.coach)

            NavigationStack {
                TrainingProgramLibraryView()
            }
            .id(tabStackIDs[.training])
            .tabItem {
                Label(
                    "训练",
                    systemImage: selectedTab == .training ? "dumbbell.fill" : "dumbbell"
                )
            }
            .tag(AppTab.training)

            NavigationStack {
                InsightsView()
            }
            .id(tabStackIDs[.insights])
            .tabItem { Label("进展", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(AppTab.insights)

            // PRD 020 修订：设置从各页右上角 gear 收敛为底部第 4 个 Tab。
            SettingsView(isEmbeddedInTab: true)
                .id(tabStackIDs[.settings])
                .tabItem {
                    Label(
                        "设置",
                        systemImage: selectedTab == .settings ? "gearshape.fill" : "gearshape"
                    )
                }
                .tag(AppTab.settings)
        }
        .tint(AppTheme.tint)
        .toolbarBackground(AppTheme.pageBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(
            AppAppearancePolicy.rootColorScheme(storedRawValue: appearanceRaw)
        )
        .overlay(alignment: .topLeading) {
            AgentSystemProjectionHost()
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case let .settings(initialRoute, showsAIConfigurationReminder):
                SettingsView(
                    initialRoute: initialRoute,
                    showsAIConfigurationReminder: showsAIConfigurationReminder
                )
            }
        }
        .onChange(of: captureRouter.pendingRequest, initial: true) {
            handleCaptureRequest()
        }
        .onChange(of: captureRouter.pendingAgentTurn, initial: true) {
            handleAgentTurnRoute()
        }
        .onChange(of: captureRouter.pendingWorkoutSession, initial: true) {
            handleWorkoutSessionRoute()
        }
        .fullScreenCover(item: $routedWorkoutSession) { session in
            NavigationStack {
                GuidedWorkoutView(session: session)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .openCoachConversation)
        ) { _ in
            selectedTab = .coach
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .prefillCoachDraft)
        ) { _ in
            selectedTab = .coach
        }
        .task {
            await RemoteAgentRevocationService.retryIfNeeded()
            if dataSpace.activeSpace == .demo {
                DemoSeeder.seedIfNeeded(modelContext)
            }
            DataIntegrityRepair.finalizeInterruptedAgentTraces(in: modelContext)
            DataIntegrityRepair.backfillConversationTurns(in: modelContext)
            DataIntegrityRepair.mergeObviousDuplicateRecords(in: modelContext)
            DataIntegrityRepair.removeUnsupportedInferences(in: modelContext)
            DataIntegrityRepair.migrateLegacyWorkoutSets(in: modelContext)
            ExerciseLibraryStore.migrateLegacyWorkoutNames(in: modelContext)
            ExerciseLibraryStore.activateBundledContent(in: modelContext)
            if dataSpace.activeSpace == .demo {
                DemoTrainingPlanSeeder.seedIfNeeded(in: modelContext)
            }
            GuidedWorkoutRecordStore.backfill(in: modelContext)
            conversationSessions.resolveForEntry(
                dataSpace: dataSpace.activeSpace,
                in: modelContext
            )
            processor.resumePendingJobs(
                dataSpace: dataSpace.activeSpace,
                ai: ai,
                modelContext: modelContext,
                locationService: locationContext
            )
            // ADR 0095：启动只投递已有的系统确认报告，不再把哨兵未清位当作崩溃。
            await CrashDiagnosticsCoordinator.shared.flushPendingReports()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task {
                    await RemoteAgentRevocationService.retryIfNeeded()
                }
                conversationSessions.resolveForEntry(
                    dataSpace: dataSpace.activeSpace,
                    in: modelContext
                )
                processor.resumePendingJobs(
                    dataSpace: dataSpace.activeSpace,
                    ai: ai,
                    modelContext: modelContext,
                    locationService: locationContext
                )
            } else if scenePhase == .background {
                dataManagement.backupWhenEnteringBackground(
                    personalContainer: dataSpace.personalContainer
                )
            }
        }
    }

    private func handleCaptureRequest() {
        guard let request = captureRouter.pendingRequest else { return }
        somaCaptureLogger.info(
            "Routing capture request in root: \(request.mode.rawValue, privacy: .public)"
        )
        selectedTab = .coach
    }

    private func handleAgentTurnRoute() {
        guard let route = captureRouter.pendingAgentTurn,
              let job = agentJobs.first(where: {
                  $0.turnID == route.turnID
              }),
              let session = (
                  try? modelContext.fetch(
                      FetchDescriptor<ConversationSession>()
                  )
              )?.first(where: { $0.id == job.sessionID })
        else {
            return
        }
        conversationSessions.select(
            session,
            dataSpace: dataSpace.activeSpace
        )
        selectedTab = .coach
        captureRouter.clearAgentTurn(route.id)
    }

    private func handleWorkoutSessionRoute() {
        guard let route = captureRouter.pendingWorkoutSession,
              let session = (
                  try? modelContext.fetch(FetchDescriptor<WorkoutSession>())
              )?.first(where: { $0.id == route.sessionID })
        else {
            return
        }
        routedWorkoutSession = session
        captureRouter.clearWorkoutSession(route.id)
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { incoming in
                if let currentID = tabStackIDs[incoming] {
                    tabStackIDs[incoming] = AppTabReselect.stackID(
                        selected: selectedTab,
                        incoming: incoming,
                        current: currentID
                    )
                }
                selectedTab = incoming
            }
        )
    }
}
