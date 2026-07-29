import SwiftData
import SwiftUI

private struct GymPhotoItem: Identifiable {
    let id: String
    let path: String
}

struct GymLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GymProfile.createdAt) private var gyms: [GymProfile]
    @Query(sort: \GymEquipment.createdAt) private var equipment: [GymEquipment]
    @Query(sort: \GymMedia.createdAt) private var media: [GymMedia]

    var body: some View {
        List {
            if gyms.isEmpty {
                ContentUnavailableView(
                    "还没有健身房",
                    systemImage: "dumbbell",
                    description: Text("在教练对话里发送健身房照片，AI 会自动创建并识别器械。")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(gyms) { gym in
                        HStack(spacing: 10) {
                            NavigationLink {
                                GymDetailView(gym: gym)
                            } label: {
                                GymLibraryRow(
                                    gym: gym,
                                    equipmentCount: equipment.filter { $0.gymID == gym.id }.count
                                )
                            }

                            Button {
                                GymSelection.activate(gym, among: gyms)
                                try? modelContext.save()
                            } label: {
                                Image(systemName: gym.isCurrent ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(gym.isCurrent ? AppTheme.tint : Color.secondary.opacity(0.45))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(gym.isCurrent ? "当前健身房" : "设为当前健身房")
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                StructuredDataStore.deleteGym(
                                    gym,
                                    gyms: gyms,
                                    equipment: equipment,
                                    media: media,
                                    in: modelContext
                                )
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("删除健身房")
                            .tint(.red)
                        }
                    }
                } footer: {
                    Text("新建和更新都通过教练对话完成；点右侧圆圈可直接切换当前健身房。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("健身房")
    }
}

private struct GymLibraryRow: View {
    let gym: GymProfile
    let equipmentCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if gym.coverImagePath != nil {
                    LocalImageView(path: gym.coverImagePath)
                } else {
                    ZStack {
                        AppTheme.softTint
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(AppTheme.tint)
                    }
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(gym.name)
                        .font(.headline)
                    if gym.isCurrent {
                        Text("当前")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.softTint, in: Capsule())
                    }
                }
                Text("\(equipmentCount) 件器械 · \(gym.notes.isEmpty ? "等待 AI 解析" : gym.notes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct GymDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GymProfile.createdAt) private var gyms: [GymProfile]
    @Query(sort: \GymEquipment.createdAt) private var allEquipment: [GymEquipment]
    @Query(sort: \GymMedia.createdAt, order: .reverse) private var allMedia: [GymMedia]
    let gym: GymProfile
    @State private var editingGym: GymProfile?
    @State private var editingEquipment: GymEquipment?
    @State private var deletingEquipment: GymEquipment?
    @State private var confirmsGymDeletion = false

    private var equipment: [GymEquipment] {
        allEquipment.filter { $0.gymID == gym.id }
    }

    private var photos: [GymPhotoItem] {
        let recorded = allMedia
            .filter { $0.gymID == gym.id }
            .map { GymPhotoItem(id: $0.id.uuidString, path: $0.path) }
        if !recorded.isEmpty {
            return recorded
        }
        return gym.coverImagePath.map { [GymPhotoItem(id: $0, path: $0)] } ?? []
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                gymPhoto

                if !gym.notes.isEmpty {
                    AppCard {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("AI 环境解析", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(AppTheme.tint)
                            Text(gym.notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("支持的器械")
                            .font(.headline)
                        Spacer()
                        Text("\(equipment.count) 件")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if equipment.isEmpty {
                        EmptyStateCard(
                            icon: "viewfinder",
                            title: "等待识别",
                            message: "把这个健身房的器械照片发给教练，AI 解析结果会出现在这里。"
                        )
                    } else {
                        AppCard {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(equipment.enumerated()), id: \.element.id) { index, item in
                                    HStack(alignment: .top, spacing: 8) {
                                        EquipmentReviewRow(item: item)

                                        Menu {
                                            Button("编辑", systemImage: "pencil") {
                                                editingEquipment = item
                                            }
                                            Button("删除", systemImage: "trash", role: .destructive) {
                                                deletingEquipment = item
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .frame(width: 30, height: 36)
                                        }
                                        .accessibilityLabel("\(item.name)操作")
                                    }
                                    if index < equipment.count - 1 {
                                        Divider().padding(.leading, 52)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .appPageBackground()
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !gym.isCurrent {
                        Button("设为当前健身房", systemImage: "checkmark.circle") {
                            GymSelection.activate(gym, among: gyms)
                            try? modelContext.save()
                        }
                    }
                    Button("编辑健身房", systemImage: "pencil") {
                        editingGym = gym
                    }
                    Button("删除健身房", systemImage: "trash", role: .destructive) {
                        confirmsGymDeletion = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("健身房操作")
            }
        }
        .sheet(item: $editingGym) { item in
            GymProfileEditor(gym: item)
        }
        .sheet(item: $editingEquipment) { item in
            GymEquipmentEditor(item: item)
        }
        .alert("删除这个健身房？", isPresented: $confirmsGymDeletion) {
            Button("删除", role: .destructive) {
                StructuredDataStore.deleteGym(
                    gym,
                    gyms: gyms,
                    equipment: allEquipment,
                    media: allMedia,
                    in: modelContext
                )
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("健身房、AI 环境解析和器械列表会被删除，原始聊天与媒体文件仍会保留。")
        }
        .alert(
            "删除器械？",
            isPresented: Binding(
                get: { deletingEquipment != nil },
                set: {
                    if !$0 {
                        deletingEquipment = nil
                    }
                }
            ),
            presenting: deletingEquipment
        ) { item in
            Button("删除", role: .destructive) {
                modelContext.delete(item)
                try? modelContext.save()
                deletingEquipment = nil
            }
            Button("取消", role: .cancel) {
                deletingEquipment = nil
            }
        } message: { item in
            Text("“\(item.name)”会从这个健身房的支持器械中移除。")
        }
    }

    @ViewBuilder
    private var gymPhoto: some View {
        if !photos.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("上传的照片")
                            .font(.headline)
                        Spacer()
                        Text("\(photos.count) 张")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(photos) { photo in
                                ZStack {
                                    LocalImageView(path: photo.path)
                                }
                                .containerRelativeFrame(.horizontal, count: 1, spacing: 10)
                                .frame(height: 176)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                    .frame(height: 176)
                }
            }
        } else {
            EmptyStateCard(
                icon: "photo.badge.plus",
                title: "还没有健身房照片",
                message: "直接在教练对话中拍照或选择照片，AI 会自动归入当前健身房。"
            )
        }
    }
}

private struct GymProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let gym: GymProfile
    @State private var name: String
    @State private var notes: String

    init(gym: GymProfile) {
        self.gym = gym
        _name = State(initialValue: gym.name)
        _notes = State(initialValue: gym.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("健身房") {
                    TextField("名称", text: $name)
                    TextField("AI 环境解析（可空）", text: $notes, axis: .vertical)
                        .lineLimit(2 ... 8)
                }
            }
            .scrollContentBackground(.hidden)
            .appPageBackground()
            .navigationTitle("编辑健身房")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        gym.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        gym.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct GymEquipmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let item: GymEquipment
    @State private var name: String
    @State private var category: String
    @State private var capabilities: String

    init(item: GymEquipment) {
        self.item = item
        _name = State(initialValue: item.name)
        _category = State(initialValue: item.category)
        _capabilities = State(initialValue: item.capabilities)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("器械解析") {
                    TextField("名称", text: $name)
                    TextField("分类", text: $category)
                    TextField("支持动作与能力", text: $capabilities, axis: .vertical)
                        .lineLimit(2 ... 8)
                }
            }
            .scrollContentBackground(.hidden)
            .appPageBackground()
            .navigationTitle("编辑器械")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        item.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
                        item.capabilities = capabilities.trimmingCharacters(in: .whitespacesAndNewlines)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}

private struct EquipmentReviewRow: View {
    let item: GymEquipment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                AppTheme.softTint
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(AppTheme.tint)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                Text(item.category)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.tint)
                Text(item.capabilities)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
