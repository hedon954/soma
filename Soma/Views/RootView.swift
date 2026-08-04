import OSLog
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case coach, training, insights
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
    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var workoutSessions: [WorkoutSession]
    @Query(sort: \TrainingProgram.updatedAt, order: .reverse)
    private var trainingPrograms: [TrainingProgram]
    @Query(sort: \WorkoutEntry.date, order: .reverse)
    private var workouts: [WorkoutEntry]
    @Query(sort: \WorkoutSet.order) private var workoutSets: [WorkoutSet]
    @State private var selectedTab: AppTab = .coach
    @State private var sheet: RootSheet?
    @State private var routedWorkoutSession: WorkoutSession?
    @State private var routedTrainingProgramID: UUID?

    private var widgetSnapshotFingerprint: String {
        let sessionValues = workoutSessions.map {
            "\($0.id.uuidString):\($0.statusRaw):\($0.guidedPhaseRaw):\($0.endedAt?.timeIntervalSinceReferenceDate ?? 0)"
        }
        let programValues = trainingPrograms.map {
            "\($0.id.uuidString):\($0.statusRaw):\($0.updatedAt.timeIntervalSinceReferenceDate)"
        }
        let workoutValues = workouts.map {
            "\($0.id.uuidString):\($0.date.timeIntervalSinceReferenceDate)"
        }
        let setValues = workoutSets.map {
            "\($0.id.uuidString):\($0.statusRaw):\($0.completedAt?.timeIntervalSinceReferenceDate ?? 0)"
        }
        return (sessionValues + programValues + workoutValues + setValues).joined(separator: "|")
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CoachView {
                    sheet = .settings(
                        initialRoute: .aiService,
                        showsAIConfigurationReminder: true
                    )
                }
                .toolbar { settingsToolbar }
            }
            .tabItem { Label("教练", systemImage: "bubble.left.and.bubble.right.fill") }
            .tag(AppTab.coach)

            NavigationStack {
                TrainingProgramLibraryView(
                    requestedProgramID: $routedTrainingProgramID
                )
                .toolbar { settingsToolbar }
            }
            .tabItem { Label("训练", systemImage: "figure.strengthtraining.traditional") }
            .tag(AppTab.training)

            NavigationStack {
                InsightsView()
                    .toolbar { settingsToolbar }
            }
            .tabItem { Label("进展", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(AppTab.insights)
        }
        .tint(AppTheme.tint)
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
        .onChange(of: captureRouter.pendingTrainingProgram, initial: true) {
            handleTrainingProgramRoute()
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
        }
        .task(id: widgetSnapshotFingerprint) {
            SomaWidgetSnapshotProjector.refresh(
                in: modelContext,
                dataSpace: dataSpace.activeSpace
            )
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

    private func handleTrainingProgramRoute() {
        guard let route = captureRouter.pendingTrainingProgram else { return }
        selectedTab = .training
        routedTrainingProgramID = route.programID
        captureRouter.clearTrainingProgram(route.id)
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                sheet = .settings(
                    initialRoute: nil,
                    showsAIConfigurationReminder: false
                )
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("设置")
        }
    }
}
