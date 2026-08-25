import OSLog
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case coach, training, insights, settings

    var performanceName: String {
        switch self {
        case .coach: "coach"
        case .training: "training"
        case .insights: "insights"
        case .settings: "settings"
        }
    }
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

/// 只由这个极小的叶子观察 Tab 内容显隐。RootView 因选中项刷新时，
/// 不再为四棵导航树各重建一个捕获 Root 状态的 `.task` 闭包。
@MainActor
private struct RootTabVisibilityReporter: View {
    let tab: AppTab
    let transition: AppTabTransitionCoordinator

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task {
                await Task.yield()
                guard !Task.isCancelled else { return }
                transition.contentDidBecomeVisible(tab)
            }
    }
}

/// 四个根 Tab 是四个独立的 SwiftUI 子树。Root 只交付选中值，不再在每次点击时
/// 重新组装 NavigationStack、查询根页和内容可见性 modifier。
private struct CoachRootTab: View {
    @Binding var sheet: RootSheet?
    let isActive: Bool
    let transition: AppTabTransitionCoordinator

    var body: some View {
        NavigationStack {
            CoachView(isTabActive: isActive) {
                sheet = .settings(
                    initialRoute: .llm,
                    showsAIConfigurationReminder: true
                )
            }
        }
        .background {
            RootTabVisibilityReporter(tab: .coach, transition: transition)
        }
    }
}

private struct TrainingRootTab: View {
    let transition: AppTabTransitionCoordinator

    var body: some View {
        NavigationStack {
            TrainingProgramLibraryView()
        }
        .background {
            RootTabVisibilityReporter(tab: .training, transition: transition)
        }
    }
}

private struct InsightsRootTab: View {
    let transition: AppTabTransitionCoordinator

    var body: some View {
        NavigationStack {
            InsightsView()
        }
        .background {
            RootTabVisibilityReporter(tab: .insights, transition: transition)
        }
    }
}

private struct SettingsRootTab: View {
    let transition: AppTabTransitionCoordinator

