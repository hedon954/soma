import SwiftUI

enum ProgressResourceDestination: CaseIterable, Hashable {
    case workouts, meals, body, footprints, gyms, exercises

    var label: (String, String, AppSemanticRole) {
        switch self {
        case .workouts: ("全部训练", "dumbbell.fill", .training)
        case .meals: ("全部饮食", "fork.knife", .meal)
        case .body: ("身体记录", "scalemass.fill", .body)
        case .footprints: ("足迹", "shoeprints.fill", .trend)
        case .gyms: ("健身房", "building.2.fill", .training)
        case .exercises: ("动作库", "figure.strengthtraining.traditional", .training)
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .workouts: WorkoutHistoryView()
        case .meals: MealHistoryView()
        case .body: BodyHistoryView()
        case .footprints: FootprintsView()
        case .gyms: GymLibraryView()
        case .exercises: ExerciseLibraryView()
        }
    }
}

struct ProgressResourceLinks: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let destinations = ProgressResourceDestination.allCases
        let columns = dynamicTypeSize >= .xxLarge ? 2 : 3
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(stride(from: 0, to: destinations.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(destinations[start...].prefix(columns), id: \.self) { destination in
                        link(destination)
                    }
                }
            }
        }
        .buttonStyle(ProgressResourceButtonStyle())
    }

    private func link(_ destination: ProgressResourceDestination) -> some View {
        let (title, systemImage, role) = destination.label
        return NavigationLink(value: destination) {
            VStack(spacing: 8) {
                SemanticIconBadge(systemImage: systemImage, role: role, size: 36, cornerRadius: 10)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accent)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: dynamicTypeSize.isAccessibilitySize)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier(destination == .exercises ? "exercise-library-link" : title)
    }
}

private struct ProgressResourceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                configuration.isPressed ? AppTheme.insetBackground : AppTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }
}
