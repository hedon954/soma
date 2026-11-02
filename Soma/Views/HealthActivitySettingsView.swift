import SwiftUI

struct HealthActivitySettingsView: View {
    @Environment(DailyActivitySyncCoordinator.self) private var activity
    @Environment(DataSpaceController.self) private var dataSpace

    var body: some View {
        Form {
            Section {
                Text("读取每日步数、步行与跑步距离、活动消耗，以及训练的类型、时间和活动能量。每日三项覆盖为一条运动记录；训练依据用于避免跑步与步数重复计算。")
                Text("记录与来源信息仅保存在本机，不发送给教练模型，也不进入备份与导出。")
            } header: { Text("读取范围") }
                .listRowBackground(AppTheme.cardBackground)

            Section {
                if dataSpace.activeSpace == .demo {
                    Text("演示空间使用虚构数据。切换到个人空间后可连接 Apple 健康。")
                } else if activity.needsCleanup {
                    Button("重试断开") { Task { await activity.disconnect() } }
                        .frame(minHeight: 44)
                } else if activity.isEnabled {
                    Label("已启用读取", systemImage: "checkmark.circle")
                    if !activity.hasRequestedTrainingAccess {
                        Button("允许读取训练") { Task { await activity.connect() } }
                            .disabled(activity.isConnecting)
                            .frame(minHeight: 44)
                    }
                    Button("重新读取") { activity.refresh() }
                        .frame(minHeight: 44)
                    Button("断开连接", role: .destructive) {
                        Task { await activity.disconnect() }
                    }.frame(minHeight: 44)
                        .accessibilityIdentifier("health-disconnect")
                } else {
                    Button {
                        Task { await activity.connect() }
                    } label: {
                        HStack {
                            Text(activity.isConnecting ? "正在连接…" : "连接 Apple 健康")
                            Spacer()
                            if activity.isConnecting {
                                ProgressView()
                            }
                        }.frame(minHeight: 44)
                    }
                    .disabled(activity.isConnecting || !activity.isPrepared || !activity.isAvailable)
                    .accessibilityIdentifier("health-connect")
                    if !activity.isAvailable {
                        Text("此设备无法使用 Apple 健康。")
                    }
                }
                if let error = activity.errorMessage {
                    Text(error)
                }
            } header: { Text("连接") }
                .listRowBackground(AppTheme.cardBackground)

            Section {
                Text("先在 COROS App 的第三方应用中开启 Apple 健康同步，并允许写入这三项。Soma 会保留 Apple 健康实际返回的来源。")
                Text("连接后，每次打开 Soma 或回到前台都会重新读取每日汇总并覆盖旧值，不累加历次同步结果。")
                Text("暂无数据也可能是未允许读取。可在 Apple 健康的个人资料 → App → Soma 中调整访问；断开后停止同步，已同步的运动记录保留。")
            } header: { Text("同步与访问") }
                .listRowBackground(AppTheme.cardBackground)
        }
        .foregroundStyle(AppTheme.accent)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("Apple 健康")
        .navigationBarTitleDisplayMode(.inline)
    }
}
