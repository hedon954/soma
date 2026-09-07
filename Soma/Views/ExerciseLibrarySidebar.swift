import SwiftUI

struct ExerciseLibrarySidebar: View {
    @Binding var filter: ExerciseLibraryFilter
    let classifications: [ExerciseLibraryClassification]
    var onSelection: () -> Void = {}
    @State private var expandedAxis: Axis? = .body
    @State private var expandedRegion: ExerciseBodyRegion?

    private enum Axis: String {
        case body = "身体部位"
        case kind = "动作类型"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                item("全部动作", selected: filter.count == 0, id: "all") {
                    filter = ExerciseLibraryFilter()
                    expandedRegion = nil
                }
                heading(.body)
                if expandedAxis == .body {
                    ForEach(ExerciseBodyRegion.allCases) { region in
                        item(region.rawValue, selected: filter.region == region && filter.muscle == nil,
                             id: "region-\(region.rawValue)", depth: 1,
                             expanded: expandedRegion == region)
                        {
                            filter = ExerciseLibraryFilter(region: region)
                            expandedRegion = expandedRegion == region ? nil : region
                        }
                        if expandedRegion == region {
                            ForEach(muscles(in: region), id: \.self) { muscle in
                                item(muscle, selected: filter.region == region && filter.muscle == muscle,
                                     id: "region-muscle-\(muscle)", depth: 2)
                                {
                                    filter = ExerciseLibraryFilter(region: region, muscle: muscle, primaryOnly: true)
                                }
                            }
                        }
                    }
                }
                heading(.kind)
                if expandedAxis == .kind {
                    ForEach(ExerciseMovementKind.allCases) { kind in
                        item(
                            kind.rawValue,
                            selected: filter.pattern == kind.rawValue,
                            id: "kind-\(kind.rawValue)",
                            depth: 1
                        ) {
                            filter = ExerciseLibraryFilter(pattern: kind.rawValue)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.cardBackground)
        .accessibilityIdentifier("exercise-library-categories")
    }

    private func heading(_ axis: Axis) -> some View {
        Button {
            onSelection()
            expandedAxis = expandedAxis == axis ? nil : axis
        } label: {
            HStack(spacing: 4) {
                Text(axis.rawValue).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: expandedAxis == axis ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expandedAxis == axis ? "已展开" : "已折叠")
        .accessibilityIdentifier("exercise-category-axis-\(axis.rawValue)")
    }

    private func item(
        _ title: String, selected: Bool, id: String, depth: Int = 0,
        expanded: Bool? = nil, action: @escaping () -> Void
    ) -> some View {
        Button {
            onSelection()
            action()
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: depth == 2 ? 12 : 13, weight: selected ? .medium : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let expanded {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                }
            }
            .foregroundStyle(selected ? AppTheme.accent : .secondary)
            .padding(.leading, depth == 2 ? 22 : 12)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .background(selected ? AppTheme.insetBackground : Color.clear)
            .overlay(alignment: .leading) {
                if selected {
                    Rectangle().fill(AppTheme.accent).frame(width: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("exercise-category-\(id)")
    }

    private func muscles(in region: ExerciseBodyRegion) -> [String] {
        let values = classifications.reduce(into: Set<String>()) { result, item in
            result.formUnion(item.primary.filter { ExerciseBodyRegion.resolve($0) == region })
        }
        return sorted(values)
    }

    private func sorted(_ values: Set<String>) -> [String] {
        values.filter { $0 != ExerciseLibraryClassification.unspecified }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
