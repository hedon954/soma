import SwiftData
import SwiftUI

struct MediaThumbnail: View {
    let kind: MediaKind
    let path: String?
    var fallbackIcon: String
    var width: CGFloat = 58
    var height: CGFloat = 58
    var role: AppSemanticRole = .training

    var body: some View {
        Group {
            switch kind {
            case .image:
                LocalImageView(path: path)
            case .video:
                VideoPosterView(path: path)
            case .none:
                ZStack {
                    role.softTint
                    Image(systemName: fallbackIcon)
                        .foregroundStyle(role.accent)
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
    @Environment(\.modelContext) private var modelContext
    let workout: WorkoutEntry

    @State private var date: Date
    @State private var exercise: String
    @State private var workoutDraft: WorkoutRecordDraft
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
    @State private var caloriesExpanded = false
    @State private var analysisExpanded = false
    @State private var notesExpanded = false
    @State private var hasCalorieReferenceWeight: Bool?
    init(workout: WorkoutEntry) {
        self.workout = workout
        _date = State(initialValue: workout.date)
        _exercise = State(initialValue: workout.exercise)
        _workoutDraft = State(
            initialValue: WorkoutRecordDraft(
                evidence: workout.setEntries,
                loggingProfile: workout.exerciseDefinition.map(
                    ExerciseLoggingProfileSnapshot.init
                )
            )
        )
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
        workout.exerciseDefinition
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

                    Text("受力图")
                        .font(.headline)
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

            Section("基本信息") {
                RecordFieldRow(
                    title: "动作",
                    placeholder: "动作名称",
                    text: $exercise
                )
                DatePicker("时间", selection: $date)
            }

            Section {
                WorkoutLogicalGroupsEditor(
                    draft: $workoutDraft,
                    isEditable: true,
                    fallbackRestSeconds: EditorValue.int(restSeconds)
                )
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
                    numericField(
                        "预计消耗",
                        unit: "kcal",
                        text: $estimatedCalories,
                        keyboard: .numberPad
                    )
                    LabeledContent(
                        "MET",
                        value: EditorValue.double(calorieMET)?.formatted(
                            .number.precision(.fractionLength(0 ... 1))
                        ) ?? "—"
                    )
                    LabeledContent(
                        "计算时长",
                        value: EditorValue.double(calorieDurationMinutes).map {
                            "\($0.formatted(.number.precision(.fractionLength(0 ... 1)))) 分钟"
                        } ?? "—"
                    )
                    LabeledContent(
                        "时长来源",
                        value: calorieDurationEstimated ? "按训练证据推算" : "实际记录"
                    )

                    if hasCalorieReferenceWeight == false {
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
                    } else if EditorValue.int(estimatedCalories) == nil {
                        Text("还缺少完整的次数/时长或组间歇事实，暂不猜测训练消耗。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    LabeledContent(
                        "热量估算",
                        value: EditorValue.int(estimatedCalories).map { "约 \($0) kcal" } ?? "未记录"
                    )
                }
            } footer: {
                if caloriesExpanded {
                    Text("MET × 最近体重记录 × 计算时长。可改写预计消耗，清空后按公式重算。推算时长只用于热量估算，不会填入上方的实际训练时长。")
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
            sanitizeMistakenDurationIfNeeded()
        }
        .task(id: date) {
            hasCalorieReferenceWeight = nil
            await Task.yield()
            guard !Task.isCancelled else { return }
            let available = WorkoutCalorieCalculator.latestRecordedWeight(
                at: date,
                in: modelContext
            ) != nil
            guard !Task.isCancelled else { return }
            hasCalorieReferenceWeight = available
        }
    }

    private var isValid: Bool {
        !exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && workoutDraft.isValid
            && EditorValue.validInt(restSeconds, range: 0 ... 3600)
            && EditorValue.validInt(durationMinutes, range: 0 ... 1440)
            && EditorValue.validInt(formScore, range: 0 ... 100)
            && EditorValue.validInt(estimatedCalories, range: 0 ... 20000)
    }

    private var isDirty: Bool {
        date != workout.date
            || EditorValue.optionalText(exercise) != workout.exercise
            || workoutDraft.evidence != workout.setEntries
            || EditorValue.int(restSeconds) != workout.restSeconds
            || EditorValue.int(durationMinutes) != workout.durationMinutes
            || EditorValue.int(formScore) != workout.formScore
            || EditorValue.int(estimatedCalories) != workout.estimatedCalories
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

    private func sanitizeMistakenDurationIfNeeded() {
        let weight = WorkoutCalorieCalculator.latestRecordedWeight(
            at: workout.date,
            in: modelContext
        )
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
        if let current = workout.exerciseDefinition,
           current.canonicalNameKey != nameKey
        {
            // Name changed away from the previous linked exercise; re-resolve.
            workout.exerciseID = nil
            workout.exerciseDefinition = nil
        }
        workout.exercise = normalizedExercise
        let definition = try? ExerciseLibraryStore.linkedExercise(
            for: workout,
            in: modelContext,
            persist: true,
            allowCreate: true
        )
        exercise = definition?.canonicalName ?? normalizedExercise
        if let definition {
            workoutDraft.applyLoggingProfile(
                ExerciseLoggingProfileSnapshot(definition)
            )
        }
        notes = normalizedNotes
        workout.date = date
        workout.setEntries = workoutDraft.evidence
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
        workout.formScore = EditorValue.int(formScore)
        workout.intensity = EditorValue.optionalText(intensity)
        workout.feedback = EditorValue.optionalText(feedback)
        workout.notes = normalizedNotes
        WorkoutCalorieCalculator.refreshStoredEstimate(
            workout,
            in: modelContext,
            calorieOverride: EditorValue.int(estimatedCalories)
        )
        estimatedCalories = EditorValue.string(workout.estimatedCalories)
        calorieMET = EditorValue.string(workout.calorieMET)
        calorieDurationMinutes = EditorValue.string(workout.calorieDurationMinutes)
        calorieDurationEstimated = workout.calorieDurationEstimated
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
    @State private var glycemicSpeed: MealGlycemicSpeed?
    @State private var glycemicAssessment: String
    @State private var recommendedEatingOrder: String
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
        _glycemicSpeed = State(initialValue: meal.glycemicSpeed)
        _glycemicAssessment = State(initialValue: meal.glycemicAssessment)
        _recommendedEatingOrder = State(initialValue: meal.recommendedEatingOrder)
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
                ForEach($drafts) { $draft in
                    MealItemDraftRow(draft: $draft) {
                        drafts.removeAll { $0.id == draft.id }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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

            Section("升糖速度") {
                Picker("食物组成估算", selection: $glycemicSpeed) {
                    Text("证据不足").tag(nil as MealGlycemicSpeed?)
                    ForEach(MealGlycemicSpeed.allCases) { speed in
                        Text(speed.displayName).tag(Optional(speed))
                    }
                }
                RecordFieldRow(
                    title: "估算依据",
                    placeholder: "证据与不确定性",
                    text: $glycemicAssessment,
                    isMultiline: true
                )
                Text("这里只描述食物组成的定性速度，不代表个人实际血糖峰值，也不能用于诊断。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("建议食用顺序") {
                RecordFieldRow(
                    title: "顺序",
                    placeholder: "例如：蔬菜 → 蛋白质 → 主食",
                    text: $recommendedEatingOrder,
                    isMultiline: true
                )
                Text("只按这餐实际包含的食物排列；不是必须严格遵循的医疗建议。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            && ((glycemicSpeed == nil && glycemicAssessment.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty) || (glycemicSpeed != nil && !glycemicAssessment.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty))
    }

    private var isDirty: Bool {
        date != meal.date
            || mealType != meal.mealType
            || EditorValue.optionalText(title) != meal.title
            || EditorValue.int(calories) != meal.calories
            || EditorValue.double(protein) != meal.protein
            || EditorValue.double(carbs) != meal.carbs
            || EditorValue.double(fat) != meal.fat
            || glycemicSpeed != meal.glycemicSpeed
            || glycemicAssessment.trimmingCharacters(in: .whitespacesAndNewlines)
            != meal.glycemicAssessment
            || recommendedEatingOrder.trimmingCharacters(in: .whitespacesAndNewlines)
            != meal.recommendedEatingOrder
            || editedItems != meal.items
            || notes.trimmingCharacters(in: .whitespacesAndNewlines) != meal.notes
    }

    private func save() {
        guard isValid else { return }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedGlycemicAssessment = glycemicAssessment.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedEatingOrder = recommendedEatingOrder.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        title = normalizedTitle
        notes = normalizedNotes
        meal.date = date
        meal.mealType = mealType
        meal.title = normalizedTitle
        let normalizedItems = editedItems
        let itemsChanged = normalizedItems != meal.items
        let editedTotals = EditorValue.int(calories) != meal.calories
            || EditorValue.double(protein) != meal.protein
            || EditorValue.double(carbs) != meal.carbs
            || EditorValue.double(fat) != meal.fat
        let editedGlycemic = glycemicSpeed != meal.glycemicSpeed
            || normalizedGlycemicAssessment != meal.glycemicAssessment
        let editedEatingOrder = normalizedEatingOrder != meal.recommendedEatingOrder
        if itemsChanged {
            meal.replaceItemsAndDeriveTotals(normalizedItems)
            drafts = MealItemDraft.drafts(for: meal)
            if !editedTotals {
                calories = EditorValue.string(meal.calories)
                protein = EditorValue.string(meal.protein)
                carbs = EditorValue.string(meal.carbs)
                fat = EditorValue.string(meal.fat)
            }
        }
        if editedTotals {
            meal.calories = EditorValue.int(calories)
            meal.protein = EditorValue.double(protein)
            meal.carbs = EditorValue.double(carbs)
            meal.fat = EditorValue.double(fat)
            meal.nutritionSource = .userEdited
        }
        if editedGlycemic {
            meal.glycemicSpeed = glycemicSpeed
            meal.glycemicAssessment = normalizedGlycemicAssessment
        } else if itemsChanged {
            glycemicSpeed = nil
            glycemicAssessment = ""
        }
        if editedEatingOrder {
            meal.recommendedEatingOrder = normalizedEatingOrder
        } else if itemsChanged {
            recommendedEatingOrder = ""
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
