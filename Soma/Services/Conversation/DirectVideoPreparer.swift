@preconcurrency import AVFoundation
import Foundation

enum DirectVideoPreparer {
    static func input(
        for sourceURL: URL,
        capability: DirectVideoCapability
    ) async -> AgentVideoInput? {
        let asset = AVURLAsset(url: sourceURL)
        guard !Task.isCancelled, await (try? asset.load(.isPlayable)) == true else { return nil }
        if sourceURL.pathExtension.lowercased() == "mp4",
           let size = try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > 0, size <= capability.maximumRawBytes,
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
        let completed = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                exporter.exportAsynchronously {
                    continuation.resume(returning: sendableExporter.value.status == .completed)
                }
            }
        } onCancel: {
            sendableExporter.value.cancelExport()
        }
        guard !Task.isCancelled,
              completed,
              let size = try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= capability.maximumRawBytes,
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
