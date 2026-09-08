import SwiftData
import SwiftUI

private struct MealAutosaveValue: Equatable {
    var mealType: MealType
    var drafts: [MealItemDraft]
}

/// ADR 0084：饮食结果在聊天里分两张卡。第一张是可编辑的菜品拆解，第二张是随草稿实时
/// 重算的只读汇总。用户在第一张卡改完保存，第二张卡的数字就是写入本机的数字。
/// ADR 0085：拆解卡按清单读，数值直接原位可改，不用一排输入框把卡片撑成表单。
struct InlineMealCards: View {
    @Environment(\.modelContext) private var modelContext
    let meal: MealEntry
    let sourceMessage: CoachMessage?
    let isEditable: Bool

    @State private var mealType: MealType
    @State private var drafts: [MealItemDraft]
    @State private var showsDelete = false
    @State private var saveState: InlineRecordSaveState = .idle

    init(meal: MealEntry, sourceMessage: CoachMessage?, isEditable: Bool) {
        self.meal = meal
        self.sourceMessage = sourceMessage
        self.isEditable = isEditable
        _mealType = State(initialValue: meal.mealType)
        _drafts = State(initialValue: MealItemDraft.drafts(for: meal))
    }

    private var totals: MealNutritionTotals {
        MealNutritionTotals.derive(from: drafts.compactMap(\.item))
    }

    private var assessmentIsCurrent: Bool {
        drafts.compactMap(\.item) == meal.items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            itemsCard
            MealTotalsCard(
                meal: meal,
                mealType: mealType,
                totals: totals,
                itemCount: drafts.compactMap(\.item).count,
                glycemicSpeed: assessmentIsCurrent ? meal.glycemicSpeed : nil,
                glycemicAssessment: assessmentIsCurrent ? meal.glycemicAssessment : "",
                recommendedEatingOrder: assessmentIsCurrent
                    ? meal.recommendedEatingOrder : ""
            )
        }
        .confirmationDialog("删除这条饮食记录？", isPresented: $showsDelete) {
            Button("删除记录", role: .destructive, action: deleteRecord)
        }
    }

    private var itemsCard: some View {
        InlineRecordShell(
            title: "记饮食",
            icon: "fork.knife",
            iconTint: AppTheme.mealAccent,
            iconSoftTint: AppTheme.mealSoftTint,
            isEditable: isEditable,
            saveState: $saveState,
            onSave: isEditable ? save : nil,
            onDelete: isEditable ? { showsDelete = true } : nil,
            accessory: { mealTypePicker }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if isEditable {
                    ForEach($drafts) { $draft in
                        MealItemDraftRow(draft: $draft) {
                            drafts.removeAll { $0.id == draft.id }
                        }
                        .overlay(alignment: .bottom) {
                            if draft.id != drafts.last?.id {
                                Divider()
                            }
                        }
                    }
                    Divider()
                    Button {
                        drafts.append(MealItemDraft())
                    } label: {
                        Label("添加菜品", systemImage: "plus.circle")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.mealAccent)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                } else {
                    readOnlyItems
                }
            }
        }
        .inlineRecordAutosave(
            value: MealAutosaveValue(mealType: mealType, drafts: drafts),
            isEnabled: isEditable,
            state: $saveState,
            save: save
        )
    }

    @ViewBuilder
    private var mealTypePicker: some View {
        if isEditable {
            Menu {
                Picker("餐次", selection: $mealType) {
                    ForEach(MealType.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(mealType.rawValue)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.mealAccent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AppTheme.mealSoftTint, in: Capsule())
            }
            .accessibilityLabel("餐次")
            .accessibilityValue(mealType.rawValue)
        }
    }

    @ViewBuilder
    private var readOnlyItems: some View {
        if meal.items.isEmpty {
            Text("没有菜品明细")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else {
            ForEach(Array(meal.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                }
                MealItemReadOnlyRow(item: item)
            }
        }
    }

    private func save() -> Bool {
        let items = drafts.compactMap(\.item)
        guard !items.isEmpty else { return false }
        meal.mealType = mealType
        meal.title = MealItemDraft.title(for: items)
        meal.replaceItemsAndDeriveTotals(items)
        sourceMessage?.recordManualCorrection(
            "饮食记录 \(AgentFacingRecordID.correctionToken(meal.businessID)) 已改为 \(mealType.rawValue)，"
                + "\(items.count) 项菜品：\(MealItemDraft.summary(for: items))"
        )
        try? modelContext.save()
        return true
    }

    private func deleteRecord() {
        sourceMessage?.recordManualCorrection(
            "饮食记录 \(AgentFacingRecordID.correctionToken(meal.businessID)) 已由用户删除"
        )
        modelContext.delete(meal)
        try? modelContext.save()
    }
}

/// 一行菜品：左侧图标块，右侧名称与热量，第二行是份量与宏量。数值直接可点可改。
struct MealItemDraftRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var draft: MealItemDraft
    var showsDelete = true
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            MealItemIcon()
            VStack(alignment: .leading, spacing: 2) {
                titleLine
                metrics
            }
            if showsDelete, let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除\(draft.name.isEmpty ? "这一项菜品" : draft.name)")
            }
        }
        .padding(.vertical, 4)
    }

    /// 辅助字号下菜名会占满整行，热量必须换行放，否则数字和单位会叠在一起。
    @ViewBuilder
    private var titleLine: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                name
                calories
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                name
                    .frame(maxWidth: .infinity, alignment: .leading)
                calories
            }
        }
    }

    private var name: some View {
        InlineTextValue(
            placeholder: "菜品",
            text: $draft.name,
            font: .footnote.weight(.semibold),
            allowsWrapping: true,
            accessibilityTitle: "菜品名称"
        )
    }

    private var calories: some View {
        InlineTextValue(
            placeholder: "-",
            text: $draft.calories,
            font: .footnote.weight(.semibold).monospacedDigit(),
            keyboard: .numberPad,
            suffix: "千卡",
            accessibilityTitle: "热量，千卡"
        )
    }

    /// 辅助字号下每项各占一行；常规字号保持单行，避免 ViewThatFits 复制整行布局。
    @ViewBuilder
    private var metrics: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                portion
                macro("蛋白", $draft.protein)
                macro("碳水", $draft.carbs)
                macro("脂肪", $draft.fat)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                portion
                macros
            }
        }
    }

    private var portion: some View {
        InlineTextValue(
            placeholder: "份量",
            text: $draft.portion,
            font: .caption2,
            tint: .secondary,
            accessibilityTitle: "份量",
            onCommit: { oldValue, newValue in
                // TextField 会逐字符写 Binding；离开编辑态后再以完整的新旧份量缩放，
                // 避免 `1 颗 → "" → 2 → 2 颗` 丢失原始比例基线。
                draft.portion = oldValue
                draft.updatePortion(newValue)
            }
        )
    }

    @ViewBuilder
    private var macros: some View {
        macro("蛋白", $draft.protein)
        macro("碳水", $draft.carbs)
        macro("脂肪", $draft.fat)
    }

    /// 单位统一在汇总卡里写清楚，行内只留标签和数字，保持一行读得完。
    private func macro(_ title: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            InlineTextValue(
                placeholder: "-",
                text: text,
                font: .caption2.monospacedDigit(),
                tint: .secondary,
                keyboard: .decimalPad,
                accessibilityTitle: "\(title)，克"
            )
        }
    }
}

