import SwiftUI
import UIKit

struct ExerciseArtworkView: View {
    let reference: ExerciseImageReference
    var contentMode: ContentMode = .fit

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.08)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(reference.title)
    }

    private var image: UIImage? {
        if let path = reference.localPath {
            return MediaStore.image(at: path)
        }
        guard let resourceName = reference.resourceName else { return nil }
        if let value = UIImage(named: resourceName) {
            return value
        }
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: nil
        ) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

extension ExerciseDefinition {
    var preferredActionIllustration: ExerciseImageReference {
        actionIllustrations.last
            ?? BundledExerciseCatalog.fallbackActionIllustration
    }
}
