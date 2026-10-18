import SwiftData
import SwiftUI

struct TrainingContentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let definitions: [ExerciseDefinition]
    let programs: [TrainingProgram]
    let plans: [TrainingSchedule]
    let onSelect: (TrainingContentSource) -> Void
    private enum Category: String, CaseIterable {
        case courses = "课程"
        case exercises = "动作"
        case plans = "计划"
    }

    @State private var category = Category.courses
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("训练内容类型", selection: $category) {
                ForEach(Category.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .padding(.horizontal, AppTheme.pagePadding)
            .accessibilityIdentifier("training-content-tabs")

            List {
                switch category {
                case .exercises:
                    exerciseRows
                case .courses:
                    courseRows
                case .plans:
                    planRows
                }
            }
            .id(category)
            .scrollContentBackground(.hidden)
            .foregroundStyle(AppTheme.accent)
        }
        .appPageBackground()
        .searchable(text: $search, prompt: "搜索\(category.rawValue)")
        .navigationTitle("添加训练内容")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var exerciseRows: some View {
        let values = definitions.filter { matches($0.canonicalName) }
        if values.isEmpty {
            emptyState
        }
        ForEach(values) { exercise in
            NavigationLink(exercise.canonicalName) {
                TrainingContentExerciseView(exercise: exercise, definitions: definitions) { value in
                    onSelect(.exercise(value))
                    dismiss()
                }
            }
            .listRowBackground(AppTheme.cardBackground)
        }
    }

    @ViewBuilder private var courseRows: some View {
        let values = programs.filter { $0.status == .active && matches($0.name) }
        if values.isEmpty {
            emptyState
        }
        ForEach(values) { program in
            Button(program.name) { onSelect(.course(program.id)); dismiss() }
                .listRowBackground(AppTheme.cardBackground)
        }
    }

    @ViewBuilder private var planRows: some View {
        let values = plans.filter { matches($0.name) }
        if values.isEmpty {
            emptyState
        }
        ForEach(values) { plan in
            Button(plan.name) { onSelect(.plan(plan.id)); dismiss() }
                .listRowBackground(AppTheme.cardBackground)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            search.isEmpty ? "暂无可选\(category.rawValue)" : "没有匹配的\(category.rawValue)",
            systemImage: "magnifyingglass",
            description: Text(search.isEmpty ? "可以切换类型选择其他训练内容。" : "试试其他关键词。")
        )
        .listRowBackground(AppTheme.pageBackground)
    }

    private func matches(_ name: String) -> Bool {
        search.isEmpty || name.localizedCaseInsensitiveContains(search)
    }
}

private struct TrainingContentExerciseView: View {
    @Environment(\.modelContext) private var modelContext
    let exercise: ExerciseDefinition
    let definitions: [ExerciseDefinition]
    let onSave: (TemplateExercisePrescription) -> Void
    @State private var initial: TemplateExercisePrescription?
    @State private var sourceDate: Date?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let initial {
                TrainingPrescriptionEditorView(
                    initialDraft: TrainingPrescriptionDraft(initial), exercise: exercise,
                    definitions: definitions, recent: nil, saveTitle: "加入计划",
                    locksExerciseSettings: true,
                    parameterSourceExplanation: sourceDate.map {
                        "推荐自 \($0.formatted(date: .abbreviated, time: .omitted)) 的实际训练，可修改后加入计划。"
                    } ?? "填写这次计划的训练参数。未提供的值保持空白。"
                ) { updated in
                    let value = updated.prescription(order: 1, names: [exercise.id: exercise.canonicalName])
                    try TrainingPlanStore.validate([value], in: modelContext)
                    onSave(value)
                }
            } else if let errorMessage {
                ContentUnavailableView("无法读取最近训练", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                Button("重试", action: load)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if initial == nil {
                load()
            }
        }
    }

    private func load() {
        do {
            let recommendation = try TrainingContentRecommendations.latest(for: exercise, in: modelContext)
            sourceDate = recommendation?.sourceDate
            initial = recommendation?.prescription ?? TemplateExercisePrescription(
                exerciseID: exercise.id, exerciseName: exercise.canonicalName, order: 1,
                laterality: exercise.laterality,
                plannedSets: [.init(order: 1, targetKind: exercise.targetKind)]
            )
        } catch { errorMessage = AppErrorMessage.message(for: error, operation: .save) }
    }
}
