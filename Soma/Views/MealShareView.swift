import SwiftUI

struct MealShareButton: View {
    let meal: MealEntry
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            Label("分享饮食记录", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
        .sheet(isPresented: $presented) { MealShareView(meal: meal) }
    }
}

private struct MealShareView: View {
    let meal: MealEntry
    @Environment(\.dismiss) private var dismiss
    @State private var showsDate = true
    @State private var showsPhoto = false
    @State private var photo: UIImage?
    @State private var error: String?
    @State private var export: UIImage?

    private var photoURL: URL? {
        MediaStore.url(at: meal.mediaAttachments.first { $0.kind == .image }?.path)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let export {
                        Image(uiImage: export).resizable().scaledToFit()
                            .accessibilityLabel("饮食分享预览，" + meal.title)
                    }
                    Toggle("显示日期", isOn: $showsDate).appToggleStyle()
                    if photoURL != nil {
                        Toggle("显示餐图", isOn: $showsPhoto).appToggleStyle()
                    }
                    if let error {
                        Text(error).font(.footnote)
                    }
                }
                .padding()
            }
            .appPageBackground()
            .navigationTitle("分享饮食").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if let export {
                        let image = Image(uiImage: export)
                        ShareLink(item: image, preview: SharePreview("饮食记录", image: image)) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task(id: [showsDate, showsPhoto]) {
                error = nil
                export = nil
                if showsPhoto, photo == nil, let photoURL {
                    let bytes = await Task.detached { try? Data(contentsOf: photoURL) }.value
                    guard !Task.isCancelled else { return }
                    photo = bytes.flatMap { UIImage(data: $0) }
                    if photo == nil {
                        error = "餐图暂时无法读取。"; showsPhoto = false; return
                    }
                }
                let renderer = ImageRenderer(content: MealSharePoster(meal: meal, showsDate: showsDate, photo: showsPhoto ? photo : nil)
                    .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .large))
                renderer.scale = 3
                export = renderer.uiImage
                if export == nil {
                    error = "分享图生成失败，请重新打开预览。"
                }
            }
        }
    }
}

private struct MealSharePoster: View {
    let meal: MealEntry
    let showsDate: Bool
    let photo: UIImage?

    var body: some View {
        let items = meal.items
        let totals = items.isEmpty ? nil : MealNutritionTotals.derive(from: items)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(meal.mealType.rawValue, systemImage: meal.mealType.icon).foregroundStyle(AppTheme.mealAccent)
                Spacer()
                if showsDate {
                    Text(meal.date.formatted(.dateTime.year().month().day())).font(.caption)
                }
            }
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill().frame(width: 332, height: 222).clipped()
            }
            Text(meal.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name)
                    Spacer()
                    if let portion = item.portionDescription {
                        Text(portion).font(.subheadline)
                    }
                }
            }
            Divider()
            if let kcal = items.isEmpty ? meal.calories : totals?.knownCalories {
                Text("\(meal.nutritionSource == .aiEstimate ? "约 " : "")\(kcal) kcal").font(.headline)
            }
            let macros: [(String, Double?)] = [
                ("蛋白质", items.isEmpty ? meal.protein : totals?.knownProtein),
                ("碳水", items.isEmpty ? meal.carbs : totals?.knownCarbs),
                ("脂肪", items.isEmpty ? meal.fat : totals?.knownFat)
            ]
            Text(macros.compactMap { name, value in value.map { "\(name) \($0.formatted(.number.precision(.fractionLength(0 ... 1)))) g" } }
                .joined(separator: "  ·  ")).font(.footnote)
            if let totals, !totals.caloriesIsComplete || !totals.proteinIsComplete || !totals.carbsIsComplete || !totals.fatIsComplete {
                Text("部分记录").font(.caption)
            }
            Text("Soma").font(.caption.weight(.medium))
        }
        .padding(24).frame(width: 380, alignment: .leading)
        .foregroundStyle(.black).background(.white)
    }
}
