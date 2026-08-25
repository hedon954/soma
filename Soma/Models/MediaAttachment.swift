import Foundation

enum MediaKind: String, Codable, Hashable, Sendable {
    case none, image, video
}

struct MediaAttachmentReference: Codable, Hashable, Identifiable, Sendable {
    var kind: MediaKind
    var path: String

    var id: String {
        "\(kind.rawValue):\(path)"
    }
}

enum MediaAttachmentStorage {
    static func encode(_ attachments: [MediaAttachmentReference]) -> Data {
        (try? JSONEncoder().encode(attachments)) ?? Data()
    }

    static func decode(
        _ data: Data,
        legacyKind: MediaKind = .none,
        legacyPath: String? = nil
    ) -> [MediaAttachmentReference] {
        let decoded = (try? JSONDecoder().decode(
            [MediaAttachmentReference].self,
            from: data
        )) ?? []
        if !decoded.isEmpty {
            return decoded
        }
        guard legacyKind != .none, let legacyPath else { return [] }
        return [MediaAttachmentReference(kind: legacyKind, path: legacyPath)]
    }
}
