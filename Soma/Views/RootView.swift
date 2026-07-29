import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case coach, insights
}

private enum RootSheet: String, Identifiable {
    case settings
    var id: String {
        rawValue
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataSpaceController.self) private var dataSpace
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
            case .settings: SettingsView()
            }
        }
        .task {
            if dataSpace.activeSpace == .demo {
                DemoSeeder.seedIfNeeded(modelContext)
            }
            DataIntegrityRepair.finalizeInterruptedAgentTraces(in: modelContext)
            DataIntegrityRepair.removeUnsupportedInferences(in: modelContext)
        }
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
