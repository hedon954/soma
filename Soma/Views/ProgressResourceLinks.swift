import SwiftUI

struct ProgressResourceLinks: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: dynamicTypeSize >= .xxLarge ? 2 : 3
            ),
            spacing: 10
        ) {
            link("全部训练", systemImage: "dumbbell.fill", role: .training) {
                WorkoutHistoryView()
            }
            link("全部饮食", systemImage: "fork.knife", role: .meal) {
                MealHistoryView()
            }
            link("身体记录", systemImage: "scalemass.fill", role: .body) {
                BodyHistoryView()
            }
            link("足迹", systemImage: "shoeprints.fill", role: .trend) {
                FootprintsView()
            }
            link("健身房", systemImage: "building.2.fill", role: .training) {
                GymLibraryView()
            }
            link("动作库", systemImage: "figure.strengthtraining.traditional", role: .training) {
                ExerciseLibraryView()
            }
            .accessibilityIdentifier("exercise-library-link")
        }
        .buttonStyle(ProgressResourceButtonStyle())
    }

    private func link(
        _ title: String,
        systemImage: String,
        role: AppSemanticRole,
        @ViewBuilder destination: () -> some View
    ) -> some View {
        NavigationLink(destination: destination) {
            VStack(spacing: 8) {
                SemanticIconBadge(systemImage: systemImage, role: role, size: 36, cornerRadius: 10)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: dynamicTypeSize.isAccessibilitySize)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityLabel(title)
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
