import AVKit
import SwiftData
import SwiftUI

struct MediaThumbnail: View {
    let kind: MediaKind
    let path: String?
    var fallbackIcon: String

    var body: some View {
        Group {
            switch kind {
            case .image:
                LocalImageView(path: path)
            case .video:
                ZStack {
                    Color.black.opacity(0.86)
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            case .none:
                ZStack {
                    AppTheme.softTint
                    Image(systemName: fallbackIcon)
                        .foregroundStyle(AppTheme.tint)
                }
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LocalVideoPlayer: View {
    @State private var player: AVPlayer?

    init(path: String) {
        _player = State(initialValue: MediaStore.url(at: path).map { AVPlayer(url: $0) })
    }

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onDisappear { player.pause() }
            } else {
                ContentUnavailableView("视频不可用", systemImage: "video.slash")
            }
        }
        .frame(height: 240)
        .background(.black, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
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

private struct RecordMediaGallery: View {
    let attachments: [MediaAttachmentReference]

    var body: some View {
        TabView {
            ForEach(attachments) { attachment in
                Group {
                    switch attachment.kind {
                    case .image:
                        RecordImage(path: attachment.path)
                    case .video:
                        LocalVideoPlayer(path: attachment.path)
                    case .none:
                        EmptyView()
                    }
                }
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
            }
        }
        .tabViewStyle(.page(indexDisplayMode: attachments.count > 1 ? .automatic : .never))
        .frame(height: 270)
    }

    private func position(of attachment: MediaAttachmentReference) -> Int {
        attachments.firstIndex(where: { $0.id == attachment.id }) ?? 0
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
    @State private var sets: String
    @State private var reps: String
    @State private var weight: String
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

    init(workout: WorkoutEntry) {
        self.workout = workout
        _date = State(initialValue: workout.date)
        _exercise = State(initialValue: workout.exercise)
        _sets = State(initialValue: EditorValue.string(workout.sets))
        _reps = State(initialValue: EditorValue.string(workout.reps))
        _weight = State(initialValue: EditorValue.string(workout.weight))
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

    var body: some View {
        Form {
            if !workout.mediaAttachments.isEmpty {
                Section("记录媒体") {
                    RecordMediaGallery(attachments: workout.mediaAttachments)
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
                numericField("组数", text: $sets, keyboard: .numberPad)
                numericField("次数", text: $reps, keyboard: .numberPad)
                numericField("重量", unit: "kg", text: $weight, keyboard: .decimalPad)
                numericField("间歇", unit: "秒", text: $restSeconds, keyboard: .numberPad)
                numericField("训练时长", unit: "分钟", text: $durationMinutes, keyboard: .numberPad)
            } header: {
                Text("训练数据")
            } footer: {
                Text("留空代表没有数据，不会自动补默认值。")
            }

            Section {
                numericField("预计消耗", unit: "kcal", text: $estimatedCalories, keyboard: .numberPad)
                numericField("MET", text: $calorieMET, keyboard: .decimalPad)
                numericField("计算时长", unit: "分钟", text: $calorieDurationMinutes, keyboard: .decimalPad)
                Toggle("计算时长来自推算", isOn: $calorieDurationEstimated)
            } header: {
                Text("热量估算")
            } footer: {
                Text("MET × 参考体重 × 计算时长。推算时长只用于热量估算，不会填入上方的实际训练时长。")
            }

            Section("AI 解析") {
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

            Section("原始记录") {
                RecordFieldRow(
                    title: "文字记录",
                    placeholder: "未记录",
                    text: $notes,
                    isMultiline: true
                )
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
    }

    private var isValid: Bool {
        !exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && EditorValue.validInt(sets, range: 1 ... 100)
            && EditorValue.validInt(reps, range: 1 ... 1000)
            && EditorValue.validDouble(weight, range: 0 ... 1000)
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
            || EditorValue.int(sets) != workout.sets
            || EditorValue.int(reps) != workout.reps
            || EditorValue.double(weight) != workout.weight
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

    private func save() {
        let normalizedExercise = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        exercise = normalizedExercise
        notes = normalizedNotes
        workout.date = date
        workout.exercise = normalizedExercise
        workout.sets = EditorValue.int(sets)
        workout.reps = EditorValue.int(reps)
        workout.weight = EditorValue.double(weight)
        workout.restSeconds = EditorValue.int(restSeconds)
        workout.durationMinutes = EditorValue.int(durationMinutes)
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
    @State private var notes: String

    init(meal: MealEntry) {
        self.meal = meal
        _date = State(initialValue: meal.date)
        _mealType = State(initialValue: meal.mealType)
        _title = State(initialValue: meal.title)
        _calories = State(initialValue: String(meal.calories))
        _protein = State(initialValue: EditorValue.string(meal.protein))
        _carbs = State(initialValue: EditorValue.string(meal.carbs))
        _fat = State(initialValue: EditorValue.string(meal.fat))
        _notes = State(initialValue: meal.notes)
    }

    var body: some View {
        Form {
            if !meal.mediaAttachments.isEmpty {
                Section("饮食媒体") {
                    RecordMediaGallery(attachments: meal.mediaAttachments)
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

            Section("营养估算") {
                RecordFieldRow(
                    title: "大卡",
                    placeholder: "必填",
                    unit: "kcal",
                    text: $calories,
                    keyboard: .numberPad
                )
                RecordFieldRow(
                    title: "蛋白质",
                    placeholder: "必填",
                    unit: "g",
                    text: $protein,
                    keyboard: .decimalPad
                )
                RecordFieldRow(
                    title: "碳水",
                    placeholder: "必填",
                    unit: "g",
                    text: $carbs,
                    keyboard: .decimalPad
                )
                RecordFieldRow(
                    title: "脂肪",
                    placeholder: "必填",
                    unit: "g",
                    text: $fat,
                    keyboard: .decimalPad
                )
            }

            Section("记录与估算") {
                RecordFieldRow(
                    title: "说明",
                    placeholder: "未记录",
                    text: $notes,
                    isMultiline: true
                )
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

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && EditorValue.requiredInt(calories, range: 0 ... 20000) != nil
            && EditorValue.requiredDouble(protein, range: 0 ... 2000) != nil
            && EditorValue.requiredDouble(carbs, range: 0 ... 2000) != nil
            && EditorValue.requiredDouble(fat, range: 0 ... 2000) != nil
    }

    private var isDirty: Bool {
        date != meal.date
            || mealType != meal.mealType
            || EditorValue.optionalText(title) != meal.title
            || EditorValue.requiredInt(calories, range: 0 ... 20000) != meal.calories
            || EditorValue.requiredDouble(protein, range: 0 ... 2000) != meal.protein
            || EditorValue.requiredDouble(carbs, range: 0 ... 2000) != meal.carbs
            || EditorValue.requiredDouble(fat, range: 0 ... 2000) != meal.fat
            || notes.trimmingCharacters(in: .whitespacesAndNewlines) != meal.notes
    }

    private func save() {
        guard
            let calories = EditorValue.requiredInt(calories, range: 0 ... 20000),
            let protein = EditorValue.requiredDouble(protein, range: 0 ... 2000),
            let carbs = EditorValue.requiredDouble(carbs, range: 0 ... 2000),
            let fat = EditorValue.requiredDouble(fat, range: 0 ... 2000)
        else { return }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        title = normalizedTitle
        notes = normalizedNotes
        meal.date = date
        meal.mealType = mealType
        meal.title = normalizedTitle
        meal.calories = calories
        meal.protein = protein
        meal.carbs = carbs
        meal.fat = fat
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
                    RecordMediaGallery(attachments: entry.mediaAttachments)
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

            Section("AI 体态观察") {
                RecordFieldRow(
                    title: "观察",
                    placeholder: "未记录",
                    text: $analysis,
                    isMultiline: true
                )
            }

            Section("原始记录") {
                RecordFieldRow(
                    title: "文字记录",
                    placeholder: "未记录",
                    text: $notes,
                    isMultiline: true
                )
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
