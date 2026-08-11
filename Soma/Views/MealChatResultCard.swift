import SwiftUI

struct MealChatResultCard: View {
    let meal: MealEntry
    @State private var showsAllItems = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                MediaThumbnail(
                    kind: meal.mediaAttachments.first?.kind ?? .none,
                    path: meal.mediaAttachments.first?.path,
                    fallbackIcon: meal.mealType.icon
                )
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(meal.mealType.rawValue) · \(meal.date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(meal.title)
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(meal.calories.map(String.init) ?? "—")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text(meal.calories == nil ? "未估算" : "kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                macro("蛋白质", value: meal.protein)
                macro("碳水", value: meal.carbs)
                macro("脂肪", value: meal.fat)
            }

            if !meal.items.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 14, alignment: .trailing)
                            Text(item.name)
                                .font(.subheadline)
                                .lineLimit(2)
                            Spacer(minLength: 4)
                            if let portion = item.portionDescription {
                                Text(portion)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if meal.items.count > 3 {
                        Button(showsAllItems ? "收起" : "还有 \(meal.items.count - 3) 项") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showsAllItems.toggle()
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }

            NavigationLink {
                MealRecordDetailView(meal: meal)
            } label: {
                Text("查看并编辑")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.tint)
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.tint.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var displayedItems: [MealItem] {
        showsAllItems ? meal.items : Array(meal.items.prefix(3))
    }

    private func macro(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map {
                "\($0.formatted(.number.precision(.fractionLength(0 ... 1)))) g"
            } ?? "—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
