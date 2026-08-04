import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AIService.self) private var ai
    @Environment(DataSpaceController.self) private var dataSpace
    @AppStorage(ConversationLocationPreference.defaultsKey)
    private var locationPreferenceRaw = ConversationLocationPreference.unasked.rawValue
    @Query(sort: \AgentTrace.startedAt, order: .reverse) private var agentTraces: [AgentTrace]

    @State private var modelTier: AIModelTier = .standard
    @State private var smallModelEnabled = false
    @State private var provider: AIProvider = .openAI
    @State private var baseURL = ""
    @State private var model = ""
    @State private var imageModel = ""
    @State private var apiKey = ""
    @State private var models: [AIModelInfo] = []
    @State private var isLoadingModels = false
    @State private var modelError: String?
    @State private var keySaved = false
    @State private var showKey = false
    @State private var path: [SettingsRoute]
    private let showsAIConfigurationReminder: Bool

    init(
        initialRoute: SettingsRoute? = nil,
        showsAIConfigurationReminder: Bool = false
    ) {
        _path = State(initialValue: initialRoute.map { [$0] } ?? [])
        self.showsAIConfigurationReminder = showsAIConfigurationReminder
    }

    private var selectedCapability: MultimodalSupport {
        models.first(where: { $0.id == model })?.multimodalSupport
            ?? ModelCapability.multimodalSupport(provider: provider, model: model)
    }

    private var locationEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                locationPreferenceRaw == ConversationLocationPreference.enabled.rawValue
            },
            set: { enabled in
                locationPreferenceRaw = (
                    enabled
                        ? ConversationLocationPreference.enabled
                        : ConversationLocationPreference.disabled
                ).rawValue
            }
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                profileAndTrainingSection
                serviceSection
                privacyAndAdvancedSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        persistConfiguration()
                        dismiss()
                    }
                }
            }
            .onAppear(perform: loadInitialConfiguration)
            .onChange(of: smallModelEnabled) {
                ai.setTierEnabled(smallModelEnabled, tier: .small)
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .aiService:
                    Form {
                        if showsAIConfigurationReminder {
                            AIConfigurationReminder()
                        }
                        aiSection
                    }
                    .navigationTitle("AI 服务")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .task(id: "\(modelTier.rawValue).\(provider.rawValue)") {
                guard !apiKey.isEmpty else { return }
                await refreshModels()
            }
        }
    }

    private var profileAndTrainingSection: some View {
        Section("个人与训练") {
            NavigationLink {
                PersonalBodyInfoView()
            } label: {
                Label("身体信息", systemImage: "person.text.rectangle")
            }

            NavigationLink {
                GymLibraryView()
            } label: {
                Label("健身房", systemImage: "building.2")
            }

            NavigationLink {
                WidgetSettingsView()
            } label: {
                SettingsSummaryRow(
                    icon: "rectangle.3.group.fill",
                    title: "主屏组件",
                    detail: "训练状态、计划与快速记录"
                )
            }
        }
    }

    private var serviceSection: some View {
        Section("服务") {
            NavigationLink(value: SettingsRoute.aiService) {
                SettingsSummaryRow(
                    icon: "sparkles",
                    title: "AI 教练",
                    detail: ai.hasRequiredAPIKey
                        ? "\(ai.provider.displayName) · \(ai.model(for: ai.provider).isEmpty ? "未选择模型" : ai.model(for: ai.provider))"
                        : "需要配置 API Key"
                )
            }

            NavigationLink {
                HealthDataIntegrationsView()
            } label: {
                SettingsSummaryRow(
                    icon: "heart.text.square",
                    title: "健康数据与设备",
                    detail: "Apple 健康、Keep、COROS"
                )
            }

            NavigationLink {
                AgentSystemSettingsView()
            } label: {
                SettingsSummaryRow(
                    icon: "waveform.path.ecg",
                    title: "任务进度与通知",
                    detail: "锁屏、灵动岛与完成提醒"
                )
            }

            NavigationLink {
                RemoteAgentSettingsView()
            } label: {
                SettingsSummaryRow(
                    icon: "server.rack",
                    title: "后台持续处理",
                    detail: RemoteAgentPreference.isEnabled()
                        ? "已开启 · Soma 管理模型"
                        : "默认关闭"
                )
            }
        }
    }

    private var privacyAndAdvancedSection: some View {
        Section("更多") {
            NavigationLink {
                DataManagementView()
            } label: {
                Label("数据与备份", systemImage: "externaldrive")
            }

            NavigationLink {
                Form {
                    privacySection
                    safetySection
                }
                .navigationTitle("隐私与安全")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("隐私与安全", systemImage: "hand.raised")
            }

            NavigationLink {
                DeveloperSettingsView()
            } label: {
                HStack {
                    Label("高级设置", systemImage: "gearshape.2")
                    Spacer()
                    if !agentTraces.isEmpty {
                        Text("\(agentTraces.count) 条日志")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("Soma", value: "1.0.0 (1)")
            Text("Your body, understood.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let attributionURL = URL(string: "https://open-meteo.com/") {
                LabeledContent("天气数据") {
                    Link("Open-Meteo", destination: attributionURL)
                }
            }
        }
    }

    private var gymSection: some View {
        Section {
            NavigationLink {
                GymLibraryView()
            } label: {
                Label("管理健身房", systemImage: "building.2")
            }
        } header: {
            Text("训练环境")
        } footer: {
            Text("在这里审查健身房照片与器械；当前健身房也可在聊天输入框上方快速切换。")
        }
    }

    private var personalSection: some View {
        Section {
            NavigationLink {
                PersonalBodyInfoView()
            } label: {
                Label("身体信息", systemImage: "person.text.rectangle")
            }
        } header: {
            Text("个人")
        } footer: {
            Text("用于个性化训练建议和本地运动热量估算。所有字段均可留空，只保存在当前数据空间。")
        }
    }

    private var dataSpaceSection: some View {
        Section {
            Picker(
                "当前数据",
                selection: Binding(
                    get: { dataSpace.activeSpace },
                    set: { dataSpace.select($0) }
                )
            ) {
                ForEach(DataSpace.allCases) { space in
                    Label(space.title, systemImage: space.icon)
                        .tag(space)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("数据空间")
        } footer: {
            Text("两个空间完全隔离。演示数据用于体验完整功能；个人数据只保存你自己的聊天、照片与 AI 记录，切换不会删除任何数据。")
        }
    }

    private var privacySection: some View {
        Section {
            Label("无账户系统", systemImage: "person.crop.circle.badge.xmark")
            Label("数据库与媒体保存在 App 沙盒", systemImage: "internaldrive.fill")
            Label("每个平台的 API Key 仅存入本机 Keychain", systemImage: "key.fill")
            Toggle(isOn: locationEnabledBinding) {
                Label("随消息记录位置", systemImage: "location")
            }
            Label("天气仅在相关消息中按需获取", systemImage: "cloud.sun")
        } header: {
            Text("隐私")
        } footer: {
            Text("首次发送时 Soma 会询问是否随消息记录位置；无论允许或拒绝都不再自动询问，可在这里修改。开启后仅在发送时获取一次并保存在本机，不持续或后台跟踪。天气或户外消息会向 Open-Meteo 发送约 1 公里精度的位置，服务方同时可见设备 IP；远程 Agent 不接收原始坐标。")
        }
    }

    private var aiSection: some View {
        Section {
            Picker("模型档位", selection: modelTierBinding) {
                ForEach(AIModelTier.allCases) { tier in
                    Text(tier.title).tag(tier)
                }
            }
            .pickerStyle(.segmented)

            if modelTier == .small {
                Toggle("配置小模型", isOn: $smallModelEnabled)
            }

            if modelTier == .standard || smallModelEnabled {
                Picker("平台", selection: providerBinding) {
                    ForEach(AIProvider.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }

                TextField(
                    provider == .other ? "自定义 OpenAI-compatible URL" : "兼容 API Base URL",
                    text: $baseURL
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

                if isLoadingModels {
                    LabeledContent("可用模型") {
                        ProgressView()
                            .controlSize(.small)
                    }
                } else if models.isEmpty {
                    LabeledContent("可用模型") {
                        Text(apiKey.isEmpty ? "保存 API Key 后自动获取" : "暂无列表，可手动输入")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("手动模型 ID") {
                        TextField("输入模型 ID", text: $model)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } else {
                    Picker("可用模型", selection: $model) {
                        if !models.contains(where: { $0.id == model }) {
                            Text("当前：\(model)").tag(model)
                        }
                        ForEach(models) { option in
                            Text(option.id).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                capabilityRow

                if modelTier == .standard {
                    LabeledContent("图片生成模型") {
                        TextField("例如 gpt-image-2", text: $imageModel)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Text("动作图片只会在你从动作详情主动点击生成时请求；不会在打开页面或记录训练时自动生成。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Group {
                        if showKey {
                            TextField("API Key", text: $apiKey)
                        } else {
                            SecureField("API Key", text: $apiKey)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel(showKey ? "隐藏 API Key" : "显示 API Key")
                }

                HStack {
                    Button(keySaved ? "API Key 已保存" : "保存并获取模型") {
                        saveKeyAndRefresh()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()

                    Button {
                        Task { await refreshModels() }
                    } label: {
                        if isLoadingModels {
                            ProgressView()
                        } else {
                            Label("刷新模型", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(apiKey.isEmpty || isLoadingModels)
                }

                if let modelError {
                    Label(modelError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.warning)
                } else if !models.isEmpty {
                    Text("已从 \(provider.displayName) 获取 \(models.count) 个可用模型。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("AI 服务")
        } footer: {
            Text("小模型可不配置；配置后，Agent 只把短文本、无媒体且无业务写入意图的简单任务交给小模型，其余使用标准模型。当前输入、同一对话最近 10 个来回，以及视觉额度内的压缩图片或视频关键帧会发送给所选平台，原始媒体继续留在本机。")
        }
    }

    private var capabilityRow: some View {
        HStack(spacing: 8) {
            Image(systemName: capabilityIcon)
                .foregroundStyle(capabilityColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCapability.label)
                    .font(.subheadline.weight(.medium))
                if selectedCapability == .unsupported {
                    Text("图片和视频不会发送给这个模型，请更换模型。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var capabilityIcon: String {
        switch selectedCapability {
        case .supported: "photo.badge.checkmark"
        case .unsupported: "photo.badge.exclamationmark"
        case .unknown: "questionmark.circle"
        }
    }

    private var capabilityColor: Color {
        switch selectedCapability {
        case .supported: AppTheme.tint
        case .unsupported: AppTheme.warning
        case .unknown: .secondary
        }
    }

    private var safetySection: some View {
        Section("动作安全") {
            Label("AI 反馈用于训练记录和一般性建议，不能替代医生、物理治疗师或现场教练。", systemImage: "cross.case")
                .foregroundStyle(.secondary)
            Label("出现锐痛、眩晕或关节异常时应立即停止训练。", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    private func loadInitialConfiguration() {
        locationPreferenceRaw = ConversationLocationPreference.current().rawValue
        smallModelEnabled = ai.isTierEnabled(.small)
        loadTierConfiguration(.standard)
    }

    private var modelTierBinding: Binding<AIModelTier> {
        Binding(
            get: { modelTier },
            set: { newTier in
                guard newTier != modelTier else { return }
                persistConfiguration()
                modelTier = newTier
                loadTierConfiguration(newTier)
            }
        )
    }

    private var providerBinding: Binding<AIProvider> {
        Binding(
            get: { provider },
            set: { newProvider in
                guard newProvider != provider else { return }
                persistConfiguration()
                provider = newProvider
                loadProviderConfiguration()
            }
        )
    }

    private func loadTierConfiguration(_ tier: AIModelTier) {
        provider = ai.provider(for: tier)
        loadProviderConfiguration()
    }

    private func loadProviderConfiguration() {
        baseURL = ai.baseURL(for: provider, tier: modelTier)
        model = ai.model(for: provider, tier: modelTier)
        imageModel = ai.imageModel(for: provider)
        apiKey = ai.apiKey(for: provider, tier: modelTier)
        models = []
        modelError = nil
        keySaved = !apiKey.isEmpty
    }

    private func persistConfiguration(
        tier: AIModelTier? = nil,
        provider configuredProvider: AIProvider? = nil
    ) {
        ai.configure(
            tier: tier ?? modelTier,
            provider: configuredProvider ?? provider,
            baseURL: baseURL,
            model: model
        )
        if (tier ?? modelTier) == .standard {
            ai.configureImageModel(
                imageModel,
                for: configuredProvider ?? provider
            )
        }
    }

    private func saveKeyAndRefresh() {
        persistConfiguration()
        ai.saveAPIKey(apiKey, for: provider, tier: modelTier)
        keySaved = true
        Task { await refreshModels() }
    }

    @MainActor
    private func refreshModels() async {
        let requestedProvider = provider
        let requestedBaseURL = baseURL
        let requestedAPIKey = apiKey
        isLoadingModels = true
        modelError = nil
        defer {
            if provider == requestedProvider {
                isLoadingModels = false
            }
        }

        do {
            let fetched = try await ai.fetchAvailableModels(
                provider: requestedProvider,
                baseURL: requestedBaseURL,
                apiKey: requestedAPIKey
            )
            try Task.checkCancellation()
            guard provider == requestedProvider else { return }
            models = fetched
            if !fetched.contains(where: { $0.id == model }),
               let suggested = fetched.first(where: { $0.multimodalSupport == .supported }) ?? fetched.first
            {
                model = suggested.id
                persistConfiguration()
            }
        } catch {
            guard !Task.isCancelled, provider == requestedProvider else { return }
            models = []
            modelError = error.localizedDescription
        }
    }
}

private struct HealthDataIntegrationsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("healthkit.lastImportAt") private var lastImportAt = 0.0
    @State private var isImporting = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(healthStatus)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Apple 健康", systemImage: "heart.fill")
                        .foregroundStyle(.primary)
                }

                Button {
                    importHealthData()
                } label: {
                    if isImporting {
                        HStack {
                            ProgressView()
                            Text("正在同步…")
                        }
                    } else {
                        Label("授权并同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isImporting || !HealthKitImporter.isAvailable)

                if let resultMessage {
                    Label(resultMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.tint)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.warning)
                }
            } header: {
                Text("Apple 健康")
            } footer: {
                Text("只读取你明确授权的最近一年体重、训练和训练活动能量，并转换为 Soma 记录写入当前数据空间。每类数据分别保存增量游标，同时按 HealthKit 样本 ID 去重并同步来源删除；权限可随时在“健康”App 中撤销。")
            }

            Section {
                LabeledContent("直接接入", value: "暂不可用")
                Text("目前没有找到 Keep 面向个人开发者开放的官方运动数据 API，因此不提供不可用的登录开关。若 Keep 已把相关数据写入 Apple 健康，可通过上方 HealthKit 路径读取支持的数据类型。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Keep")
            }

            Section {
                LabeledContent("推荐方式", value: "经 Apple 健康")
                Text("COROS 官方支持把部分日常与训练相关数据同步到 Apple 健康。Soma 可读取其中获准的体重和 HealthKit 训练；更完整的 COROS 云端直连需要开发者申请 OAuth API 凭据。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Link(
                    "查看 COROS 与 Apple 健康同步说明",
                    destination: URL(string: "https://support.coros.com/hc/en-us/articles/360041549551-Connecting-Apple-Health-with-COROS-App")!
                )
                Link(
                    "申请 COROS API 接入",
                    destination: URL(string: "https://support.coros.com/hc/en-us/articles/17085887816340-Submitting-an-API-Application")!
                )
            } header: {
                Text("COROS")
            }
        }
        .navigationTitle("健康数据与设备")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var healthStatus: String {
        guard HealthKitImporter.isAvailable else { return "当前设备不可用" }
        guard lastImportAt > 0 else { return "尚未同步" }
        return Date(timeIntervalSince1970: lastImportAt)
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func importHealthData() {
        isImporting = true
        resultMessage = nil
        errorMessage = nil
        Task {
            defer { isImporting = false }
            do {
                let result = try await HealthKitImporter.requestAuthorizationAndImport(
                    into: modelContext
                )
                lastImportAt = Date.now.timeIntervalSince1970
                resultMessage = result.summary
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PersonalBodyInfoView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProfile.updatedAt, order: .reverse) private var profiles: [UserProfile]
    @Query(sort: \BodyEntry.date, order: .reverse) private var bodyEntries: [BodyEntry]

    @State private var displayName = ""
    @State private var biologicalSex: BiologicalSex = .unspecified
    @State private var birthDate = Calendar.current.date(
        byAdding: .year,
        value: -25,
        to: .now
    ) ?? .now
    @State private var hasBirthDate = false
    @State private var height = ""
    @State private var referenceWeight = ""
    @State private var fitnessGoal = ""
    @State private var healthNotes = ""
    @State private var loadedProfileID: UUID?

    private var profile: UserProfile? {
        loadedProfileID.flatMap { id in profiles.first(where: { $0.id == id }) }
            ?? profiles.first
    }

    private var latestMeasuredWeight: Double? {
        bodyEntries.compactMap(\.weight).first
    }

    private var postureEntries: [BodyEntry] {
        bodyEntries.filter { $0.imagePath != nil }
    }

    var body: some View {
        Form {
            Section("基本信息") {
                ProfileFieldRow(title: "称呼", placeholder: "可选", text: $displayName)

                Picker("生理性别", selection: $biologicalSex) {
                    ForEach(BiologicalSex.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }

                Toggle("填写出生日期", isOn: $hasBirthDate)
                if hasBirthDate {
                    DatePicker(
                        "出生日期",
                        selection: $birthDate,
                        in: earliestBirthDate ... Date.now,
                        displayedComponents: .date
                    )
                }
                ProfileFieldRow(
                    title: "身高",
                    placeholder: "未填写",
                    unit: "cm",
                    text: $height,
                    keyboard: .decimalPad
                )
                ProfileFieldRow(
                    title: "参考体重",
                    placeholder: "未填写",
                    unit: "kg",
                    text: $referenceWeight,
                    keyboard: .decimalPad
                )
            }

            Section {
                ProfileFieldRow(
                    title: "健身目标",
                    placeholder: "例如：提升力量、减脂或保持健康",
                    text: $fitnessGoal,
                    isMultiline: true
                )
                ProfileFieldRow(
                    title: "身体限制与注意事项",
                    placeholder: "例如：膝盖不适、医生给出的运动限制",
                    text: $healthNotes,
                    isMultiline: true
                )
            } header: {
                Text("训练上下文")
            } footer: {
                Text("AI 只会把这里的信息当作上下文，不会据此进行医学诊断。")
            }

            Section {
                if postureEntries.isEmpty {
                    Label {
                        Text("在教练对话中发送体态图后，会自动保存在这里。")
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "person.crop.rectangle.badge.plus")
                            .foregroundStyle(AppTheme.tint)
                    }
                } else {
                    ForEach(postureEntries) { entry in
                        NavigationLink {
                            BodyRecordDetailView(entry: entry)
                        } label: {
                            HStack(spacing: 12) {
                                MediaThumbnail(
                                    kind: .image,
                                    path: entry.imagePath,
                                    fallbackIcon: "figure.stand"
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline.weight(.medium))
                                    Text(postureSummary(entry))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                modelContext.delete(entry)
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("删除体态记录")
                            .tint(.red)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("体态图")
                    Spacer()
                    if !postureEntries.isEmpty {
                        Text("\(postureEntries.count) 张")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("体态图按时间保留，方便在相近拍摄条件下回溯变化。左滑可删除，点入后可编辑解析数据。")
            }

            Section {
                LabeledContent("当前体重来源") {
                    if let latestMeasuredWeight {
                        Text("最近身体记录 · \(formatted(latestMeasuredWeight)) kg")
                    } else if let profileWeight = parsedDouble(referenceWeight) {
                        Text("个人信息 · \(formatted(profileWeight)) kg")
                    } else {
                        Text("未填写")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("计算方式", value: "MET × 体重 × 时长")
            } header: {
                Text("热量估算")
            } footer: {
                Text("优先使用最近一次体重记录。无氧训练缺少实际时长时，可由组数、次数、间歇和每次约 4 秒的动作节奏推算，仅用于热量估算且会明确标记。")
            }
        }
        .navigationTitle("身体信息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isDirty {
                    Button("保存", action: save)
                        .disabled(!isValid)
                }
            }
        }
        .onAppear(perform: load)
    }

    private var isValid: Bool {
        (!hasBirthDate || birthDate <= .now)
            && validDouble(height, range: 80 ... 250)
            && validDouble(referenceWeight, range: 20 ... 400)
    }

    private var isDirty: Bool {
        guard let profile else {
            return [
                displayName, height, referenceWeight, fitnessGoal, healthNotes
            ].contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                || biologicalSex != .unspecified
                || hasBirthDate
        }
        return normalized(displayName) != profile.displayName
            || biologicalSex != profile.biologicalSex
            || birthDateChanged(from: profile.birthDate)
            || parsedDouble(height) != profile.height
            || parsedDouble(referenceWeight) != profile.referenceWeight
            || normalized(fitnessGoal) != profile.fitnessGoal
            || normalized(healthNotes) != profile.healthNotes
    }

    private func load() {
        guard loadedProfileID == nil, let profile = profiles.first else { return }
        loadedProfileID = profile.id
        displayName = profile.displayName
        biologicalSex = profile.biologicalSex
        if let storedBirthDate = profile.birthDate {
            birthDate = storedBirthDate
            hasBirthDate = true
        } else {
            hasBirthDate = false
        }
        height = profile.height.map(formatted) ?? ""
        referenceWeight = profile.referenceWeight.map(formatted) ?? ""
        fitnessGoal = profile.fitnessGoal
        healthNotes = profile.healthNotes
    }

    private func save() {
        let target: UserProfile
        if let profile {
            target = profile
        } else {
            target = UserProfile()
            modelContext.insert(target)
            loadedProfileID = target.id
        }
        target.updatedAt = .now
        target.displayName = normalized(displayName)
        target.biologicalSex = biologicalSex
        target.birthDate = optionalBirthDate
        target.age = nil
        target.height = parsedDouble(height)
        target.referenceWeight = parsedDouble(referenceWeight)
        target.fitnessGoal = normalized(fitnessGoal)
        target.healthNotes = normalized(healthNotes)
        try? modelContext.save()
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parsedDouble(_ value: String) -> Double? {
        Double(normalized(value).replacingOccurrences(of: ",", with: "."))
    }

    private func validDouble(_ value: String, range: ClosedRange<Double>) -> Bool {
        normalized(value).isEmpty || parsedDouble(value).map(range.contains) == true
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    private var optionalBirthDate: Date? {
        guard hasBirthDate else { return nil }
        return Calendar.current.startOfDay(for: birthDate)
    }

    private var earliestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -120, to: .now) ?? .distantPast
    }

    private func birthDateChanged(from storedDate: Date?) -> Bool {
        switch (optionalBirthDate, storedDate) {
        case (nil, nil):
            false
        case let (newDate?, storedDate?):
            !Calendar.current.isDate(newDate, inSameDayAs: storedDate)
        default:
            true
        }
    }

    private func postureSummary(_ entry: BodyEntry) -> String {
        if !entry.analysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entry.analysis
        }
        if let weight = entry.weight {
            return "体重 \(formatted(weight)) kg"
        }
        return "体态图记录"
    }
}

private struct ProfileFieldRow: View {
    let title: String
    let placeholder: String
    var unit: String?
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isMultiline = false

    var body: some View {
        if isMultiline {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(2 ... 6)
                    .keyboardType(keyboard)
            }
            .padding(.vertical, 2)
        } else {
            LabeledContent(title) {
                HStack(spacing: 5) {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .multilineTextAlignment(.trailing)
                    if let unit {
                        Text(unit)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct DeveloperSettingsView: View {
    @Environment(DataSpaceController.self) private var dataSpace
    @Query(sort: \AgentTrace.startedAt, order: .reverse) private var agentTraces: [AgentTrace]
    @State private var customizedSections = Set<ReActPromptSection>()
    @State private var customizedSkills = Set<AgentSkill>()
    @State private var confirmsResetAllPrompts = false
    @State private var confirmsResetAllSkills = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    AgentExecutionLogView()
                } label: {
                    HStack {
                        Label("执行日志", systemImage: "point.3.connected.trianglepath.dotted")
                        Spacer()
                        Text("\(agentTraces.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("审查当前数据空间内每次 ReAct Loop 的完整本地 Trace。")
            }

            Section {
                ForEach(ReActPromptSection.userEditableCases) { section in
                    NavigationLink {
                        ReActPromptEditor(section: section)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(section.title)
                                    .font(.headline)
                                Spacer()
                                Text(customizedSections.contains(section) ? "已自定义" : "默认")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(customizedSections.contains(section) ? AppTheme.tint : .secondary)
                            }
                            Text(section.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("系统提示词")
            } footer: {
                Text("角色与安全策略可以分别自定义和恢复默认。")
            }

            Section {
                Button("全部恢复默认提示词", systemImage: "arrow.counterclockwise", role: .destructive) {
                    confirmsResetAllPrompts = true
                }
            }

            Section {
                ForEach(AgentSkill.allCases) { skill in
                    NavigationLink {
                        AgentSkillEditor(skill: skill)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(skill.title)
                                    .font(.headline)
                                Spacer()
                                Text(customizedSkills.contains(skill) ? "已自定义" : "默认")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(customizedSkills.contains(skill) ? AppTheme.tint : .secondary)
                            }
                            Text(skill.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Skills")
            } footer: {
                Text("系统提示词只披露 Skill 目录；Agent 通过 load_skill 按需加载这里保存的完整内容，加载过程会记录为独立 Span。")
            }

            Section {
                Button("全部恢复默认 Skills", systemImage: "arrow.counterclockwise", role: .destructive) {
                    confirmsResetAllSkills = true
                }
            }

            Section {
                Picker(
                    "当前数据",
                    selection: Binding(
                        get: { dataSpace.activeSpace },
                        set: { dataSpace.select($0) }
                    )
                ) {
                    ForEach(DataSpace.allCases) { space in
                        Label(space.title, systemImage: space.icon)
                            .tag(space)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("演示与调试")
            } footer: {
                Text("演示空间用于展示完整功能；个人空间只保存真实数据。两个空间完全隔离，切换不会删除内容。")
            }
        }
        .navigationTitle("开发者设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            customizedSections = Set(ReActPromptSection.userEditableCases.filter { $0.isCustomized() })
            customizedSkills = Set(AgentSkill.allCases.filter { $0.isCustomized() })
        }
        .alert("恢复全部默认提示词？", isPresented: $confirmsResetAllPrompts) {
            Button("恢复默认", role: .destructive) {
                ReActPromptSection.allCases.forEach { $0.reset() }
                customizedSections = []
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你保存的角色与安全策略自定义内容会被移除。")
        }
        .alert("恢复全部默认 Skills？", isPresented: $confirmsResetAllSkills) {
            Button("恢复默认", role: .destructive) {
                AgentSkill.allCases.forEach { $0.reset() }
                customizedSkills = []
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你保存的全部自定义 Skill 内容都会被移除。")
        }
    }
}

private enum MarkdownEditorMode: String, CaseIterable, Identifiable {
    case edit = "编辑"
    case preview = "预览"

    var id: String {
        rawValue
    }
}

private struct ReActPromptEditor: View {
    let section: ReActPromptSection
    @State private var text: String
    @State private var savedText: String
    @State private var mode: MarkdownEditorMode = .edit
    @State private var confirmsReset = false

    init(section: ReActPromptSection) {
        self.section = section
        let initial = section.text()
        _text = State(initialValue: initial)
        _savedText = State(initialValue: initial)
    }

    var body: some View {
        Form {
            Section {
                Picker("显示方式", selection: $mode) {
                    ForEach(MarkdownEditorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                if mode == .edit {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 360)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    MarkdownText(text)
                        .frame(minHeight: 360, alignment: .topLeading)
                        .padding(.vertical, 6)
                }
            } header: {
                Text(section.title)
            } footer: {
                Text(section.summary)
            }

            Section {
                Button("恢复这一段的默认值", systemImage: "arrow.counterclockwise") {
                    confirmsReset = true
                }
                .disabled(!section.isCustomized() && text == section.defaultText)
            }
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isDirty {
                    Button("保存", action: save)
                        .disabled(normalizedText.isEmpty)
                }
            }
        }
        .alert("恢复默认提示词？", isPresented: $confirmsReset) {
            Button("恢复默认", role: .destructive) {
                section.reset()
                text = section.defaultText
                savedText = section.defaultText
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("“\(section.title)”的自定义内容会被移除。")
        }
    }

    private var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDirty: Bool {
        normalizedText != savedText
    }

    private func save() {
        section.save(text)
        let persisted = section.text()
        text = persisted
        savedText = persisted
    }
}

private struct AgentSkillEditor: View {
    let skill: AgentSkill
    @State private var text: String
    @State private var savedText: String
    @State private var mode: MarkdownEditorMode = .edit
    @State private var confirmsReset = false

    init(skill: AgentSkill) {
        self.skill = skill
        let initial = skill.text()
        _text = State(initialValue: initial)
        _savedText = State(initialValue: initial)
    }

    var body: some View {
        Form {
            Section {
                Picker("显示方式", selection: $mode) {
                    ForEach(MarkdownEditorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                if mode == .edit {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 420)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    MarkdownText(text)
                        .frame(minHeight: 420, alignment: .topLeading)
                        .padding(.vertical, 6)
                }
            } header: {
                Text(skill.title)
            } footer: {
                Text(skill.summary)
            }

            Section {
                LabeledContent("Skill ID", value: skill.rawValue)
                Button("恢复这个 Skill 的默认值", systemImage: "arrow.counterclockwise") {
                    confirmsReset = true
                }
                .disabled(!skill.isCustomized() && text == skill.defaultText)
            } footer: {
                Text("保存后从下一次 load_skill 调用开始生效。")
            }
        }
        .navigationTitle(skill.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isDirty {
                    Button("保存", action: save)
                        .disabled(normalizedText.isEmpty)
                }
            }
        }
        .alert("恢复默认 Skill？", isPresented: $confirmsReset) {
            Button("恢复默认", role: .destructive) {
                skill.reset()
                text = skill.defaultText
                savedText = skill.defaultText
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("“\(skill.title)”的自定义内容会被移除。")
        }
    }

    private var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDirty: Bool {
        normalizedText != savedText
    }

    private func save() {
        skill.save(text)
        let persisted = skill.text()
        text = persisted
        savedText = persisted
    }
}

private enum AgentTraceFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case succeeded = "成功"
    case failed = "失败"

    var id: String {
        rawValue
    }
}

private struct AgentExecutionLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AgentTrace.startedAt, order: .reverse) private var traces: [AgentTrace]
    @State private var filter: AgentTraceFilter = .all

    private var filteredTraces: [AgentTrace] {
        switch filter {
        case .all:
            traces
        case .succeeded:
            traces.filter { $0.status == .succeeded }
        case .failed:
            traces.filter { [.failed, .cancelled].contains($0.status) }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("状态", selection: $filter) {
                    ForEach(AgentTraceFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            if filteredTraces.isEmpty {
                ContentUnavailableView(
                    filter == .all ? "暂无执行日志" : "没有\(filter.rawValue)日志",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("发送消息并完成一次 Agent Loop 后，这里会生成对应 Trace。")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(filteredTraces) { trace in
                        NavigationLink {
                            AgentTraceDetailView(trace: trace)
                        } label: {
                            AgentTraceRow(trace: trace)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                modelContext.delete(trace)
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("删除执行日志")
                            .tint(.red)
                        }
                    }
                } footer: {
                    Text("Trace 只保存在当前数据空间。日志不包含 API Key、Authorization 头或图片 Base64。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("执行日志")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AgentTraceRow: View {
    let trace: AgentTrace

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(TraceStyle.color(for: trace.status))
                    .frame(width: 7, height: 7)
                Text("\(trace.status.title) · Agent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TraceStyle.color(for: trace.status))
                Spacer(minLength: 8)
                if let duration = trace.durationMilliseconds {
                    Text(TraceStyle.duration(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(trace.userInput)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 4)
            }

            Text("\(trace.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(trace.provider)/\(trace.model)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct AgentTraceDetailView: View {
    let trace: AgentTrace

    private var timelineEntries: [AgentTraceTimelineEntry] {
        var kindCounts: [AgentTraceSpanKind: Int] = [:]
        return trace.spans.map { span in
            let nextOrdinal = kindCounts[span.kind, default: 0] + 1
            kindCounts[span.kind] = nextOrdinal
            return AgentTraceTimelineEntry(
                span: span,
                ordinal: nextOrdinal,
                traceStartedAt: trace.startedAt
            )
        }
    }

    private var diagnosticSpan: AgentTraceSpan? {
        trace.spans.first {
            [.failed, .cancelled].contains($0.status) && $0.kind != .output
        } ?? trace.spans.first {
            [.failed, .cancelled].contains($0.status)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                AppCard {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(TraceStyle.color(for: trace.status).opacity(0.13))
                            Image(systemName: TraceStyle.icon(for: trace.status))
                                .font(.title2)
                                .foregroundStyle(TraceStyle.color(for: trace.status))
                        }
                        .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(TraceStyle.detailTitle(for: trace.status))
                                .font(.title3.bold())
                            HStack(spacing: 5) {
                                if let duration = trace.durationMilliseconds {
                                    Text("耗时 \(TraceStyle.duration(duration))")
                                } else {
                                    Text("正在执行")
                                }
                                Text("·")
                                Text("\(trace.spans.count) 个 Span")
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            Text("\(trace.provider)/\(trace.model)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                tracePreviewCard(
                    title: "输入预览",
                    icon: "text.bubble",
                    text: trace.userInput,
                    detail: mediaDescription
                )

                if trace.status == .succeeded, let finalAnswer = trace.finalAnswer {
                    tracePreviewCard(
                        title: "结果预览",
                        icon: "checkmark.bubble.fill",
                        text: finalAnswer,
                        color: AppTheme.tint
                    )
                }

                if [.failed, .cancelled].contains(trace.status),
                   let errorMessage = trace.errorMessage
                {
                    traceErrorCard(errorMessage)
                }

                Text("执行时间线 (\(trace.spans.count))")
                    .font(.title3.bold())
                    .padding(.horizontal, 2)

                AppCard {
                    if timelineEntries.isEmpty {
                        Text("本次执行没有生成 Span。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(timelineEntries) { entry in
                                AgentTraceSpanRow(
                                    entry: entry,
                                    provider: trace.provider,
                                    model: trace.model
                                )
                                if entry.id != timelineEntries.last?.id {
                                    Divider()
                                        .padding(.leading, 42)
                                }
                            }
                        }
                    }
                }

                AppCard {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            traceMetadata("开始", trace.startedAt.formatted(date: .long, time: .standard))
                            traceMetadata("平台", trace.provider)
                            traceMetadata("模型", trace.model)
                            traceMetadata("Endpoint", trace.endpoint)
                            traceMetadata("Trace ID", trace.id.uuidString)
                            if !trace.contextSnapshot.isEmpty {
                                Divider()
                                Text("本地上下文快照")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(trace.contextSnapshot)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, 12)
                    } label: {
                        Label("运行信息", systemImage: "info.circle")
                            .font(.headline)
                    }
                    .tint(.secondary)
                }

                Label(
                    "日志仅保存在当前数据空间，不包含 API Key、Authorization 头或图片 Base64。",
                    systemImage: "lock.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .appPageBackground()
        .navigationTitle("执行详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func traceMetadata(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private var mediaDescription: String? {
        guard trace.mediaKind != .none else { return nil }
        var parts: [String] = []
        if trace.imageAttachmentCount > 0 {
            parts.append("\(trace.imageAttachmentCount) 张图片")
        }
        if trace.videoAttachmentCount > 0 {
            parts.append("\(trace.videoAttachmentCount) 个视频")
        }
        if parts.isEmpty {
            parts.append(trace.mediaKind == .video ? "视频" : "图片")
        }
        parts.append("\(trace.imageCount) 个分析帧")
        return parts.joined(separator: " · ")
    }

    private func tracePreviewCard(
        title: String,
        icon: String,
        text: String,
        detail: String? = nil,
        color: Color = .primary
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 9) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                Text(text)
                    .font(.subheadline)
                    .textSelection(.enabled)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func traceErrorCard(_ errorMessage: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 9) {
                Label("错误详情", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .font(.subheadline)
                    .textSelection(.enabled)
                if let diagnosticSpan {
                    Text("失败于：\(TraceStyle.displayTitle(for: diagnosticSpan, ordinal: timelineOrdinal(for: diagnosticSpan)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func timelineOrdinal(for span: AgentTraceSpan) -> Int {
        timelineEntries.first(where: { $0.id == span.id })?.ordinal ?? 1
    }
}

private struct AgentTraceTimelineEntry: Identifiable {
    let span: AgentTraceSpan
    let ordinal: Int
    let traceStartedAt: Date

    var id: UUID {
        span.id
    }

    var relativeMilliseconds: Double {
        max(0, span.endedAt.timeIntervalSince(traceStartedAt) * 1000)
    }
}

private struct AgentTraceSpanRow: View {
    let entry: AgentTraceTimelineEntry
    let provider: String
    let model: String
    @State private var isExpanded: Bool

    init(entry: AgentTraceTimelineEntry, provider: String, model: String) {
        self.entry = entry
        self.provider = provider
        self.model = model
        _isExpanded = State(initialValue:
            [.failed, .cancelled].contains(entry.span.status)
                && entry.span.kind != .output)
    }

    private var span: AgentTraceSpan {
        entry.span
    }

    private var metadata: TraceSpanMetadata {
        TraceSpanMetadata(span.metadata)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(spanColor.opacity(0.12))
                        Image(systemName: TraceStyle.icon(for: span.kind))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(spanColor)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(TraceStyle.displayTitle(for: span, ordinal: entry.ordinal))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(span.status == .failed ? .red : .primary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(TraceStyle.relative(entry.relativeMilliseconds))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(primarySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                        if let secondarySummary {
                            Text(secondarySummary)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(TraceStyle.displayTitle(for: span, ordinal: entry.ordinal))，\(primarySummary)")
            .accessibilityValue(isExpanded ? "已展开" : "已收起")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    tracePayload("入参", span.input)
                    tracePayload("返回", span.output)
                    tracePayload("元数据", span.metadata)
                    if span.kind != .output {
                        tracePayload("错误", span.errorMessage, color: .red)
                    }
                }
                .padding(.leading, 42)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 10)
    }

    private var spanColor: Color {
        if [.failed, .cancelled].contains(span.status) {
            return .red
        }
        return TraceStyle.color(for: span.kind)
    }

    private var primarySummary: String {
        switch span.kind {
        case .model:
            return "\(provider)/\(model)"
        case .skill:
            if let skillID = metadata.string("skill_id") {
                return skillID
            }
            return span.status.title
        case .tool:
            return span.status == .succeeded ? "调用成功" : span.status.title
        case .output:
            return span.status.title
        }
    }

    private var secondarySummary: String? {
        var parts = [TraceStyle.duration(span.durationMilliseconds)]
        switch span.kind {
        case .model:
            if let tokenSummary = metadata.tokenSummary {
                parts.append(tokenSummary)
            }
        case .skill:
            parts.insert(span.status.title, at: 0)
        case .tool, .output:
            return parts.first
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func tracePayload(
        _ title: String,
        _ value: String?,
        color: Color = .primary
    ) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(color)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct TraceSpanMetadata {
    private let values: [String: Any]

    init(_ rawValue: String?) {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            values = [:]
            return
        }
        values = dictionary
    }

    func string(_ key: String) -> String? {
        values[key] as? String
    }

    private func integer(_ key: String) -> Int? {
        if let value = values[key] as? Int {
            return value
        }
        return (values[key] as? NSNumber)?.intValue
    }

    var tokenSummary: String? {
        guard let total = integer("total_tokens") else { return nil }
        let totalText = total.formatted(.number.grouping(.automatic))
        guard let input = integer("prompt_tokens"),
              let output = integer("completion_tokens")
        else {
            return "tokens \(totalText)"
        }
        return "\(totalText) tokens · 入 \(input.formatted()) / 出 \(output.formatted())"
    }
}
