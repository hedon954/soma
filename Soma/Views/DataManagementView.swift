import SwiftUI
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Environment(DataManagementCoordinator.self) private var coordinator
    @Environment(DataSpaceController.self) private var dataSpace
    @Environment(ConversationSessionController.self) private var conversationSessions
    @State private var folderPurpose: FolderPurpose?
    @State private var showFolderImporter = false
    @State private var passwordRequest: BackupPasswordRequest?
    @State private var restoreConfirmation: PendingRestore?
    @State private var showRestoreConfirmation = false
    @State private var notice: DataManagementNotice?
    @State private var showExportDisclosure = false
    @State private var showClearConfirmation = false
    @State private var showDisconnectConfirmation = false

    var body: some View {
        Form {
            exportSection
            backupSection
            clearSection
        }
        .navigationTitle("数据与备份")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder]
        ) { result in
            handleFolderResult(result)
        }
        .sheet(item: $passwordRequest) { request in
            BackupPasswordSheet(request: request) { password in
                handlePassword(password, request: request)
            }
        }
        .confirmationDialog(
            "导出会生成未加密副本",
            isPresented: $showExportDisclosure,
            titleVisibility: .visible
        ) {
            Button("选择导出文件夹") {
                presentFolderImporter(for: .export)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("目标文件夹、云盘或共享成员可能读取其中的文字、照片与视频，请选择你信任的位置。")
        }
        .confirmationDialog(
            "用备份替换个人数据？",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("替换并恢复", role: .destructive) {
                guard let restoreConfirmation else { return }
                self.restoreConfirmation = nil
                Task {
                    await performRestore(restoreConfirmation)
                }
            }
            Button("取消", role: .cancel) {
                restoreConfirmation = nil
            }
        } message: {
            Text("恢复会替换当前个人空间。演示数据、AI API Key 和系统相册不会改变。")
        }
        .confirmationDialog(
            "清除个人数据？",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("永久清除本机个人数据", role: .destructive) {
                performClear()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除个人记录、聊天和专属沙盒媒体，并断开自动备份；外部导出和备份不会删除。此操作无法撤销。")
        }
        .confirmationDialog(
            "停止自动备份？",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("停止自动备份", role: .destructive) {
                coordinator.disconnectBackup()
                notice = DataManagementNotice(
                    title: "已停止自动备份",
                    message: "外部文件夹中的已有备份仍然保留。"
                )
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Soma 会忘记所选目录和本机派生密钥，但不会删除已有备份。")
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
        .overlay {
            if let activity = coordinator.activity {
                ProgressView(activity.title)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(activity.title)
            }
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                showExportDisclosure = true
            } label: {
                Label("导出饮食与训练", systemImage: "folder.badge.plus")
            }
            .disabled(coordinator.isWorking)

            if let result = coordinator.lastExportResult {
                LabeledContent(
                    "上次导出",
                    value: "\(result.mealCount) 条饮食 · \(result.workoutCount) 条训练"
                )
            }
        } header: {
            Text("导出")
        } footer: {
            Text("生成按年、月、日整理的普通文件夹，包含原始文字、分析 JSON、图片和视频。即使不再使用 Soma，也可以直接保留和阅读。")
        }
    }

    private var backupSection: some View {
        Section {
            if coordinator.isBackupConfigured {
                LabeledContent(
                    "备份位置",
                    value: coordinator.backupDestinationName ?? "已选择文件夹"
                )
                if let lastBackupAt = coordinator.lastBackupAt {
                    LabeledContent("最后成功") {
                        Text(lastBackupAt, format: .dateTime
                            .year()
                            .month()
                            .day()
                            .hour()
                            .minute())
                    }
                } else {
                    LabeledContent("最后成功", value: "尚未完成")
                }
                if let error = coordinator.lastErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Button {
                    Task {
                        await performBackupNow()
                    }
                } label: {
                    Label("立即备份", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(coordinator.isWorking)

                Button {
                    presentFolderImporter(for: .configureBackup)
                } label: {
                    Label("更换文件夹或密码", systemImage: "folder")
                }
                .disabled(coordinator.isWorking)
            } else {
                LabeledContent("自动备份", value: "未设置")
                Button {
                    presentFolderImporter(for: .configureBackup)
                } label: {
                    Label("设置自动备份", systemImage: "externaldrive.badge.plus")
                }
                .disabled(coordinator.isWorking)
            }

            Button {
                presentFolderImporter(for: .restore)
            } label: {
                Label("从备份恢复", systemImage: "arrow.counterclockwise")
            }
            .disabled(coordinator.isWorking)

            if coordinator.isBackupConfigured {
                Button("停止自动备份", role: .destructive) {
                    showDisconnectConfirmation = true
                }
                .disabled(coordinator.isWorking)
            }
        } header: {
            Text("备份与恢复")
        } footer: {
            Text("首次选择文件夹并设置密码后，Soma 会立即备份；个人数据变化后，App 进入后台时会尽力更新。备份包含完整个人空间和媒体，使用密码加密；请妥善记住密码。")
        }
    }

    private var clearSection: some View {
        Section {
            Button("清除个人数据", role: .destructive) {
                showClearConfirmation = true
            }
            .disabled(coordinator.isWorking)
        } header: {
            Text("清除数据")
        } footer: {
            Text("只清除 Soma 个人空间和专属沙盒媒体。演示数据、AI API Key、系统相册以及外部导出与备份不会删除。")
        }
    }

    private func handleFolderResult(_ result: Result<URL, Error>) {
        guard let purpose = folderPurpose else { return }
        folderPurpose = nil
        switch result {
        case let .success(url):
            switch purpose {
            case .export:
                Task {
                    await performExport(to: url)
                }
            case .configureBackup:
                passwordRequest = BackupPasswordRequest(
                    purpose: .configure,
                    directoryURL: url
                )
            case .restore:
                passwordRequest = BackupPasswordRequest(
                    purpose: .restore,
                    directoryURL: url
                )
            }
        case let .failure(error):
            if (error as NSError).code != NSUserCancelledError {
                showError(error)
            }
        }
    }

    private func presentFolderImporter(for purpose: FolderPurpose) {
        folderPurpose = purpose
        showFolderImporter = true
    }

    private func handlePassword(
        _ password: String,
        request: BackupPasswordRequest
    ) {
        passwordRequest = nil
        switch request.purpose {
        case .configure:
            Task {
                await performConfigureBackup(
                    destination: request.directoryURL,
                    password: password
                )
            }
        case .restore:
            restoreConfirmation = PendingRestore(
                directoryURL: request.directoryURL,
                password: password
            )
            showRestoreConfirmation = true
        }
    }

    private func performExport(to destination: URL) async {
        do {
            let result = try await coordinator.exportRecords(
                to: destination,
                personalContainer: dataSpace.personalContainer
            )
            let missing = result.missingMediaCount > 0
                ? "；\(result.missingMediaCount) 个已不存在的媒体已在 manifest 中标记"
                : ""
            notice = DataManagementNotice(
                title: "导出完成",
                message: "已导出 \(result.mealCount) 条饮食、\(result.workoutCount) 条训练和 \(result.copiedMediaCount) 个媒体\(missing)。"
            )
        } catch {
            showError(error)
        }
    }

    private func performConfigureBackup(
        destination: URL,
        password: String
    ) async {
        do {
            let result = try await coordinator.configureBackup(
                destination: destination,
                password: password,
                personalContainer: dataSpace.personalContainer
            )
            notice = DataManagementNotice(
                title: "自动备份已开启",
                message: "首份备份已完成：\(result.modelCount) 条数据，\(result.mediaCount) 个媒体。App 进入后台时会继续更新。"
            )
        } catch {
            showError(error)
        }
    }

    private func performBackupNow() async {
        do {
            guard let result = try await coordinator.backupNow(
                personalContainer: dataSpace.personalContainer
            ) else {
                return
            }
            notice = DataManagementNotice(
                title: "备份完成",
                message: "已备份 \(result.modelCount) 条数据和 \(result.mediaCount) 个媒体。"
            )
        } catch {
            showError(error)
        }
    }

    private func performRestore(_ pending: PendingRestore) async {
        do {
            try await coordinator.restore(
                from: pending.directoryURL,
                password: pending.password,
                dataSpace: dataSpace
            )
            resolvePersonalSessionIfActive()
            notice = DataManagementNotice(
                title: "恢复完成",
                message: "个人数据和媒体已从备份恢复。"
            )
        } catch {
            showError(error)
        }
    }

    private func performClear() {
        Task {
            do {
                let result = try await coordinator.clearPersonalData(
                    dataSpace: dataSpace
                )
                resolvePersonalSessionIfActive()
                notice = DataManagementNotice(
                    title: "个人数据已清除",
                    message: "已删除 \(result.deletedModelCount) 条本机数据和 \(result.deletedMediaCount) 个专属媒体；外部备份仍然保留。"
                )
            } catch {
                showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        notice = DataManagementNotice(
            title: "操作未完成",
            message: error.localizedDescription
        )
    }

    private func resolvePersonalSessionIfActive() {
        guard dataSpace.activeSpace == .personal else { return }
        conversationSessions.resolveForEntry(
            dataSpace: .personal,
            in: dataSpace.personalContainer.mainContext
        )
    }
}

private enum FolderPurpose {
    case export
    case configureBackup
    case restore
}

private struct PendingRestore {
    var directoryURL: URL
    var password: String
}

private struct DataManagementNotice: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

private struct BackupPasswordRequest: Identifiable {
    enum Purpose {
        case configure
        case restore
    }

    let id = UUID()
    var purpose: Purpose
    var directoryURL: URL
}

private struct BackupPasswordSheet: View {
    let request: BackupPasswordRequest
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""

    private var isConfigure: Bool {
        request.purpose == .configure
    }

    private var canSubmit: Bool {
        password.count >= 8 && (!isConfigure || password == confirmation)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("备份密码", text: $password)
                        .textContentType(.password)
                    if isConfigure {
                        SecureField("再次输入密码", text: $confirmation)
                            .textContentType(.newPassword)
                    }
                } footer: {
                    Text(isConfigure
                        ? "至少 8 个字符。Soma 不会保存明文密码，也无法找回密码。"
                        : "输入创建这份备份时使用的密码。")
                }

                if isConfigure, !confirmation.isEmpty, password != confirmation {
                    Label("两次输入的密码不一致", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(isConfigure ? "设置备份密码" : "输入备份密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isConfigure ? "创建备份" : "继续") {
                        onSubmit(password)
                        dismiss()
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }
}
