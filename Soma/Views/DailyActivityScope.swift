import SwiftData
import SwiftUI

/// 根层持有查询 owner；每次回前台在个人空间强制重读，不依赖是否打开进展。
struct DailyActivityScope: ViewModifier {
    @Environment(DataSpaceController.self) private var dataSpace
    @Environment(\.scenePhase) private var scenePhase
    @State private var activity = DailyActivitySyncCoordinator()
    @State private var bodyMass = BodyMassSyncCoordinator()
    @State private var energy = EnergyRefreshCoordinator()

    func body(content: Content) -> some View {
        content
            .environment(activity)
            .environment(bodyMass)
            .environment(energy)
            .task {
                await activity.prepare()
                updateContext()
            }
            .onDisappear {
                activity.setContext(space: dataSpace.activeSpace, foreground: false)
                bodyMass.setContext(space: dataSpace.activeSpace, foreground: false)
                energy.bind(context: nil, foreground: false)
            }
            .onChange(of: scenePhase) {
                if scenePhase != .inactive {
                    updateContext()
                }
            }
            .onChange(of: dataSpace.migrationState) { updateContext() }
            .onChange(of: dataSpace.activeSpace) { updateContext() }
            .onChange(of: activity.isEnabled) {
                bodyMass.setEnabled(activity.isEnabled)
                bodyMass.setContext(space: dataSpace.activeSpace, foreground: scenePhase == .active)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in updateContext() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in updateContext() }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { energy.saved($0) }
            .onReceive(NotificationCenter.default.publisher(for: .personalDataDidReplace)) { _ in
                let token = activity.beginDisconnect()
                bodyMass.setEnabled(false)
                Task { await activity.finishDisconnect(generation: token) }
            }
    }

    private func updateContext() {
        let container = dataSpace.activeSpace == .personal ? dataSpace.personalContainer : dataSpace.demoContainer
        energy.bind(context: container?.mainContext, foreground: scenePhase == .active)
        let personalContext = dataSpace.activeSpace == .personal ? dataSpace.personalContainer?.mainContext : nil
        activity.bind(context: personalContext)
        bodyMass.bind(context: personalContext)
        bodyMass.setEnabled(activity.isEnabled)
        activity.setContext(space: dataSpace.activeSpace, foreground: scenePhase == .active)
        bodyMass.setContext(space: dataSpace.activeSpace, foreground: scenePhase == .active)
    }
}