    var body: some View {
        SettingsView(isEmbeddedInTab: true)
            .background {
                RootTabVisibilityReporter(tab: .settings, transition: transition)
            }
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
    @State private var tabTransition = AppTabTransitionCoordinator()
    @State private var didFinishInitialMaintenance = false

    var body: some View {
        rootTabs
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
                selectCoachTabIfNeeded()
            }
            .onAppear {
                AppPerformance.event(
                    .rootVisible,
                    detail: "space=\(dataSpace.activeSpace.rawValue)"
                )
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .prefillCoachDraft)
            ) { _ in
                selectCoachTabIfNeeded()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification
                )
            ) { _ in
                Task {
                    await ImagePipeline.shared.removeAllCachedImages()
                }
                CoachTextRenderCache.removeAll()
                CoachMessageRenderPayloadCache.removeAll()
                TrainingIntelligenceService.removeCachedPerformanceFingerprints()
            }
            .task {
                // `.task` 已经在 Root 挂载后触发，但缓存命中时首个 async 调用
                // 可能同步返回。先主动让出一次 MainActor，保证首帧和首个点击优先。
                await Task.yield()
                await ai.warmRequiredAPIKeyCache()
                let performanceInterval = AppPerformance.begin(
                    .rootMaintenance,
                    detail: "space=\(dataSpace.activeSpace.rawValue)"
                )
                defer {
                    AppPerformance.end(
                        performanceInterval,
                        detail: "space=\(dataSpace.activeSpace.rawValue)"
                    )
                }
                await RemoteAgentRevocationService.retryIfNeeded()
                if dataSpace.activeSpace == .demo {
                    DemoSeeder.seedIfNeeded(modelContext)
                }
                DataIntegrityRepair.finalizeInterruptedAgentTraces(in: modelContext)
                await Task.yield()
                let bundledContentKey = "exercise.bundledContent.\(dataSpace.activeSpace.rawValue).v1"
                if !UserDefaults.standard.bool(forKey: bundledContentKey) {
                    ExerciseLibraryStore.activateBundledContent(in: modelContext)
                    UserDefaults.standard.set(true, forKey: bundledContentKey)
                }
                if dataSpace.activeSpace == .demo {
                    DemoTrainingPlanSeeder.seedIfNeeded(in: modelContext)
                }
                let performanceSession = PerformanceTestFixture
                    .seedLongStreamIfRequested(in: modelContext)
                conversationSessions.resolveForEntry(
                    dataSpace: dataSpace.activeSpace,
                    in: modelContext
                )
                if let performanceSession {
                    conversationSessions.select(
                        performanceSession,
                        dataSpace: dataSpace.activeSpace
                    )
                    processor.startLongStreamPerformanceFixture(
                        dataSpace: dataSpace.activeSpace,
                        sessionID: performanceSession.id
                    )
                }
                startDevicePerformanceHarnessIfRequested()
                await Task.yield()
                processor.resumePendingJobs(
                    dataSpace: dataSpace.activeSpace,
                    ai: ai,
                    modelContext: modelContext,
                    locationService: locationContext
                )
                // ADR 0095：启动只投递已有的系统确认报告，不再把哨兵未清位当作崩溃。
                await CrashDiagnosticsCoordinator.shared.flushPendingReports()
                await Task.yield()
                await MediaMaintenance.shared.reclaimOrphansIfNeeded(
                    personalContainer: dataSpace.personalContainer,
                    demoContainer: dataSpace.demoContainer
                )
                didFinishInitialMaintenance = true
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    // 首次 active 与上面的 root task 处在同一启动窗口。等待初次
                    // 收口完成后才允许执行真正的前台恢复，避免启动时重复查询。
                    guard didFinishInitialMaintenance else { return }
                    Task {
                        await RemoteAgentRevocationService.retryIfNeeded()
                        await Task.yield()
                        guard scenePhase == .active else { return }
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
                } else if scenePhase == .background {
                    dataManagement.backupWhenEnteringBackground(
                        personalContainer: dataSpace.personalContainer
                    )
                }
            }
    }

    /// iOS 18 起直接使用 TabContentBuilder。当前 SDK 已把旧的
    /// `.tabItem + .tag` 路径标记为迁移方向；iOS 17 只保留兼容分支。
    /// 两条路径复用完全相同的内容，导航栈身份和再选回根语义不变。
    @ViewBuilder
    private var rootTabs: some View {
        if #available(iOS 18.0, *) {
            modernRootTabs
        } else {
            legacyRootTabs
        }
    }

    @available(iOS 18.0, *)
    private var modernRootTabs: some View {
        TabView(selection: tabSelection) {
            Tab(
                "教练",
                systemImage: "bubble.left.and.bubble.right",
                value: AppTab.coach
            ) {
                coachTab
            }
            Tab("训练", systemImage: "dumbbell", value: AppTab.training) {
                trainingTab
            }
            Tab(
                "进展",
                systemImage: "chart.line.uptrend.xyaxis",
                value: AppTab.insights
            ) {
                insightsTab
            }
            Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                settingsTab
            }
        }
    }

    private var legacyRootTabs: some View {
        TabView(selection: tabSelection) {
            coachTab
                .tabItem {
                    Label(
                        "教练",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                }
                .tag(AppTab.coach)

            trainingTab
                .tabItem { Label("训练", systemImage: "dumbbell") }
                .tag(AppTab.training)

            insightsTab
                .tabItem {
                    Label("进展", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(AppTab.insights)

            settingsTab
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }

    private var coachTab: some View {
        CoachRootTab(
            sheet: $sheet,
            isActive: selectedTab == .coach,
            transition: tabTransition
        )
        .id(tabStackIDs[.coach])
    }

    private var trainingTab: some View {
        TrainingRootTab(transition: tabTransition)
            .id(tabStackIDs[.training])
    }

    private var insightsTab: some View {
        InsightsRootTab(transition: tabTransition)
            .id(tabStackIDs[.insights])
    }

    private var settingsTab: some View {
        // PRD 020 修订：设置从各页右上角 gear 收敛为底部第 4 个 Tab。
        SettingsRootTab(transition: tabTransition)
            .id(tabStackIDs[.settings])
    }

    private func handleCaptureRequest() {
        guard let request = captureRouter.pendingRequest else { return }
        somaCaptureLogger.info(
            "Routing capture request in root: \(request.mode.rawValue, privacy: .public)"
        )
        selectCoachTabIfNeeded()
    }

    private func handleAgentTurnRoute() {
        guard let route = captureRouter.pendingAgentTurn else {
            return
        }
        let turnID = route.turnID
        var jobDescriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate { job in
                job.turnID == turnID
            },
            sortBy: [SortDescriptor(\AgentJob.createdAt, order: .reverse)]
        )
        jobDescriptor.fetchLimit = 1
        guard let job = try? modelContext.fetch(jobDescriptor).first else { return }
        let sessionID = job.sessionID
        var sessionDescriptor = FetchDescriptor<ConversationSession>(
            predicate: #Predicate { session in
                session.id == sessionID
            }
        )
        sessionDescriptor.fetchLimit = 1
        guard let session = try? modelContext.fetch(sessionDescriptor).first else { return }
        conversationSessions.select(
            session,
            dataSpace: dataSpace.activeSpace
        )
        selectCoachTabIfNeeded()
        captureRouter.clearAgentTurn(route.id)
    }

    private func handleWorkoutSessionRoute() {
        guard let route = captureRouter.pendingWorkoutSession else {
            return
        }
        let sessionID = route.sessionID
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.id == sessionID
            }
        )
        descriptor.fetchLimit = 1
        guard let session = try? modelContext.fetch(descriptor).first else { return }
        routedWorkoutSession = session
        captureRouter.clearWorkoutSession(route.id)
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { incoming in
                switch AppTabReselect.effect(
                    selected: selectedTab,
                    incoming: incoming
                ) {
                case let .switchTo(tab):
                    tabTransition.begin(from: selectedTab, to: tab)
                    selectedTab = tab
                case let .resetStack(tab):
                    tabStackIDs[tab] = UUID()
                }
            }
        )
    }

    private func selectCoachTabIfNeeded() {
        guard selectedTab != .coach else { return }
        tabTransition.begin(from: selectedTab, to: .coach)
        selectedTab = .coach
    }

    private func startDevicePerformanceHarnessIfRequested() {
        guard let mode = DevicePerformanceHarness.mode else { return }
        let rounds = DevicePerformanceHarness.rounds
        Task { @MainActor in
            try? await Task.sleep(for: DevicePerformanceHarness.delay)
            guard !Task.isCancelled else { return }
            switch mode {
            case .tabs:
                let targets: [AppTab] = [.training, .insights, .settings, .coach]
                for _ in 0 ..< rounds {
                    for target in targets {
                        tabSelection.wrappedValue = target
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
            case .sessions:
                var descriptor = FetchDescriptor<ConversationSession>(
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
                descriptor.fetchLimit = 2
                guard let sessions = try? modelContext.fetch(descriptor),
                      sessions.count == 2
                else { return }
                selectCoachTabIfNeeded()
                for _ in 0 ..< rounds {
                    for session in sessions.reversed() {
                        NotificationCenter.default.post(
                            name: .performanceSelectCoachSession,
                            object: session
                        )
                        try? await Task.sleep(for: .milliseconds(450))
                    }
                }
            case .scroll:
                selectCoachTabIfNeeded()
                for _ in 0 ..< rounds {
                    NotificationCenter.default.post(
                        name: .performanceScrollCoach,
                        object: "top"
                    )
                    try? await Task.sleep(for: .milliseconds(350))
                    NotificationCenter.default.post(
                        name: .performanceScrollCoach,
                        object: "bottom"
                    )
                    try? await Task.sleep(for: .milliseconds(350))
                }
            }
        }
    }
}
