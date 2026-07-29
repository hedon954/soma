import OSLog
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case coach, insights
}

private enum RootSheet: Identifiable {
    case settings

    var id: String {
        "settings"
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataSpaceController.self) private var dataSpace
    @Environment(SomaCaptureRouter.self) private var captureRouter
    @State private var selectedTab: AppTab = .coach
    @State private var sheet: RootSheet?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CoachView()
                    .toolbar { settingsToolbar }
            }
            .tabItem { Label("教练", systemImage: "bubble.left.and.bubble.right.fill") }
            .tag(AppTab.coach)

            NavigationStack {
                InsightsView()
                    .toolbar { settingsToolbar }
            }
            .tabItem { Label("进展", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(AppTab.insights)
        }
        .tint(AppTheme.tint)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .settings:
                SettingsView()
            }
        }
        .onChange(of: captureRouter.pendingRequest, initial: true) {
            handleCaptureRequest()
        }
        .task {
            if dataSpace.activeSpace == .demo {
                DemoSeeder.seedIfNeeded(modelContext)
            }
            DataIntegrityRepair.finalizeInterruptedAgentTraces(in: modelContext)
            DataIntegrityRepair.removeUnsupportedInferences(in: modelContext)
        }
    }

    private func handleCaptureRequest() {
        guard let request = captureRouter.pendingRequest else { return }
        somaCaptureLogger.info(
            "Routing capture request in root: \(request.mode.rawValue, privacy: .public)"
        )
        selectedTab = .coach
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                sheet = .settings
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("设置")
        }
    }
}
