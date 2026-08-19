import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AIService.self) private var ai
    @AppStorage(ConversationLocationPreference.defaultsKey)
    private var locationPreferenceRaw = ConversationLocationPreference.unasked.rawValue
    @AppStorage("workout.voiceCuesEnabled")
    private var voiceCuesEnabled = true
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
    @State private var didLoadConfiguration = false
    @FocusState private var modelFieldFocused: Bool
    @State private var path: [SettingsRoute]
    private let showsAIConfigurationReminder: Bool
    private let isEmbeddedInTab: Bool

    init(
        initialRoute: SettingsRoute? = nil,
        showsAIConfigurationReminder: Bool = false,
        isEmbeddedInTab: Bool = false
    ) {
        _path = State(initialValue: initialRoute.map { [$0] } ?? [])
        self.showsAIConfigurationReminder = showsAIConfigurationReminder
        self.isEmbeddedInTab = isEmbeddedInTab
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
                feedbackSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isEmbeddedInTab {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            persistConfiguration()
                            dismiss()
                        }
                    }
                }
            }
            .onChange(of: smallModelEnabled) {
                ai.setTierEnabled(smallModelEnabled, tier: .small)
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .llm:
                    Form {
                        if showsAIConfigurationReminder {
                            AIConfigurationReminder()
                        }
                        llmSections
                    }
                    .navigationTitle("LLM 配置")
                    .navigationBarTitleDisplayMode(.inline)
                    .onDisappear {
                        ai.notifyConfigurationChanged()
                    }
                }
            }
            .task(id: "\(modelTier.rawValue).\(provider.rawValue)") {
                guard !apiKey.isEmpty else { return }
                await refreshModels()
            }
        }
        // 初始路由直接进入 LLM 子页时，根 Form 不会出现；加载必须挂在容器上。
        .onAppear(perform: loadInitialConfiguration)
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

            // PRD 020：带练语音提示从每次开练的准备页移到设置。
            Toggle(isOn: $voiceCuesEnabled) {
                Label("带练语音提示", systemImage: "speaker.wave.2")
            }
        }
    }

    private var serviceSection: some View {
        Section("服务") {
            NavigationLink(value: SettingsRoute.llm) {
                SettingsSummaryRow(
                    icon: "sparkles",
                    title: "LLM 配置",
                    detail: ai.hasRequiredAPIKey
                        ? "\(ai.provider.displayName) · \(ai.model(for: ai.provider).isEmpty ? "未填写模型" : ai.model(for: ai.provider))"
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
        }
    }

    /// PRD 020：任务进度与后台处理是低频配置，下沉到「更多」。
    private var privacyAndAdvancedSection: some View {
        Section("更多") {
            NavigationLink {
                DataManagementView()
            } label: {
                Label("数据与备份", systemImage: "externaldrive")
            }

            NavigationLink {
                AgentSystemSettingsView()
            } label: {
                Label("任务进度与通知", systemImage: "waveform.path.ecg")
            }

            NavigationLink {
                RemoteAgentSettingsView()
            } label: {
                Label("后台持续处理", systemImage: "server.rack")
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

    private var feedbackSection: some View {
        Section("反馈") {
            FeedbackView(isEmbedded: true)
                .listRowInsets(
                    EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
                )
                .listRowBackground(Color.clear)
        }
    }

    /// PRD 020：隐私页只保留可操作的位置开关，静态说明压缩为一句 footer。
    private var privacySection: some View {
        Section {
            Toggle(isOn: locationEnabledBinding) {
                Label("随消息记录位置", systemImage: "location")
            }
        } header: {
            Text("隐私")
        } footer: {
            Text("开启后仅在发送时获取一次位置并保存在本机；天气或户外消息会向 Open-Meteo 发送约 1 公里精度的位置。Soma 无账户，数据与 API Key 只保存在本机。")
        }
    }

    /// ADR 0046：配置页不折叠配置本身。两档在顶部分段切换，
    /// 平台、Base URL、API Key 与模型同屏可见可改，改动即时落盘。
    @ViewBuilder
    private var llmSections: some View {
        Section {
            Picker("模型档位", selection: modelTierBinding) {
                ForEach(AIModelTier.allCases) { tier in
                    Text(tier.title).tag(tier)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } footer: {
            Text(
                modelTier == .standard
                    ? "标准模型负责所有含媒体、含业务写入和复杂纠错的任务，是聊天的能力下限。"
                    : "小模型可不配置。配置并启用后，Agent 只把短文本、无媒体且无业务写入意图的简单任务交给它。"
            )
        }

        Section {
            Picker("平台", selection: providerBinding) {
                ForEach(AIProvider.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            TextField("Base URL", text: $baseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .onChange(of: baseURL) { persistConfiguration() }

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
                .buttonStyle(.borderless)
                .accessibilityLabel(showKey ? "隐藏 API Key" : "显示 API Key")
            }

            Button {
                saveKeyAndRefresh()
            } label: {
                if isLoadingModels {
                    HStack {
                        ProgressView()
                        Text("正在获取模型…")
                    }
                } else {
                    Text(keySaved ? "保存并重新获取模型" : "保存并获取模型")
                }
            }
            .disabled(
                apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isLoadingModels
            )
        } header: {
            Text("平台与凭据")
        } footer: {
            Text("Base URL 会按所选平台预填，可以改成自建或代理地址。API Key 只保存在本机 Keychain。")
        }

        modelSection

        if modelTier == .standard {
            Section {
                TextField("例如 gpt-image-2", text: $imageModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: imageModel) { persistConfiguration() }
            } header: {
                Text("图片生成模型")
            } footer: {
                Text("留空表示不启用。动作图片只在动作详情主动点击生成时请求。")
            }
        } else {
            Section {
                Toggle("启用小模型", isOn: $smallModelEnabled)
            } footer: {
                Text("关闭时所有任务都走标准模型，这里的配置会被保留。")
            }
        }
    }

    /// ADR 0046：模型是纯输入框，`/models` 结果只作为输入历史式建议。
    private var modelSection: some View {
        Section {
            TextField("输入模型 ID", text: $model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($modelFieldFocused)
                .onChange(of: model) { persistConfiguration() }

            if showsModelSuggestions {
                InputSuggestionList(
                    items: modelSuggestions,
                    selectionHint: "填入模型输入框",
                    scrollAfter: 5
                ) { item in
                    model = item.id
                    modelFieldFocused = false
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if isLoadingModels {
                LabeledContent("可用模型") {
                    ProgressView().controlSize(.small)
                }
            }

            if !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                capabilityRow
            }

            if let modelError {
                Label(modelError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.warning)
            }
        } header: {
            Text("模型")
        } footer: {
            Text(modelFooterText)
        }
    }

    private var modelFooterText: String {
        if models.isEmpty {
            return "可以直接输入平台的模型 ID。保存 API Key 后 Soma 会尝试拉取 /models，成功时在输入框下方给出候选。"
        }
        return "点选候选或直接输入都可以，输入的值会立即保存，重新拉取候选不会覆盖它。"
    }

    private var showsModelSuggestions: Bool {
        modelFieldFocused && !modelSuggestions.isEmpty
    }

    /// 候选行只给模型 ID：能力标注在选定之后由下方那一行说明，不在每行重复。
    private var modelSuggestions: [InputSuggestionItem] {
        let query = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = query.isEmpty
            ? models
            : models.filter { $0.id.localizedCaseInsensitiveContains(query) }
        if matched.count == 1, matched[0].id == query {
            return []
        }
        return matched.map { option in
            InputSuggestionItem(id: option.id, title: option.id, icon: "cpu")
        }
    }

    /// 只在已经填好模型时出现，并且只占一行：能力标注本身已经说清了后果。
    private var capabilityRow: some View {
        HStack(spacing: 8) {
            Image(systemName: capabilityIcon)
                .foregroundStyle(capabilityColor)
            Text(selectedCapability.label)
                .font(.footnote)
                .foregroundStyle(
                    selectedCapability == .unsupported
                        ? AppTheme.warning
                        : .secondary
                )
        }
        .accessibilityElement(children: .combine)
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

    /// 只在首次出现时载入。返回上一层会再次触发 `onAppear`，重新载入会覆盖
    /// 子页刚改过的值——这正是「选了模型但没保存」缺陷的成因（ADR 0046）。
    private func loadInitialConfiguration() {
        locationPreferenceRaw = ConversationLocationPreference.current().rawValue
        guard !didLoadConfiguration else { return }
        didLoadConfiguration = true
        smallModelEnabled = ai.isTierEnabled(.small)
        loadTierConfiguration(.standard)
    }

    private var modelTierBinding: Binding<AIModelTier> {
        Binding(
            get: { modelTier },
            set: { newTier in
                guard newTier != modelTier else { return }
                modelFieldFocused = false
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
                modelFieldFocused = false
                provider = newProvider
                loadProviderConfiguration()
            }
        )
    }

    private func loadTierConfiguration(_ tier: AIModelTier) {
        applyConfigurationDraft(
            SettingsLLMConfigurationDraft.load(from: ai, tier: tier)
        )
    }

    private func loadProviderConfiguration() {
        applyConfigurationDraft(
            SettingsLLMConfigurationDraft.load(
                from: ai,
                tier: modelTier,
                provider: provider
            )
        )
    }

    private func applyConfigurationDraft(_ draft: SettingsLLMConfigurationDraft) {
        provider = draft.provider
        baseURL = draft.baseURL
        model = draft.model
        imageModel = draft.imageModel
        apiKey = draft.apiKey
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
            // ADR 0046：刷新候选不覆盖已填写的模型，只在为空时补一个默认值。
            guard model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let suggested = fetched.first(where: {
                      $0.multimodalSupport == .supported
                  }) ?? fetched.first
            else {
                return
            }
            model = suggested.id
            persistConfiguration()
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
    @State private var otherDevicesExpanded = false

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

            // PRD 020：Keep/COROS 没有直连路径，说明折叠为「其他设备」。
            Section {
                DisclosureGroup("Keep 与 COROS", isExpanded: $otherDevicesExpanded) {
                    LabeledContent("Keep 直接接入", value: "暂不可用")
                    Text("Keep 暂无面向个人开发者的官方运动数据 API。若 Keep 已把数据写入 Apple 健康，可通过上方路径读取。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    LabeledContent("COROS 推荐方式", value: "经 Apple 健康")
                    Text("COROS 支持把部分数据同步到 Apple 健康；更完整的云端直连需要开发者申请 OAuth API 凭据。")
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
                }
            } header: {
                Text("其他设备")
            } footer: {
                Text("Keep 与 COROS 数据统一经 Apple 健康路径读取。")
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

struct PersonalBodyInfoView: View {
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
    @State private var moreBasicsExpanded = false
    @State private var contextExpanded = false

    private var profile: UserProfile? {
        loadedProfileID.flatMap { id in profiles.first(where: { $0.id == id }) }
            ?? profiles.first
    }

    private var postureEntries: [BodyEntry] {
        bodyEntries.filter { $0.imagePath != nil }
    }

    var body: some View {
        Form {
            // PRD 020：默认只展示性别/身高/参考体重三个核心字段，其余折叠。
            Section {
                Picker("生理性别", selection: $biologicalSex) {
                    ForEach(BiologicalSex.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
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

                DisclosureGroup("更多（可选）", isExpanded: $moreBasicsExpanded) {
                    ProfileFieldRow(title: "称呼", placeholder: "可选", text: $displayName)
                    Toggle("填写出生日期", isOn: $hasBirthDate)
                    if hasBirthDate {
                        DatePicker(
                            "出生日期",
                            selection: $birthDate,
                            in: earliestBirthDate ... Date.now,
                            displayedComponents: .date
                        )
                    }
                }
            } header: {
                Text("基本信息")
            } footer: {
                Text("参考体重用于本地热量估算（MET × 体重 × 时长），优先使用最近一次体重记录。所有字段均可留空。")
            }

            Section {
                DisclosureGroup("训练上下文", isExpanded: $contextExpanded) {
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
                }
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
        moreBasicsExpanded = !profile.displayName.isEmpty || hasBirthDate
        contextExpanded = !profile.fitnessGoal.isEmpty || !profile.healthNotes.isEmpty
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
    @State private var customizedSkillCount = 0
    @State private var confirmsResetAllPrompts = false

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

            ReActLoopSettingsSection()

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
                NavigationLink {
                    FixedAgentContractView()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(ReActPromptSection.policy.title)
                                .font(.headline)
                            Spacer()
                            Text("只读")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(ReActPromptSection.policy.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("系统提示词")
            } footer: {
                Text("只允许编辑教练人格；安全、真实性和授权契约始终由 App 固定。")
            }

            Section {
                Button("全部恢复默认提示词", systemImage: "arrow.counterclockwise", role: .destructive) {
                    confirmsResetAllPrompts = true
                }
            }

            // PRD 020：Skill 列表收进二级页，这里只保留入口与自定义摘要。
            Section {
                NavigationLink {
                    AgentSkillsListView()
                } label: {
                    HStack {
                        Label("Skills", systemImage: "text.book.closed")
                        Spacer()
                        Text(customizedSkillCount > 0 ? "\(customizedSkillCount) 项自定义" : "默认")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("可编辑内置 Skill、创建本地 Skill，并绑定 App 白名单内的最小工具权限。")
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
        .navigationTitle("高级设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            customizedSections = Set(ReActPromptSection.userEditableCases.filter { $0.isCustomized() })
            customizedSkillCount = AgentSkill.allCases.count { $0.isCustomized() }
        }
        .alert("恢复全部默认提示词？", isPresented: $confirmsResetAllPrompts) {
            Button("恢复默认", role: .destructive) {
                ReActPromptSection.allCases.forEach { $0.reset() }
                customizedSections = []
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你保存的教练人格自定义内容会被移除；固定契约不会改变。")
        }
    }
}

struct AgentSkillEditor: View {
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

struct AgentCustomSkillEditor: View {
    @Environment(\.dismiss) private var dismiss
    let originalID: String
    @State private var name: String
    @State private var description: String
    @State private var whenToUse: String
    @State private var content: String
    @State private var selectedGroups: Set<AgentToolGroup>
    @State private var showInQuickBar: Bool
    @State private var mode: MarkdownEditorMode = .edit

    init(skill: AgentCustomSkill) {
        originalID = skill.id
        _name = State(initialValue: skill.name)
        _description = State(initialValue: skill.description)
        _whenToUse = State(initialValue: skill.whenToUse)
        _content = State(initialValue: skill.content)
        _selectedGroups = State(initialValue: Set(
            skill.toolGroupIDs.compactMap(AgentToolGroup.init(rawValue:))
        ))
        _showInQuickBar = State(initialValue:
            AgentSkillRegistry.quickSkillIDs().contains(skill.id))
    }

    var body: some View {
        Form {
            Section("目录元数据") {
                TextField("名称", text: $name)
                TextField("描述", text: $description, axis: .vertical)
                TextField("什么时候使用", text: $whenToUse, axis: .vertical)
                LabeledContent("Skill ID", value: originalID)
            }

            Section {
                Picker("显示方式", selection: $mode) {
                    ForEach(MarkdownEditorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if mode == .edit {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 260)
                } else {
                    MarkdownText(content)
                        .frame(minHeight: 260, alignment: .topLeading)
                }
            } header: {
                Text("Markdown 内容")
            }

            Section {
                ForEach(allowedGroups, id: \.rawValue) { group in
                    Toggle(groupTitle(group), isOn: groupBinding(group))
                }
            } header: {
                Text("工具权限")
            } footer: {
                Text("只会暴露选中的最小工具组；权限边界由 App 固定。")
            }

            Section {
                Toggle("显示在输入框快捷栏", isOn: $showInQuickBar)
            } footer: {
                Text("快捷栏最多 6 项；加入时会替换当前最后一项。")
            }
        }
        .navigationTitle("自定义 Skill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(!isValid)
            }
        }
    }

    private var allowedGroups: [AgentToolGroup] {
        AgentToolGroup.allCases.filter {
            AgentSkillRegistry.allowedCustomToolGroups.contains($0)
        }
    }

    private var isValid: Bool {
        [name, description, whenToUse, content].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func groupBinding(_ group: AgentToolGroup) -> Binding<Bool> {
        Binding(
            get: { selectedGroups.contains(group) },
            set: { selected in
                if selected {
                    selectedGroups.insert(group)
                } else {
                    selectedGroups.remove(group)
                }
            }
        )
    }

    private func groupTitle(_ group: AgentToolGroup) -> String {
        switch group {
        case .exercises: "动作库"
        case .workouts: "训练记录"
        case .meals: "饮食记录"
        case .body: "体重与体态"
        case .plans: "训练计划与带练"
        case .gym: "健身房"
        case .review: "动作复盘"
        case .core, .feedback: group.rawValue
        }
    }

    private func save() {
        AgentSkillRegistry.save(AgentCustomSkill(
            id: originalID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            whenToUse: whenToUse.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            toolGroupIDs: selectedGroups.map(\.rawValue).sorted()
        ))
        var quick = AgentSkillRegistry.quickSkillIDs().filter { $0 != originalID }
        if showInQuickBar {
            if quick.count >= 6 {
                quick.removeLast()
            }
            quick.append(originalID)
        }
        AgentSkillRegistry.setQuickSkillIDs(quick)
        dismiss()
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
            if let latencySummary = metadata.latencySummary {
                parts.append(latencySummary)
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
