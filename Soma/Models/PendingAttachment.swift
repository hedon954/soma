import Foundation

struct PendingAttachment: Identifiable {
    let id = UUID()
    let kind: MediaKind
    let imageData: Data?
    let videoURL: URL?

    init(
        kind: MediaKind,
        imageData: Data? = nil,
        videoURL: URL? = nil
    ) {
        self.kind = kind
        self.imageData = imageData
        self.videoURL = videoURL
    }

    init(_ media: PickedMedia) {
        switch media {
        case let .image(data):
            kind = .image
            imageData = data
            videoURL = nil
        case let .video(url):
            kind = .video
            imageData = nil
            videoURL = url
        }
    }
}
