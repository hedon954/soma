import SwiftData
import SwiftUI

struct MediaThumbnail: View {
    let kind: MediaKind
    let path: String?
    var fallbackIcon: String
    var width: CGFloat = 58
    var height: CGFloat = 58

    var body: some View {
        Group {
            switch kind {
            case .image:
                LocalImageView(path: path)
            case .video:
                VideoPosterView(path: path)
            case .none:
                ZStack {
                    AppTheme.softTint
                    Image(systemName: fallbackIcon)
                        .foregroundStyle(AppTheme.tint)
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct RecordImage: View {
    let path: String

    var body: some View {
        LocalImageView(path: path)
            .frame(maxWidth: .infinity)
            .frame(height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RecordVideoPreview: View {
    let path: String

    var body: some View {
        VideoPosterView(path: path, badgeFont: .largeTitle)
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 270)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RecordMediaGallery: View {
    let attachments: [MediaAttachmentReference]
    let onDelete: (MediaAttachmentReference) -> Void
    @Namespace private var mediaZoomNamespace
    @State private var selectedAttachmentID = ""
    @State private var presentedAttachment: MediaAttachmentReference?

    var body: some View {
        TabView(selection: $selectedAttachmentID) {
            ForEach(attachments) { attachment in
                Button {
                    presentedAttachment = attachment
                } label: {
                    Group {
                        switch attachment.kind {
                        case .image:
                            RecordImage(path: attachment.path)
                        case .video:
                            RecordVideoPreview(path: attachment.path)
                        case .none:
                            EmptyView()
                        }
                    }
                }
                .buttonStyle(.plain)
                .mediaZoomSource(id: attachment.id, in: mediaZoomNamespace)
                .accessibilityLabel(
                    attachment.kind == .video
                        ? "放大查看这个视频"
                        : "放大查看这张照片"
                )
                .overlay(alignment: .bottomTrailing) {
                    if attachments.count > 1 {
                        Text("\(position(of: attachment) + 1)/\(attachments.count)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(9)
                    }
                }
                .tag(attachment.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: attachments.count > 1 ? .automatic : .never))
        .frame(height: 270)
        .mediaViewerCover(
            item: $presentedAttachment,
            attachments: attachments,
            namespace: mediaZoomNamespace,
            deletionTitle: "从记录中移除此媒体？",
            deletionMessage: "只会从这条记录解除关联；聊天中的原始附件和系统相册不会删除。",
            onDelete: onDelete
        )
        .onAppear {
            normalizeSelection()
        }
        .onChange(of: attachments) {
            normalizeSelection()
        }
    }

    private func position(of attachment: MediaAttachmentReference) -> Int {
        attachments.firstIndex(where: { $0.id == attachment.id }) ?? 0
    }

    private func normalizeSelection() {
        guard !attachments.contains(where: { $0.id == selectedAttachmentID }) else {
            return
        }
        selectedAttachmentID = attachments.first?.id ?? ""
    }
}

struct WorkoutRecordDetailView: View {
    let workout: WorkoutEntry

    var body: some View {
        WorkoutRecordEditor(workout: workout)
    }
}

struct MealRecordDetailView: View {
    let meal: MealEntry

    var body: some View {
        MealRecordEditor(meal: meal)
    }
}

struct BodyRecordDetailView: View {
    let entry: BodyEntry

    var body: some View {
        BodyRecordEditor(entry: entry)
    }
}

private struct WorkoutRecordEditor: View {
    private struct EditableSet: Identifiable, Equatable {
        let id = UUID()
        var logicalSetIndex: String
        var side: WorkoutEffortSide?
        var kind: WorkoutSetKind?
        var targetKind: WorkoutTargetKind
        var reps: String
        var durationSeconds: String
        var weight: String
        var restSeconds: String
        var recordedVideoPath: String?

        init(_ evidence: WorkoutSetEvidence) {
            logicalSetIndex = EditorValue.string(evidence.logicalSetIndex)
            side = evidence.side
            kind = evidence.kind
            targetKind = evidence.targetKind
                ?? (evidence.durationSeconds == nil ? .repetitions : .duration)
            reps = EditorValue.string(evidence.reps)
            durationSeconds = EditorValue.string(evidence.durationSeconds)
            weight = EditorValue.string(evidence.externalWeightKG)
            restSeconds = EditorValue.string(evidence.restSeconds)
            recordedVideoPath = evidence.recordedVideoPath
        }

        var evidence: WorkoutSetEvidence {
            WorkoutSetEvidence(
                logicalSetIndex: EditorValue.int(logicalSetIndex),
                side: side,
                kind: kind,
                targetKind: targetKind,
                reps: targetKind == .repetitions
                    ? EditorValue.int(reps)
                    : nil,
                durationSeconds: EditorValue.int(durationSeconds),
                externalWeightKG: EditorValue.double(weight),
                restSeconds: EditorValue.int(restSeconds),
                recordedVideoPath: recordedVideoPath
            )
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseDefinition.canonicalName)
    private var definitions: [ExerciseDefinition]
    let workout: WorkoutEntry

    @State private var date: Date
    @State private var exercise: String
    @State private var setRows: [EditableSet]
    @State private var restSeconds: String
    @State private var durationMinutes: String
    @State private var estimatedCalories: String
    @State private var calorieMET: String
    @State private var calorieDurationMinutes: String
    @State private var calorieDurationEstimated: Bool
    @State private var formScore: String
    @State private var intensity: String
    @State private var feedback: String
    @State private var notes: String
    @State private var muscleMapExpanded = false
    @State private var caloriesExpanded = false
    @State private var analysisExpanded = false
    @State private var notesExpanded = false
    init(workout: WorkoutEntry) {
        self.workout = workout
        _date = State(initialValue: workout.date)
        _exercise = State(initialValue: workout.exercise)
        _setRows = State(initialValue: workout.setEntries.map(EditableSet.init))
        _restSeconds = State(initialValue: EditorValue.string(workout.restSeconds))
        _durationMinutes = State(initialValue: EditorValue.string(workout.durationMinutes))
        _estimatedCalories = State(initialValue: EditorValue.string(workout.estimatedCalories))
        _calorieMET = State(initialValue: EditorValue.string(workout.calorieMET))
        _calorieDurationMinutes = State(initialValue: EditorValue.string(workout.calorieDurationMinutes))
        _calorieDurationEstimated = State(initialValue: workout.calorieDurationEstimated)
        _formScore = State(initialValue: EditorValue.string(workout.formScore))
        _intensity = State(initialValue: workout.intensity ?? "")
        _feedback = State(initialValue: workout.feedback ?? "")
        _notes = State(initialValue: workout.notes)
    }

    private var linkedExercise: ExerciseDefinition? {
        if let exerciseID = workout.exerciseID {
            return definitions.first { $0.id == exerciseID }
        }
        let key = ExerciseLibraryStore.canonicalNameKey(exercise)
        return definitions.first {
            !$0.isArchived && $0.canonicalNameKey == key
        }
    }

    private var hasCalorieReferenceWeight: Bool {
        WorkoutCalorieCalculator.referenceWeight(
            at: date,
            in: modelContext
        ) != nil
    }

    var body: some View {
        Form {
            if !workout.mediaAttachments.isEmpty {
                Section("记录媒体") {
                    RecordMediaGallery(
                        attachments: workout.mediaAttachments,
                        onDelete: {
                            MediaAssociationStore.detach(
                                $0,
                                from: workout,
                                in: modelContext
                            )
                        }
                    )
                }
            }

            if let linkedExercise {
                Section("关联动作") {
                    NavigationLink {
                        ExerciseDetailView(exercise: linkedExercise)
                    } label: {
                        HStack(spacing: 12) {
                            ExerciseArtworkView(
                                reference: linkedExercise.preferredActionIllustration,
                                contentMode: .fill
                            )
                            .frame(width: 64, height: 64)
                            .clipShape(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(linkedExercise.canonicalName)
                                    .font(.headline)
                                if !linkedExercise.primaryMuscles.isEmpty {
                                    Text(
                                        "主要："
                                            + linkedExercise.primaryMuscles
                                            .joined(separator: "、")
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                }
                                if !linkedExercise.coachingNotes.isEmpty {
                                    Text(linkedExercise.coachingNotes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .accessibilityLabel("查看动作 \(linkedExercise.canonicalName)")

                    // PRD 020：受力图默认收起，展开后仍可点击放大。
                    DisclosureGroup("受力图", isExpanded: $muscleMapExpanded) {
                        MuscleMapView(
                            intensities: MuscleMapView.intensities(for: linkedExercise),
                            height: 180,
                            allowsExpansion: true
                        )
                        Text("肌群图来自动作库元数据，不是本次记录的个人测量。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("基本信息") {
                RecordFieldRow(
                    title: "动作",
                    placeholder: "动作名称",
                    text: $exercise
                )
                DatePicker("时间", selection: $date)
            }

            Section {
                ForEach(setRows.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(
                                ExerciseLoggingProfile.setTitle(
                                    displayIndex: index + 1,
                                    logicalSetIndex: EditorValue.int(
                                        setRows[index].logicalSetIndex
                                    ),
                                    side: setRows[index].side
                                )
                            )
                            .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button(role: .destructive) {
                                setRows.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("删除第 \(index + 1) 组")
                        }

                        HStack(alignment: .top, spacing: 12) {
                            if setTargetKind(at: index) == .duration {
                                evidenceField(
                                    "时长",
                                    text: $setRows[index].durationSeconds,
                                    unit: "秒",
                                    keyboard: .numberPad
                                )
                            } else {
                                evidenceField(
                                    "次数",
                                    text: $setRows[index].reps,
                                    unit: "次",
                                    keyboard: .numberPad
                                )
                            }
                            evidenceField(
                                "重量",
                                text: $setRows[index].weight,
                                unit: "kg",
                                keyboard: .decimalPad
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    guard setRows.count < 100 else { return }
                    let targetKind = setTargetKind(at: setRows.count - 1)
                    setRows.append(EditableSet(WorkoutSetEvidence(
                        logicalSetIndex: ExerciseLoggingProfile.nextLogicalSetIndex(
                            existing: setRows.map {
                                EditorValue.int($0.logicalSetIndex)
                            }
                        ),
                        targetKind: targetKind
                    )))
                } label: {
                    Label("添加一组", systemImage: "plus.circle")
                }
                numericField("间歇", unit: "秒", text: $restSeconds, keyboard: .numberPad)
                numericField("训练时长", unit: "分钟", text: $durationMinutes, keyboard: .numberPad)
            } header: {
                Text("训练数据")
            } footer: {
                Text("次数、时长和重量留空代表没有数据。完成方式和左右方式在动作中统一设置。")
            }

            // PRD 020：热量估算、AI 解析与原始记录默认折叠，展开后仍可完整编辑。
            Section {
                DisclosureGroup(isExpanded: $caloriesExpanded) {
                    numericField("预计消耗", unit: "kcal", text: $estimatedCalories, keyboard: .numberPad)
                    numericField("MET", text: $calorieMET, keyboard: .decimalPad)
                    numericField("计算时长", unit: "分钟", text: $calorieDurationMinutes, keyboard: .decimalPad)
                    Toggle("计算时长来自推算", isOn: $calorieDurationEstimated)

                    if !hasCalorieReferenceWeight {
                        NavigationLink {
                            PersonalBodyInfoView()
                        } label: {
                            Label(
                                "补充体重以估算训练消耗",
                                systemImage: "flame"
                            )
                            .foregroundStyle(.orange)
                        }
                        .accessibilityHint("已有训练事实不会被改写")
                    }
                } label: {
                    LabeledContent(
                        "热量估算",
                        value: EditorValue.int(estimatedCalories).map { "约 \($0) kcal" } ?? "未记录"
                    )
                }
            } footer: {
                if caloriesExpanded {
                    Text("MET × 参考体重 × 计算时长。推算时长只用于热量估算，不会填入上方的实际训练时长。")
                }
            }

            Section {
                DisclosureGroup("AI 解析", isExpanded: $analysisExpanded) {
                    numericField("动作评分", text: $formScore, keyboard: .numberPad)
                    Picker("负荷判断", selection: $intensity) {
                        Text("无").tag("")
                        Text("偏轻").tag("偏轻")
                        Text("适中").tag("适中")
                        Text("偏重").tag("偏重")
                    }
                    RecordFieldRow(
                        title: "动作反馈",
                        placeholder: "未记录",
                        text: $feedback,
                        isMultiline: true
                    )
                }
            }

            Section {
                DisclosureGroup("原始记录", isExpanded: $notesExpanded) {
                    RecordFieldRow(
                        title: "文字记录",
                        placeholder: "未记录",
                        text: $notes,
                        isMultiline: true
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle(workout.exercise)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isDirty {
                    Button("保存", action: save)
                        .disabled(!isValid)
                }
            }
        }
        .onAppear {
            syncTargetKindFromExercise()
            sanitizeMistakenDurationIfNeeded()
        }
    }

    private var isValid: Bool {
        !exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && setRows.count <= 100
            && setRows.allSatisfy {
                EditorValue.validInt($0.logicalSetIndex, range: 1 ... 100)
                    && EditorValue.validInt($0.reps, range: 1 ... 1000)
                    && EditorValue.validInt($0.durationSeconds, range: 1 ... 86400)
                    && EditorValue.validDouble($0.weight, range: 0 ... 1000)
                    && EditorValue.validInt($0.restSeconds, range: 0 ... 3600)
            }
            && EditorValue.validInt(restSeconds, range: 0 ... 3600)
            && EditorValue.validInt(durationMinutes, range: 0 ... 1440)
            && EditorValue.validInt(estimatedCalories, range: 0 ... 10000)
            && EditorValue.validDouble(calorieMET, range: 0 ... 25)
            && EditorValue.validDouble(calorieDurationMinutes, range: 0 ... 1440)
            && EditorValue.validInt(formScore, range: 0 ... 100)
    }

    private var isDirty: Bool {
        date != workout.date
            || EditorValue.optionalText(exercise) != workout.exercise
            || setRows.map(\.evidence) != workout.setEntries
            || EditorValue.int(restSeconds) != workout.restSeconds
            || EditorValue.int(durationMinutes) != workout.durationMinutes
            || EditorValue.int(estimatedCalories) != workout.estimatedCalories
            || EditorValue.double(calorieMET) != workout.calorieMET
            || EditorValue.double(calorieDurationMinutes) != workout.calorieDurationMinutes
            || calorieDurationEstimated != workout.calorieDurationEstimated
            || EditorValue.int(formScore) != workout.formScore
            || EditorValue.optionalText(intensity) != workout.intensity
            || EditorValue.optionalText(feedback) != workout.feedback
            || notes.trimmingCharacters(in: .whitespacesAndNewlines) != workout.notes
    }

    private func numericField(
        _ title: String,
        unit: String? = nil,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        RecordFieldRow(
            title: title,
            placeholder: "未记录",
            unit: unit,
            text: text,
            keyboard: keyboard
        )
    }

    private func evidenceField(
        _ title: String,
        text: Binding<String>,
        unit: String,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("可选", text: text)
                    .keyboardType(keyboard)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(title)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func setTargetKind(at index: Int) -> WorkoutTargetKind {
        let row = setRows.indices.contains(index) ? setRows[index] : nil
        return ExerciseLoggingProfile.resolvedTargetKind(
            exercise: linkedExercise,
            evidenceTargetKind: row?.targetKind,
            reps: row.flatMap { EditorValue.int($0.reps) },
            durationSeconds: row.flatMap { EditorValue.int($0.durationSeconds) }
        )
    }

    private func syncTargetKindFromExercise() {
        let kind = ExerciseLoggingProfile.resolvedTargetKind(exercise: linkedExercise)
        for index in setRows.indices {
            setRows[index].targetKind = kind
        }
    }

    private func sanitizeMistakenDurationIfNeeded() {
        let weight = WorkoutCalorieCalculator.currentReferenceWeight(in: modelContext)
        guard WorkoutCalorieCalculator.sanitizeStoredDurationIfNeeded(
            workout,
            weightKG: weight
        ) else {
            return
        }
        try? modelContext.save()
        durationMinutes = EditorValue.string(workout.durationMinutes)
        estimatedCalories = EditorValue.string(workout.estimatedCalories)
        calorieMET = EditorValue.string(workout.calorieMET)
        calorieDurationMinutes = EditorValue.string(workout.calorieDurationMinutes)
        calorieDurationEstimated = workout.calorieDurationEstimated
    }

    private func save() {
        let normalizedExercise = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameKey = ExerciseLibraryStore.canonicalNameKey(normalizedExercise)
        if let exerciseID = workout.exerciseID,
           let current = definitions.first(where: { $0.id == exerciseID }),
           current.canonicalNameKey != nameKey
        {
            // Name changed away from the previous linked exercise; re-resolve.
            workout.exerciseID = nil
        }
        workout.exercise = normalizedExercise
        let definition = try? ExerciseLibraryStore.linkedExercise(
            for: workout,
            in: modelContext,
            persist: true,
            allowCreate: true
        )
        exercise = definition?.canonicalName ?? normalizedExercise
        notes = normalizedNotes
        workout.date = date
        if let definition {
            let kind = ExerciseLoggingProfile.resolvedTargetKind(exercise: definition)
            for index in setRows.indices {
                setRows[index].targetKind = kind
                if EditorValue.int(setRows[index].logicalSetIndex) == nil {
                    setRows[index].logicalSetIndex = String(index + 1)
                }
            }
        }
        workout.setEntries = setRows.map(\.evidence)
        workout.restSeconds = EditorValue.int(restSeconds)
        let sets = workout.setCount
        let reps = workout.representativeReps
        workout.durationMinutes = WorkoutCalorieCalculator.sanitizedActualDurationMinutes(
            EditorValue.int(durationMinutes),
            sets: sets,
            reps: reps,
            restSeconds: workout.restSeconds
        )
        durationMinutes = EditorValue.string(workout.durationMinutes)
        workout.estimatedCalories = EditorValue.int(estimatedCalories)
        workout.calorieMET = EditorValue.double(calorieMET)
        workout.calorieDurationMinutes = EditorValue.double(calorieDurationMinutes)
        workout.calorieDurationEstimated = calorieDurationEstimated
        workout.formScore = EditorValue.int(formScore)
        workout.intensity = EditorValue.optionalText(intensity)
        workout.feedback = EditorValue.optionalText(feedback)
        workout.notes = normalizedNotes
        try? modelContext.save()
    }
}

private struct MealRecordEditor: View {
    @Environment(\.modelContext) private var modelContext
    let meal: MealEntry

    @State private var date: Date
    @State private var mealType: MealType
    @State private var title: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var drafts: [MealItemDraft]
    @State private var notes: String
    @State private var macrosExpanded = false
    @State private var notesExpanded = false
    init(meal: MealEntry) {
        self.meal = meal
        _date = State(initialValue: meal.date)
        _mealType = State(initialValue: meal.mealType)
        _title = State(initialValue: meal.title)
        _calories = State(initialValue: EditorValue.string(meal.calories))
        _protein = State(initialValue: EditorValue.string(meal.protein))
        _carbs = State(initialValue: EditorValue.string(meal.carbs))
        _fat = State(initialValue: EditorValue.string(meal.fat))
        _drafts = State(initialValue: MealItemDraft.drafts(for: meal))
        _notes = State(initialValue: meal.notes)
    }

    var body: some View {
        Form {
            if !meal.mediaAttachments.isEmpty {
                Section("饮食媒体") {
                    RecordMediaGallery(
                        attachments: meal.mediaAttachments,
                        onDelete: {
                            MediaAssociationStore.detach(
                                $0,
                                from: meal,
                                in: modelContext
                            )
                        }
                    )
                }
            }

            Section("基本信息") {
                RecordFieldRow(title: "食物", placeholder: "餐食名称", text: $title)
                Picker("餐次", selection: $mealType) {
                    ForEach(MealType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                DatePicker("时间", selection: $date)
            }

            Section("食物项") {
                if drafts.isEmpty {
                    Text("尚未拆分食物项")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array($drafts.enumerated()), id: \.element.id) { index, $draft in
                    if index > 0 {
                        Divider()
                    }
                    MealItemDraftRow(draft: $draft) {
                        drafts.removeAll { $0.id == draft.id }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                Button {
                    drafts.append(MealItemDraft())
                } label: {
                    Label("添加食物", systemImage: "plus")
                }
            }

            // PRD 020：大卡保持直出，宏量与说明默认折叠。
            Section("营养估算") {
                RecordFieldRow(
                    title: "大卡",
                    placeholder: "未估算",
                    unit: "kcal",
                    text: $calories,
                    keyboard: .numberPad
                )
                DisclosureGroup("宏量营养", isExpanded: $macrosExpanded) {
                    RecordFieldRow(
                        title: "蛋白质",
                        placeholder: "未估算",
                        unit: "g",
                        text: $protein,
                        keyboard: .decimalPad
                    )
                    RecordFieldRow(
                        title: "碳水",
                        placeholder: "未估算",
                        unit: "g",
                        text: $carbs,
                        keyboard: .decimalPad
                    )
                    RecordFieldRow(
                        title: "脂肪",
                        placeholder: "未估算",
                        unit: "g",
                        text: $fat,
                        keyboard: .decimalPad
                    )
                }
            }

            Section {
                DisclosureGroup("记录与估算", isExpanded: $notesExpanded) {
                    RecordFieldRow(
                        title: "说明",
                        placeholder: "未记录",
                        text: $notes,
                        isMultiline: true
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle(meal.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isDirty {
                    Button("保存", action: save)
                        .disabled(!isValid)
                }
            }
        }
    }

    private var editedItems: [MealItem] {
        drafts.compactMap(\.item)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && EditorValue.validInt(calories, range: 0 ... 20000)
            && EditorValue.validDouble(protein, range: 0 ... 2000)
            && EditorValue.validDouble(carbs, range: 0 ... 2000)
            && EditorValue.validDouble(fat, range: 0 ... 2000)
    }

    private var isDirty: Bool {
        date != meal.date
            || mealType != meal.mealType
            || EditorValue.optionalText(title) != meal.title
            || EditorValue.int(calories) != meal.calories
            || EditorValue.double(protein) != meal.protein
            || EditorValue.double(carbs) != meal.carbs
            || EditorValue.double(fat) != meal.fat
            || editedItems != meal.items
            || notes.trimmingCharacters(in: .whitespacesAndNewlines) != meal.notes
    }

    private func save() {
        guard isValid else { return }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        title = normalizedTitle
        notes = normalizedNotes
        meal.date = date
        meal.mealType = mealType
        meal.title = normalizedTitle
        let normalizedItems = editedItems
        let editedTotals = EditorValue.int(calories) != meal.calories
            || EditorValue.double(protein) != meal.protein
            || EditorValue.double(carbs) != meal.carbs
            || EditorValue.double(fat) != meal.fat
        if normalizedItems != meal.items {
            meal.replaceItemsAndDeriveTotals(normalizedItems)
            drafts = MealItemDraft.drafts(for: meal)
        }
        if editedTotals {
            meal.calories = EditorValue.int(calories)
            meal.protein = EditorValue.double(protein)
            meal.carbs = EditorValue.double(carbs)
            meal.fat = EditorValue.double(fat)
            meal.nutritionSource = .userEdited
        }
        meal.notes = normalizedNotes
        try? modelContext.save()
    }
}

private struct BodyRecordEditor: View {
    @Environment(\.modelContext) private var modelContext
    let entry: BodyEntry

    @State private var date: Date
    @State private var weight: String
    @State private var bodyFat: String
    @State private var waist: String
    @State private var analysis: String
    @State private var notes: String
    @State private var analysisExpanded = false
    @State private var notesExpanded = false
    init(entry: BodyEntry) {
        self.entry = entry
        _date = State(initialValue: entry.date)
        _weight = State(initialValue: EditorValue.string(entry.weight))
        _bodyFat = State(initialValue: EditorValue.string(entry.bodyFat))
        _waist = State(initialValue: EditorValue.string(entry.waist))
        _analysis = State(initialValue: entry.analysis)
        _notes = State(initialValue: entry.notes)
    }

    var body: some View {
        Form {
            if !entry.mediaAttachments.isEmpty {
                Section("体态媒体") {
                    RecordMediaGallery(
                        attachments: entry.mediaAttachments,
                        onDelete: {
                            MediaAssociationStore.detach(
                                $0,
                                from: entry,
                                in: modelContext
                            )
                        }
                    )
                }
            }

            Section("身体数据") {
                DatePicker("时间", selection: $date)
                RecordFieldRow(
                    title: "体重",
                    placeholder: "未记录",
                    unit: "kg",
                    text: $weight,
                    keyboard: .decimalPad
                )
                RecordFieldRow(
                    title: "体脂",
                    placeholder: "未记录",
                    unit: "%",
                    text: $bodyFat,
                    keyboard: .decimalPad
                )
                RecordFieldRow(
                    title: "腰围",
                    placeholder: "未记录",
                    unit: "cm",
                    text: $waist,
                    keyboard: .decimalPad
                )
            }

            // PRD 020：AI 观察与原始记录默认折叠，展开后仍可完整编辑。
            Section {
                DisclosureGroup("AI 体态观察", isExpanded: $analysisExpanded) {
                    RecordFieldRow(
                        title: "观察",
                        placeholder: "未记录",
                        text: $analysis,
                        isMultiline: true
                    )
                }
            }

            Section {
                DisclosureGroup("原始记录", isExpanded: $notesExpanded) {
                    RecordFieldRow(
                        title: "文字记录",
                        placeholder: "未记录",
                        text: $notes,
                        isMultiline: true
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("身体记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isDirty {
                    Button("保存", action: save)
                        .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        EditorValue.validDouble(weight, range: 1 ... 500)
            && EditorValue.validDouble(bodyFat, range: 0 ... 100)
            && EditorValue.validDouble(waist, range: 1 ... 500)
    }

    private var isDirty: Bool {
        date != entry.date
            || EditorValue.double(weight) != entry.weight
            || EditorValue.double(bodyFat) != entry.bodyFat
            || EditorValue.double(waist) != entry.waist
            || analysis.trimmingCharacters(in: .whitespacesAndNewlines) != entry.analysis
            || notes.trimmingCharacters(in: .whitespacesAndNewlines) != entry.notes
    }

    private func save() {
        let normalizedAnalysis = analysis.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        analysis = normalizedAnalysis
        notes = normalizedNotes
        entry.date = date
        entry.weight = EditorValue.double(weight)
        entry.bodyFat = EditorValue.double(bodyFat)
        entry.waist = EditorValue.double(waist)
        entry.analysis = normalizedAnalysis
        entry.notes = normalizedNotes
        try? modelContext.save()
    }
}

private struct RecordFieldRow: View {
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
                    .lineLimit(2 ... 8)
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

private enum EditorValue {
    static func optionalText(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func int(_ value: String) -> Int? {
        optionalText(value).flatMap(Int.init)
    }

    static func double(_ value: String) -> Double? {
        optionalText(value).flatMap {
            Double($0.replacingOccurrences(of: ",", with: "."))
        }
    }

    static func string(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    static func string(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0 ... 2))) } ?? ""
    }

    static func string(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 2)))
    }

    static func validInt(_ value: String, range: ClosedRange<Int>) -> Bool {
        guard optionalText(value) != nil else { return true }
        guard let number = int(value) else { return false }
        return range.contains(number)
    }

    static func validDouble(_ value: String, range: ClosedRange<Double>) -> Bool {
        guard optionalText(value) != nil else { return true }
        guard let number = double(value) else { return false }
        return range.contains(number)
    }

    static func requiredInt(_ value: String, range: ClosedRange<Int>) -> Int? {
        guard let number = int(value), range.contains(number) else { return nil }
        return number
    }

    static func requiredDouble(_ value: String, range: ClosedRange<Double>) -> Double? {
        guard let number = double(value), range.contains(number) else { return nil }
        return number
    }
}

private struct DetailTextCard: View {
    let title: String
    let icon: String
    let text: String

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(AppTheme.tint)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
    }
}
