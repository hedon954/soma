import SwiftUI
import UIKit

struct ExerciseArtworkView: View {
    let reference: ExerciseImageReference
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?

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
                    .foregroundStyle(AppTheme.trainingAccent)
            }
        }
        .accessibilityLabel(reference.title)
        .task(id: imageIdentity) {
            image = nil
            let loaded: UIImage? = if let path = reference.localPath {
                await ImagePipeline.shared.image(
                    atStoredPath: path,
                    maxPixelSize: 1024
                )
            } else if let resourceName = reference.resourceName,
                      let url = Bundle.main.url(
                          forResource: resourceName,
                          withExtension: nil
                      )
            {
                await ImagePipeline.shared.image(
                    at: url,
                    cacheKey: "bundle:\(resourceName)",
                    maxPixelSize: 1024
                )
            } else if let resourceName = reference.resourceName {
                UIImage(named: resourceName)
            } else {
                nil
            }
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }

    private var imageIdentity: String {
        reference.localPath ?? reference.resourceName ?? "missing"
    }
}

extension ExerciseDefinition {
    var preferredActionIllustration: ExerciseImageReference {
        actionIllustrations.max { lhs, rhs in
            if lhs.source.displayPriority == rhs.source.displayPriority {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.source.displayPriority < rhs.source.displayPriority
        }
            ?? BundledExerciseCatalog.fallbackActionIllustration
    }
}

private extension ExerciseImageSource {
    /// 用户明确上传永远胜过生成图和内置图；同一来源内部才按更新时间选最新。
    var displayPriority: Int {
        switch self {
        case .generated: 0
        case .bundled: 1
        case .user: 2
        }
    }
}
