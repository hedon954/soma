import SwiftData
import SwiftUI

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var definitions: [ExerciseDefinition]
    @State private var searchText = ""
    @State private var filter = ExerciseLibraryFilter()
    @FocusState private var searchIsFocused: Bool
    @State private var classifications: [UUID: ExerciseLibraryClassification] = [:]
    @State private var latestWorkouts: [UUID: ExerciseLibraryRecentWorkout] = [:]
    @State private var recentWorkoutRevision = 0

    init() {
        var descriptor = FetchDescriptor<ExerciseDefinition>(
            sortBy: [SortDescriptor(\.canonicalName)]
        )
        descriptor.fetchLimit = 2000
        _definitions = Query(descriptor)
    }

    var body: some View {
        let sections = visibleSections()
        VStack(spacing: 0) {
            searchBar
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ExerciseLibrarySidebar(filter: $filter, classifications: Array(classifications.values)) {
                        searchIsFocused = false
                    }
                    .frame(width: min(156, max(108, geometry.size.width * 0.28)))
                    Divider()
                    resultList(sections)
                }
            }
        }
        .appPageBackground()
        .navigationTitle("动作库")
        .onChange(of: filter) { _, _ in searchIsFocused = false }
        // 键值只用数量 + revision：目录增删改和训练保存都会经其中之一触发，
        // 不再在每次 body 求值（含每个搜索按键）时构建并哈希整表 UUID 数组。
        .task(id: ExerciseLibraryRecentWorkoutLoadRequest(
            definitionCount: definitions.count,
            revision: recentWorkoutRevision
        )) {
            classifications = Dictionary(uniqueKeysWithValues: definitions.map { definition in
                (definition.id, ExerciseLibraryClassification(
                    name: definition.canonicalName,
                    primary: definition.primaryMuscles,
                    secondary: definition.secondaryMuscles,
                    patterns: definition.movementPatterns
                ))
            })
            await loadRecentWorkouts()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: ModelContext.didSave,
                object: modelContext
            )
        ) { notification in
            guard ModelContextSaveImpact.affectsExerciseLibraryRecents(
                notification,
                in: modelContext
            ) else {
                return
            }
            recentWorkoutRevision &+= 1
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索动作名称", text: $searchText)
                .focused($searchIsFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchIsFocused = false }
                .accessibilityIdentifier("exercise-library-search")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("清除搜索")
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: 44)
        .background(AppTheme.insetBackground, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func resultList(_ sections: (active: [ExerciseDefinition], archived: [ExerciseDefinition])) -> some View {
        List {
            if definitions.isEmpty {
                ContentUnavailableView(
                    "动作库会随训练自然形成",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("在教练中描述训练后，Soma 会用稳定动作身份串联历史。")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if sections.active.isEmpty, sections.archived.isEmpty {
                ContentUnavailableView {
                    Label("没有符合条件的动作", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("试试其他关键词，或清除筛选条件。")
                } actions: {
                    Button("重置搜索与筛选") {
                        searchText = ""
                        filter = ExerciseLibraryFilter()
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section("\(selectionTitle) · \(sections.active.count)") {
                    ForEach(sections.active) { definition in
                        exerciseLink(definition)
                    }
                }
                if !sections.archived.isEmpty {
                    Section("已归档") {
                        ForEach(sections.archived) { definition in
                            exerciseLink(definition)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("exercise-library-results")
    }

    private var selectionTitle: String {
        filter.muscle ?? filter.pattern ?? filter.region?.rawValue ?? "全部动作"
    }

    private func exerciseLink(
        _ definition: ExerciseDefinition
    ) -> some View {
        NavigationLink {
            ExerciseDetailView(exercise: definition)
        } label: {
            ExerciseLibraryRow(
                definition: definition,
                latest: latestWorkouts[definition.id]
            )
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 10))
        .accessibilityIdentifier("exercise-link-\(definition.canonicalName)")
    }

    private func loadRecentWorkouts() async {
        let container = modelContext.container
        let worker = Task.detached(priority: .utility) {
            let loader = ExerciseRecentWorkoutSnapshotLoader(
                modelContainer: container
            )
            return try await loader.load()
        }
        let loaded = try? await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard let loaded, !Task.isCancelled else { return }
        latestWorkouts = loaded
    }

    private func visibleSections() -> (
        active: [ExerciseDefinition],
        archived: [ExerciseDefinition]
    ) {
        var active: [ExerciseDefinition] = []
        var archived: [ExerciseDefinition] = []
        active.reserveCapacity(definitions.count)
        archived.reserveCapacity(definitions.count / 4)
        for definition in definitions {
            if let classification = classifications[definition.id] {
                guard filter.matches(classification, search: searchText) else { continue }
            } else if filter.count > 0 || !searchText.isEmpty {
                continue
            }
            if definition.isArchived {
                archived.append(definition)
            } else {
                active.append(definition)
            }
        }
        return (active, archived)
    }
}

private struct ExerciseLibraryRow: View {
    let definition: ExerciseDefinition
    let latest: ExerciseLibraryRecentWorkout?

    var body: some View {
        HStack(spacing: 8) {
            ExerciseArtworkView(
                reference: definition.actionIllustrations.last
                    ?? BundledExerciseCatalog.fallbackActionIllustration,
                contentMode: .fill
            )
            .frame(
                width: 40,
                height: 45
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(definition.canonicalName)
                        .font(.subheadline)
                        .lineLimit(2)
                    if definition.isArchived {
                        Text("已归档")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if let latest {
                    Text("最近：\(latest.date.formatted(date: .abbreviated, time: .omitted)) · \(latest.summary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("暂无训练历史")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, AppTheme.listRowVerticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(definition.canonicalName)，\(latest?.summary ?? "暂无训练历史")"
        )
    }
}

private struct ExerciseLibraryRecentWorkoutLoadRequest: Hashable {
    let definitionCount: Int
    let revision: Int
}

// PRD 020：动作详情首屏只读——示意图、名称、教练提示（折叠）、
// 紧凑肌群图与最近训练；编辑、媒体与管理下沉到工具栏菜单的子页。
