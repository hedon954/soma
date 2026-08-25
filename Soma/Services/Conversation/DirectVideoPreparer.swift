@preconcurrency import AVFoundation
import Foundation

enum DirectVideoPreparer {
    static func input(
        for sourceURL: URL,
        capability: DirectVideoCapability
    ) async -> AgentVideoInput? {
        if sourceURL.pathExtension.lowercased() == "mp4",
           let data = try? Data(contentsOf: sourceURL),
           !data.isEmpty,
           data.count <= capability.maximumRawBytes
        {
            return AgentVideoInput(
                data: data,
                mimeType: capability.preferredMIMEType
            )
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetMediumQuality
        ) else {
            return nil
        }
        exporter.outputURL = temporaryURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        let sendableExporter = SendableExportSession(exporter)
        let completed = await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume(
                    returning: sendableExporter.value.status == .completed
                )
            }
        }
        guard completed,
              let data = try? Data(contentsOf: temporaryURL),
              !data.isEmpty,
              data.count <= capability.maximumRawBytes
        else {
            return nil
        }
        return AgentVideoInput(
            data: data,
            mimeType: capability.preferredMIMEType
        )
    }
}

private final class SendableExportSession: @unchecked Sendable {
    let value: AVAssetExportSession

    init(_ value: AVAssetExportSession) {
        self.value = value
    }
}
