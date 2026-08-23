import SwiftUI
import UIKit

struct TrainingPrescriptionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let exercise: ExerciseDefinition?
    let definitions: [ExerciseDefinition]
    let recent: RecentExercisePrescription?
    let onSave: (TrainingPrescriptionDraft) throws -> Void
    @State private var draft: TrainingPrescriptionDraft
    @State private var expandedClusterIDs: Set<UUID> = []
    @State private var errorMessage: String?

    init(
        initialDraft: TrainingPrescriptionDraft,
        exercise: ExerciseDefinition?,
        definitions: [ExerciseDefinition],
        recent: RecentExercisePrescription?,
        onSave: @escaping (TrainingPrescriptionDraft) throws -> Void
    ) {
        self.exercise = exercise
        self.definitions = definitions
        self.recent = recent
        self.onSave = onSave
        var draft = initialDraft
        if let exercise {
            if exercise.hasExplicitLaterality {
                draft.laterality = exercise.laterality
            }
            if exercise.hasExplicitTargetKind {
                for index in draft.plannedSets.indices {
                    draft.plannedSets[index].targetKind = exercise.targetKind
                }
            }
        }
        _draft = State(initialValue: draft)
    }

    private var selectedExercise: ExerciseDefinition? {
        definitions.first { $0.id == draft.exerciseID } ?? exercise
    }

    private var exerciseTargetKind: WorkoutTargetKind {
        selectedExercise?.targetKind
            ?? draft.plannedSets.first?.targetKind
            ?? .repetitions
    }

    var body: some View {
        Form {
            exerciseHeader
            lateralitySection
            setBlocks

            Section {
                Button {
                    appendBlankSet()
                } label: {
                    Label("新增空白组", systemImage: "plus.circle.fill")
                }
                Button {
                    copyLastSet()
                } label: {
                    Label("复制上一组", systemImage: "doc.on.doc")
                }
            } footer: {
                Text("相同组收成一句编辑。要改其中一组时再展开；保存后仍是互不绑定的独立组。")
            }
        }
        .navigationTitle("编辑动作")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        TrainingExercisePickerView(
                            definitions: definitions,
                            allowsMultipleSelection: false
                        ) { exercises in
                            guard let replacement = exercises.first else { return }
                            draft.exerciseID = replacement.id
                        }
                    } label: {
                        Label("更换动作", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多操作")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(!hasValidTargets)
            }
        }
        .alert(
            "无法保存",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var exerciseHeader: some View {
        Section {
            HStack(spacing: 14) {
                ExerciseArtworkView(
                    reference: selectedExercise?.preferredActionIllustration
                        ?? BundledExerciseCatalog.fallbackActionIllustration
                )
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedExercise?.canonicalName ?? "已归档动作")
                        .font(.title3.bold())
                    Text(headerSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var lateralitySection: some View {
        Section("动作设定") {
            Picker("完成方式", selection: targetKindBinding) {
                ForEach(WorkoutTargetKind.allCases, id: \.self) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .pickerStyle(.segmented)

            Picker("左右方式", selection: lateralityBinding) {
                ForEach(ExerciseLaterality.allCases, id: \.self) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .pickerStyle(.menu)

            Text(draft.laterality.editorExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var lateralityBinding: Binding<ExerciseLaterality> {
        Binding(
            get: { draft.laterality },
            set: { value in
                draft.laterality = value
                selectedExercise?.laterality = value
                try? modelContext.save()
            }
        )
    }

    private var targetKindBinding: Binding<WorkoutTargetKind> {
        Binding(
            get: {
                selectedExercise?.targetKind
                    ?? draft.plannedSets.first?.targetKind
                    ?? .repetitions
            },
            set: { value in
                selectedExercise?.targetKind = value
                for index in draft.plannedSets.indices {
                    draft.plannedSets[index].targetKind = value
                }
                try? modelContext.save()
            }
        )
    }

    private var setBlocks: some View {
        ForEach(visibleBlocks) { block in
            switch block {
            case let .cluster(id, start, count):
                clusterSection(id: id, start: start, count: count)
            case let .set(id):
                if let index = draft.plannedSets.firstIndex(where: { $0.id == id }) {
                    setSection(id: id, index: index)
                }
            }
        }
    }

    private var visibleBlocks: [EditorBlock] {
        TrainingPrescriptionDraftClustering.clusters(in: draft.plannedSets).flatMap { cluster in
            let id = draft.plannedSets[cluster.startIndex].id
            if cluster.count > 1, expandedClusterIDs.contains(id) {
                return draft.plannedSets[
                    cluster.startIndex ..< cluster.startIndex + cluster.count
                ].map { EditorBlock.set($0.id) }
            }
            return [EditorBlock.cluster(id: id, start: cluster.startIndex, count: cluster.count)]
        }
    }

    private func clusterSection(id: UUID, start: Int, count: Int) -> some View {
        let sample = draft.plannedSets[start]
        return Section {
            Stepper(value: clusterCount(start: start, count: count), in: 1 ... 20) {
                Text("\(count) 组")
            }
            .accessibilityLabel("\(WorkoutPrescriptionFormatter.kindTitle(sample.kind))数量")

            setFields(
                kind: clusterField(start: start, count: count, keyPath: \.kind),
                reps: clusterField(start: start, count: count, keyPath: \.reps),
                durationSeconds: clusterField(
                    start: start,
                    count: count,
                    keyPath: \.durationSeconds
                ),
                notes: clusterField(start: start, count: count, keyPath: \.notes),
                setID: id
            )

            clusterActions(id: id, start: start, count: count)
        } header: {
            Text(clusterHeader(sample.kind, count: count))
        }
    }

    private func setSection(id: UUID, index: Int) -> some View {
        Section {
            setFields(
                kind: setValue(id, \.kind),
                reps: setValue(id, \.reps),
                durationSeconds: setValue(id, \.durationSeconds),
                notes: setValue(id, \.notes),
                setID: id
            )
            setActions(setID: id, index: index)
        } header: {
            Text("第 \(draft.plannedSets[index].order) 组")
        }
    }

    @ViewBuilder
    private func setFields(
        kind: Binding<WorkoutSetKind>,
        reps: Binding<String>,
        durationSeconds: Binding<String>,
        notes: Binding<String>,
        setID: UUID
    ) -> some View {
        Picker("组类型", selection: kind) {
            Text("工作组").tag(WorkoutSetKind.working)
            Text("热身组").tag(WorkoutSetKind.warmup)
            Text("递减组").tag(WorkoutSetKind.drop)
            Text("力竭组").tag(WorkoutSetKind.failure)
            Text("自定义").tag(WorkoutSetKind.custom)
        }

        if exerciseTargetKind == .repetitions {
            metric("目标次数", text: reps, keyboard: .numberPad)
        } else {
            metric(
                "目标时长（秒）",
                text: durationSeconds,
                keyboard: .numberPad
            )
        }

        weightFields(for: setID)

        if draft.laterality == .both {
            metric(
                "左右之间间歇（秒）",
                text: field(setID, \.restBetweenSidesSeconds),
                keyboard: .numberPad,
                optional: true
            )
        }
        metric(
            "本组结束后间歇（秒）",
            text: field(setID, \.restAfterSetSeconds),
            keyboard: .numberPad,
            optional: true
        )
        TextField("本组备注（可选）", text: notes, axis: .vertical)
            .lineLimit(2 ... 5)
    }

    @ViewBuilder
    private func weightFields(for setID: UUID) -> some View {
        switch draft.laterality {
        case .none:
            metric(
                "重量（kg）",
                text: field(setID, \.weight),
                keyboard: .decimalPad,
                optional: true
            )
        case .both:
            metric(
                "左侧重量（kg）",
                text: field(setID, \.leftWeight),
                keyboard: .decimalPad,
                optional: true
            )
            metric(
                "右侧重量（kg）",
                text: field(setID, \.rightWeight),
                keyboard: .decimalPad,
                optional: true
            )
        case .left:
            metric(
                "左侧重量（kg）",
                text: field(setID, \.leftWeight),
                keyboard: .decimalPad,
                optional: true
            )
        case .right:
            metric(
                "右侧重量（kg）",
                text: field(setID, \.rightWeight),
                keyboard: .decimalPad,
                optional: true
            )
        }
    }

    private func clusterActions(id: UUID, start: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if count > 1 {
                Button("展开各组") {
                    expandedClusterIDs.insert(id)
                }
                .accessibilityHint("分别编辑这一批里的某一组")
            }

            HStack {
                Button {
                    draft.plannedSets = TrainingPrescriptionDraftClustering.moveCluster(
                        draft.plannedSets,
                        startIndex: start,
                        count: count,
                        direction: -1
                    )
                } label: {
                    Label("上移", systemImage: "arrow.up")
                }
                .disabled(start == 0)

                Spacer()

                Button(role: .destructive) {
                    draft.plannedSets = TrainingPrescriptionDraftClustering.removeCluster(
                        draft.plannedSets,
                        startIndex: start,
                        count: count
                    )
                    expandedClusterIDs.remove(id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(draft.plannedSets.count <= count)

                Spacer()

                Button {
                    draft.plannedSets = TrainingPrescriptionDraftClustering.moveCluster(
                        draft.plannedSets,
                        startIndex: start,
                        count: count,
                        direction: 1
                    )
                } label: {
                    Label("下移", systemImage: "arrow.down")
                }
                .disabled(start + count >= draft.plannedSets.count)
            }
            .font(.subheadline)
        }
    }

    private func setActions(setID: UUID, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let cluster = enclosingCluster(for: index), cluster.count > 1 {
                Button("收起相同组") {
                    expandedClusterIDs.remove(draft.plannedSets[cluster.startIndex].id)
                }
            }

            HStack {
                Button {
                    move(setID: setID, offset: -1)
                } label: {
                    Label("上移", systemImage: "arrow.up")
                }
                .disabled(index == 0)

                Spacer()

                Button(role: .destructive) {
                    removeSet(id: setID)
                } label: {
                    Label("删除本组", systemImage: "trash")
                }
                .disabled(draft.plannedSets.count == 1)

                Spacer()

                Button {
                    move(setID: setID, offset: 1)
                } label: {
                    Label("下移", systemImage: "arrow.down")
                }
                .disabled(index >= draft.plannedSets.count - 1)
            }
            .font(.subheadline)
        }
    }

    private func metric(
        _ label: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        optional: Bool = false
    ) -> some View {
        LabeledContent(label) {
            TextField(optional ? "可选" : "必填", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 88)
                .accessibilityLabel(label)
        }
    }

    private var headerSummary: String {
        WorkoutPrescriptionFormatter.exerciseSummary(
            draft.prescription(
                order: 1,
                names: [draft.exerciseID: selectedExercise?.canonicalName ?? ""]
            ),
            includesLaterality: false
        )
    }

    private var hasValidTargets: Bool {
        !draft.plannedSets.isEmpty && draft.plannedSets.allSatisfy { set in
            switch set.targetKind {
            case .repetitions:
                (Int(set.reps) ?? 0) > 0
            case .duration:
                (Int(set.durationSeconds) ?? 0) > 0
            }
        }
    }

    private func clusterHeader(_ kind: WorkoutSetKind, count: Int) -> String {
        let title = WorkoutPrescriptionFormatter.kindTitle(kind)
        return count == 1 ? title : "\(title) · \(count) 组相同"
    }

    private func clusterCount(start: Int, count: Int) -> Binding<Int> {
        Binding(
            get: { count },
            set: { newCount in
                draft.plannedSets = TrainingPrescriptionDraftClustering.resize(
                    draft.plannedSets,
                    startIndex: start,
                    count: count,
                    newCount: newCount
                )
            }
        )
    }

    private func clusterField<Value>(
        start: Int,
        count: Int,
        keyPath: WritableKeyPath<TrainingSetPrescriptionDraft, Value>
    ) -> Binding<Value> {
        Binding(
            get: { draft.plannedSets[start][keyPath: keyPath] },
            set: { value in
                for index in start ..< start + count
                    where draft.plannedSets.indices.contains(index)
                {
                    draft.plannedSets[index][keyPath: keyPath] = value
                }
            }
        )
    }

    private func field(
        _ setID: UUID,
        _ keyPath: WritableKeyPath<TrainingSetPrescriptionDraft, String>
    ) -> Binding<String> {
        clusterAwareValue(setID, keyPath)
    }

    private func setValue<Value>(
        _ setID: UUID,
        _ keyPath: WritableKeyPath<TrainingSetPrescriptionDraft, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                draft.plannedSets.first { $0.id == setID }![keyPath: keyPath]
            },
            set: { value in
                guard let index = draft.plannedSets.firstIndex(where: { $0.id == setID })
                else {
                    return
                }
                draft.plannedSets[index][keyPath: keyPath] = value
            }
        )
    }

    private func clusterAwareValue(
        _ setID: UUID,
        _ keyPath: WritableKeyPath<TrainingSetPrescriptionDraft, String>
    ) -> Binding<String> {
        Binding(
            get: {
                draft.plannedSets.first { $0.id == setID }?[keyPath: keyPath] ?? ""
            },
            set: { value in
                guard let index = draft.plannedSets.firstIndex(where: { $0.id == setID })
                else {
                    return
                }
                let cluster = TrainingPrescriptionDraftClustering.clusters(
                    in: draft.plannedSets
                ).first {
                    (index >= $0.startIndex) && (index < $0.startIndex + $0.count)
                }
                let expanded = cluster.map {
                    expandedClusterIDs.contains(draft.plannedSets[$0.startIndex].id)
                } ?? true
                if let cluster, cluster.count > 1, !expanded {
                    for item in cluster.startIndex ..< cluster.startIndex + cluster.count {
                        draft.plannedSets[item][keyPath: keyPath] = value
                    }
                } else {
                    draft.plannedSets[index][keyPath: keyPath] = value
                }
            }
        )
    }

    private func enclosingCluster(for index: Int) -> TrainingPrescriptionCluster? {
        TrainingPrescriptionDraftClustering.clusters(in: draft.plannedSets).first {
            index >= $0.startIndex && index < $0.startIndex + $0.count
        }
    }

    private func appendBlankSet() {
        draft.plannedSets.append(TrainingSetPrescriptionDraft(
            order: draft.plannedSets.count + 1,
            targetKind: exerciseTargetKind
        ))
    }

    private func copyLastSet() {
        var next = draft.plannedSets.last
            ?? TrainingSetPrescriptionDraft(order: 1)
        next.id = UUID()
        next.order = draft.plannedSets.count + 1
        draft.plannedSets.append(next)
    }

    private func removeSet(id: UUID) {
        guard draft.plannedSets.count > 1 else { return }
        draft.plannedSets.removeAll { $0.id == id }
        normalizeOrder()
    }

    private func move(setID: UUID, offset: Int) {
        guard let source = draft.plannedSets.firstIndex(where: { $0.id == setID }) else {
            return
        }
        let destination = source + offset
        guard draft.plannedSets.indices.contains(destination) else { return }
        draft.plannedSets.swapAt(source, destination)
        normalizeOrder()
    }

    private func normalizeOrder() {
        for index in draft.plannedSets.indices {
            draft.plannedSets[index].order = index + 1
        }
    }

    private func save() {
        normalizeOrder()
        do {
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum EditorBlock: Identifiable {
    case cluster(id: UUID, start: Int, count: Int)
    case set(UUID)

    var id: UUID {
        switch self {
        case let .cluster(id, _, _): id
        case let .set(id): id
        }
    }
}

private extension ExerciseLaterality {
    var editorExplanation: String {
        switch self {
        case .none:
            "全身完成一次目标，不拆成左右两侧。"
        case .both:
            "同一组先做左侧再做右侧，可分别记录重量。"
        case .left:
            "每组只做并记录左边。"
        case .right:
            "每组只做并记录右边。"
        }
    }
}