struct MealItemReadOnlyRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: MealItem

    private var caption: String {
        [
            item.portionDescription,
            item.protein.map { "蛋白 \($0.formatted())" },
            item.carbs.map { "碳水 \($0.formatted())" },
            item.fat.map { "脂肪 \($0.formatted())" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            MealItemIcon()
            VStack(alignment: .leading, spacing: 2) {
                let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
                layout {
                    Text(item.name)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1 ... 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.calories.map { "\($0) 千卡" } ?? "未估算")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                if !caption.isEmpty {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct MealItemIcon: View {
    var body: some View {
        Image(systemName: "takeoutbag.and.cup.and.straw.fill")
            .font(.caption2)
            .foregroundStyle(AppTheme.mealAccent)
            .frame(width: 22, height: 22)
            .background(
                AppTheme.mealSoftTint,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// 看起来是文字、点一下就能改的行内数值。聚焦时给一层浅底，明确当前在编辑哪个值。
struct InlineTextValue: View {
    let placeholder: String
    @Binding var text: String
    var font: Font = .caption
    var tint: Color = .primary
    var keyboard: UIKeyboardType = .default
    var suffix: String?
    var allowsWrapping = false
    let accessibilityTitle: String
    var onCommit: (String, String) -> Void = { _, _ in }

    @State private var isEditing = false
    @State private var valueAtEditingStart = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 2) {
            Group {
                if isEditing {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit(endEditing)
                        .onChange(of: isFocused) { _, focused in
                            if !focused {
                                finishEditing()
                            }
                        }
                        .accessibilityIdentifier("meal-inline-value-editor")
                } else {
                    Button(action: beginEditing) {
                        Text(text.isEmpty ? placeholder : text)
                            .foregroundStyle(text.isEmpty ? Color.secondary : tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("meal-inline-value-display")
                }
            }
            .font(font)
            .foregroundStyle(tint)
            .lineLimit(allowsWrapping ? 1 ... 3 : 1 ... 1)
            .fixedSize(horizontal: !allowsWrapping, vertical: allowsWrapping)
            .frame(minWidth: 22, alignment: .leading)
            if let suffix, !text.isEmpty {
                Text(suffix)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            isFocused ? AppTheme.softTint : .clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(text.isEmpty ? "未填写" : text)
        .accessibilityHint(isEditing ? "正在编辑" : "点按编辑")
    }

    private func beginEditing() {
        valueAtEditingStart = text
        isEditing = true
        Task { @MainActor in
            await Task.yield()
            guard isEditing else { return }
            isFocused = true
        }
    }

    private func endEditing() {
        isFocused = false
        finishEditing()
    }

    private func finishEditing() {
        guard isEditing else { return }
        isEditing = false
        let initialValue = valueAtEditingStart
        valueAtEditingStart = text
        guard initialValue != text else { return }
        onCommit(initialValue, text)
    }
}

/// 只读派生汇总：随第一张卡的草稿实时重算。完整字段显示精确总值；
/// 部分字段显示已知小计并加“≥”，不把未知项猜成 0。
private struct MealTotalsCard: View {
    let meal: MealEntry
    let mealType: MealType
    let totals: MealNutritionTotals
    let itemCount: Int
    let glycemicSpeed: MealGlycemicSpeed?
    let glycemicAssessment: String
    let recommendedEatingOrder: String
    @State private var showsDetail = false

    var body: some View {
        InlineRecordShell(
            title: "饮食评价",
            icon: "chart.pie",
            iconTint: AppTheme.mealAccent,
            iconSoftTint: AppTheme.mealSoftTint,
            isEditable: false,
            showsLockWhenReadOnly: false
        ) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(header)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(displayValue(
                            exact: totals.calories,
                            known: totals.knownCalories,
                            isComplete: totals.caloriesIsComplete
                        ))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        Text("千卡")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    macro(
                        "碳水",
                        exact: totals.carbs,
                        known: totals.knownCarbs,
                        isComplete: totals.carbsIsComplete
                    )
                    macro(
                        "蛋白质",
                        exact: totals.protein,
                        known: totals.knownProtein,
                        isComplete: totals.proteinIsComplete
                    )
                    macro(
                        "脂肪",
                        exact: totals.fat,
                        known: totals.knownFat,
                        isComplete: totals.fatIsComplete
                    )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("升糖速度估算")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(glycemicSpeed?.displayName ?? "证据不足")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
                if !glycemicAssessment.isEmpty {
                    ExpandableMealAssessment(text: glycemicAssessment)
                }
                if !recommendedEatingOrder.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("建议食用顺序", systemImage: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(recommendedEatingOrder)
                            .font(.caption.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("基于食物组成的定性估算，不代表你的实际血糖反应。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button {
                    showsDetail = true
                } label: {
                    Text("查看详情")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            AppTheme.mealSoftTint,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .foregroundStyle(AppTheme.mealAccent)
                }
                .buttonStyle(.plain)
                .navigationDestination(isPresented: $showsDetail) {
                    MealRecordDetailView(meal: meal)
                }
            }
        }
    }

    private var header: String {
        let time = meal.date.formatted(
            .dateTime.month().day().hour().minute()
        )
        return "\(mealType.rawValue) · \(time) · \(itemCount) 项菜品"
    }

    private func macro(
        _ title: String,
        exact: Double?,
        known: Double?,
        isComplete: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(displayValue(exact: exact, known: known, isComplete: isComplete)) 克")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func displayValue<T: BinaryInteger>(
        exact: T?,
        known: T?,
        isComplete: Bool
    ) -> String {
        guard let value = exact ?? known else { return "—" }
        return "\(isComplete ? "" : "≥")\(value)"
    }

    private func displayValue(
        exact: Double?,
        known: Double?,
        isComplete: Bool
    ) -> String {
        guard let value = exact ?? known else { return "—" }
        let formatted = value.formatted(
            .number.precision(.fractionLength(0 ... 1))
        )
        return "\(isComplete ? "" : "≥")\(formatted)"
    }
}

private struct ExpandableMealAssessment: View {
    let text: String
    @State private var isExpanded = false

    private var needsExpansion: Bool {
        text.split(whereSeparator: \.isNewline).count > 5 || text.count > 140
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 5)
            if needsExpansion {
                Button(isExpanded ? "收起" : "展开") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.tint)
                .accessibilityHint(isExpanded ? "收起到五行" : "显示完整饮食评价")
            }
        }
    }
}
