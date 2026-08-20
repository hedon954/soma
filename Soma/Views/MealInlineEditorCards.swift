import SwiftData
import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            itemsCard
            MealTotalsCard(
                meal: meal,
                mealType: mealType,
                totals: totals,
                itemCount: drafts.compactMap(\.item).count
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
            isEditable: isEditable,
            onSave: isEditable ? save : nil,
            onDelete: isEditable ? { showsDelete = true } : nil,
            accessory: { mealTypePicker }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if isEditable {
                    ForEach(Array($drafts.enumerated()), id: \.element.id) { index, $draft in
                        if index > 0 {
                            Divider()
                        }
                        MealItemDraftRow(draft: $draft) {
                            drafts.removeAll { $0.id == draft.id }
                        }
                    }
                    Divider()
                    Button {
                        drafts.append(MealItemDraft())
                    } label: {
                        Label("添加菜品", systemImage: "plus.circle")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.tint)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                } else {
                    readOnlyItems
                }
            }
        }
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
                .foregroundStyle(AppTheme.tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AppTheme.tint.opacity(0.12), in: Capsule())
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
        drafts = MealItemDraft.drafts(for: meal)
        sourceMessage?.recordManualCorrection(
            "饮食记录 \(meal.id.uuidString) 已改为 \(mealType.rawValue)，"
                + "\(items.count) 项菜品：\(MealItemDraft.summary(for: items))"
        )
        try? modelContext.save()
        return true
    }

    private func deleteRecord() {
        sourceMessage?.recordManualCorrection(
            "饮食记录 \(meal.id.uuidString) 已由用户删除"
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
                Spacer(minLength: 4)
                calories
            }
        }
    }

    private var name: some View {
        InlineTextValue(
            placeholder: "菜品",
            text: $draft.name,
            font: .footnote.weight(.semibold),
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

    /// 一行排不下时先把份量单独提一行，辅助字号下每项各占一行，避免数字被压成省略号。
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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    portion
                    macros
                }
                VStack(alignment: .leading, spacing: 3) {
                    portion
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        macros
                    }
                }
            }
        }
    }

    private var portion: some View {
        InlineTextValue(
            placeholder: "份量",
            text: $draft.portion,
            font: .caption2,
            tint: .secondary,
            accessibilityTitle: "份量"
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
                    Spacer(minLength: 4)
                    Text(item.calories.map { "\($0) 千卡" } ?? "未估算")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
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
            .foregroundStyle(AppTheme.tint)
            .frame(width: 22, height: 22)
            .background(
                AppTheme.tint.opacity(0.12),
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
    let accessibilityTitle: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 2) {
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(tint)
                .focused($isFocused)
                .fixedSize(horizontal: true, vertical: false)
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
            isFocused ? AppTheme.tint.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(text.isEmpty ? "未填写" : text)
    }
}

/// 只读派生汇总：随第一张卡的草稿实时重算，缺项显示未估算而不是 0。
private struct MealTotalsCard: View {
    let meal: MealEntry
    let mealType: MealType
    let totals: MealNutritionTotals
    let itemCount: Int

    var body: some View {
        InlineRecordShell(
            title: "饮食评价",
            icon: "chart.pie",
            isEditable: false,
            showsLockWhenReadOnly: false
        ) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(header)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(totals.calories.map(String.init) ?? "—")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        Text(totals.calories == nil ? "千卡未估算" : "千卡")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    macro("碳水", totals.carbs)
                    macro("蛋白质", totals.protein)
                    macro("脂肪", totals.fat)
                }
                NavigationLink {
                    MealRecordDetailView(meal: meal)
                } label: {
                    Text("查看详情")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            AppTheme.tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .foregroundStyle(AppTheme.tint)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var header: String {
        let time = meal.date.formatted(
            .dateTime.month().day().hour().minute()
        )
        return "\(mealType.rawValue) · \(time) · \(itemCount) 项菜品"
    }

    private func macro(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map {
                "\($0.formatted(.number.precision(.fractionLength(0 ... 1)))) 克"
            } ?? "未估算")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
