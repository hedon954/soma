import AVFoundation
import CryptoKit
import Foundation
import UIKit

enum MediaStore {
    private static let writeLock = NSLock()

    static func saveImage(_ data: Data) throws -> String {
        try save(data: normalizedJPEG(data), extension: "jpg")
    }

    static func saveImageAsync(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try saveImage(data)
        }.value
    }

    static func saveVideo(from source: URL) throws -> String {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let hash = try contentHash(of: source)
        return try writeLock.withLock {
            let directory = try mediaDirectory()
            let destination = contentAddressedURL(
                hash: hash,
                extension: ext,
                in: directory
            )
            if let existing = existingContentURL(hash: hash, in: directory) {
                try FileManager.default.linkItem(at: existing, to: destination)
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }
            return storedPath(for: destination)
        }
    }

    static func saveVideoAsync(from source: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try saveVideo(from: source)
        }.value
    }

    static func image(at path: String?) -> UIImage? {
        guard let url = url(at: path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func url(at path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let original = URL(fileURLWithPath: path)
        if path.hasPrefix("/"), FileManager.default.fileExists(atPath: original.path) {
            return original
        }

        guard let media = try? mediaDirectory() else { return nil }
        let filename = original.lastPathComponent
        let relocated = media.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: relocated.path) ? relocated : nil
    }

    static func saveRestoredMedia(
        _ data: Data,
        fileExtension: String
    ) throws -> String {
        let sanitized = fileExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return try save(
            data: data,
            extension: String((sanitized.isEmpty ? "bin" : sanitized).prefix(10))
        )
    }

    @discardableResult
    static func removeStoredFile(at path: String) -> Bool {
        guard let media = try? mediaDirectory() else { return false }
        let filename = URL(fileURLWithPath: path).lastPathComponent
        guard !filename.isEmpty else { return false }
        let target = media.appending(path: filename)
        guard target.deletingLastPathComponent().standardizedFileURL
            == media.standardizedFileURL,
            FileManager.default.fileExists(atPath: target.path)
        else {
            return false
        }
        do {
            try FileManager.default.removeItem(at: target)
            return true
        } catch {
            return false
        }
    }

    static func allStoredPaths() -> Set<String> {
        guard let media = try? mediaDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: media,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              )
        else {
            return []
        }
        return Set(urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true ? storedPath(for: url) : nil
        })
    }

    static func removeOrphans(
        retaining referencedPaths: Set<String>,
        shouldCancel: () -> Bool = { false }
    ) -> Int {
        let orphanedPaths = orphanedStoredPaths(
            allStoredPaths(),
            retaining: referencedPaths
        )
        var removed = 0
        for path in orphanedPaths.sorted() {
            guard !shouldCancel() else { break }
            removed += removeStoredFile(at: path) ? 1 : 0
        }
        return removed
    }

    /// 保留每个引用的独立路径，但把相同内容换成硬链接。因此删除一条
    /// 记录不会误删其他记录，最后一个链接回收后才释放物理空间。
    static func deduplicateStoredFiles(
        shouldCancel: () -> Bool = { false }
    ) -> Int {
        writeLock.withLock {
            guard let directory = try? mediaDirectory(),
                  let urls = try? FileManager.default.contentsOfDirectory(
                      at: directory,
                      includingPropertiesForKeys: [.isRegularFileKey],
                      options: [.skipsHiddenFiles]
                  )
            else {
                return 0
            }
            var canonicalByHash: [String: URL] = [:]
            var replaced = 0
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard !shouldCancel() else { break }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?
                    .isRegularFile == true,
                    let hash = try? contentHash(of: url)
                else {
                    continue
                }
                guard let canonical = canonicalByHash[hash] else {
                    canonicalByHash[hash] = url
                    continue
                }
                let temporary = directory.appendingPathComponent(
                    ".dedup-\(UUID().uuidString)"
                )
                do {
                    try FileManager.default.linkItem(at: canonical, to: temporary)
                    _ = try FileManager.default.replaceItemAt(
                        url,
                        withItemAt: temporary,
                        backupItemName: nil,
                        options: []
                    )
                    replaced += 1
                } catch {
                    try? FileManager.default.removeItem(at: temporary)
                }
            }
            return replaced
        }
    }

    static func orphanedStoredPaths(
        _ storedPaths: Set<String>,
        retaining referencedPaths: Set<String>
    ) -> Set<String> {
        let retainedNames = Set(
            referencedPaths.map { URL(fileURLWithPath: $0).lastPathComponent }
        )
        return Set(storedPaths.filter {
            !retainedNames.contains(URL(fileURLWithPath: $0).lastPathComponent)
        })
    }

    private static func save(data: Data, extension ext: String) throws -> String {
        let hash = contentHash(of: data)
        return try writeLock.withLock {
            let directory = try mediaDirectory()
            let url = contentAddressedURL(hash: hash, extension: ext, in: directory)
            if let existing = existingContentURL(hash: hash, in: directory) {
                try FileManager.default.linkItem(at: existing, to: url)
            } else {
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            }
            return storedPath(for: url)
        }
    }

    private static func contentAddressedURL(
        hash: String,
        extension ext: String,
        in directory: URL
    ) -> URL {
        directory
            .appendingPathComponent("\(hash)-\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    private static func existingContentURL(hash: String, in directory: URL) -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return urls.first { url in
            url.lastPathComponent.hasPrefix("\(hash)-")
                && (try? url.resourceValues(forKeys: [.isRegularFileKey]))?
                .isRegularFile == true
        }
    }

    private static func contentHash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func contentHash(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func mediaDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let media = root.appendingPathComponent("PrivateMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        return media
    }

    private static func storedPath(for url: URL) -> String {
        "PrivateMedia/\(url.lastPathComponent)"
    }

    private static func normalizedJPEG(_ data: Data) -> Data {
        guard let image = UIImage(data: data),
              let resized = image.preparingThumbnail(of: CGSize(width: 1600, height: 1600)),
              let jpeg = resized.jpegData(compressionQuality: 0.82) else { return data }
        return jpeg
    }
}

enum VideoFrameExtractor {
    static func frames(from url: URL, count: Int = 4) async -> [Data] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              duration.seconds.isFinite,
              duration.seconds > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        var frames: [Data] = []
        for index in 1 ... count {
            let second = duration.seconds * Double(index) / Double(count + 1)
            let time = CMTime(seconds: second, preferredTimescale: 600)
            if let image = try? await generator.image(at: time).image,
               let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.72)
            {
                frames.append(data)
            }
        }
        return frames
    }
}
