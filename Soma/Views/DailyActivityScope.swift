import SwiftData
import SwiftUI

/// 根层持有查询 owner；每次回前台在个人空间强制重读，不依赖是否打开进展。
struct DailyActivityScope: ViewModifier {
    @Environment(DataSpaceController.self) private var dataSpace
    @Environment(\.scenePhase) private var scenePhase
    @State private var activity = DailyActivitySyncCoordinator()
    @State private var energy = EnergyRefreshCoordinator()

    func body(content: Content) -> some View {
        content
            .environment(activity)
            .environment(energy)
            .task {
                await activity.prepare()
                updateContext()
            }
            .onDisappear {
                activity.setContext(space: dataSpace.activeSpace, foreground: false)
                energy.bind(context: nil, foreground: false)
            }
            .onChange(of: scenePhase) {
                if scenePhase != .inactive {
                    updateContext()
                }
            }
            .onChange(of: dataSpace.migrationState) { updateContext() }
            .onChange(of: dataSpace.activeSpace) { updateContext() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in updateContext() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in updateContext() }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { energy.saved($0) }
            .onReceive(NotificationCenter.default.publisher(for: .personalDataDidReplace)) { _ in
                let token = activity.beginDisconnect()
                Task { await activity.finishDisconnect(generation: token) }
            }
    }

    private func updateContext() {
        let container = dataSpace.activeSpace == .personal ? dataSpace.personalContainer : dataSpace.demoContainer
        energy.bind(context: container?.mainContext, foreground: scenePhase == .active)
        activity.bind(context: dataSpace.activeSpace == .personal ? dataSpace.personalContainer?.mainContext : nil)
        activity.setContext(space: dataSpace.activeSpace, foreground: scenePhase == .active)
    }
}
