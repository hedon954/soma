import Foundation

/// 历史视频抽帧结果落盘缓存，避免每个 Turn 重复跑 AVAssetImageGenerator。
enum VideoFrameCache {
    private static let subdirectory = "SomaVideoFrames"
    private static let maximumBytes = 80 * 1024 * 1024
    private static let frameCount = 4
    private static let strategyTag = "v1-c4-960"

    struct Key: Hashable {
        var path: String
        var fileSize: Int64
        var modificationTime: TimeInterval
        var strategy: String

        var digest: String {
            let raw = "\(path)|\(fileSize)|\(modificationTime)|\(strategy)"
            return SHA256Lite.hex(raw)
        }
    }

    static func frames(for url: URL) async -> [Data] {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ),
            let size = attributes[.size] as? NSNumber,
            let modified = attributes[.modificationDate] as? Date
        else {
            return await VideoFrameExtractor.frames(from: url, count: frameCount)
        }
        let key = Key(
            path: url.path,
            fileSize: size.int64Value,
            modificationTime: modified.timeIntervalSince1970,
            strategy: strategyTag
        )
        if let cached = load(key: key), !cached.isEmpty {
            touch(key: key)
            return cached
        }
        let frames = await VideoFrameExtractor.frames(from: url, count: frameCount)
        if !frames.isEmpty {
            store(frames, key: key)
        }
        return frames
    }

    private static func directory() throws -> URL {
        let root = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
        let dir = root.appendingPathComponent(subdirectory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    private static func fileURL(for key: Key) throws -> URL {
        try directory().appendingPathComponent("\(key.digest).frames")
    }

    private static func load(key: Key) -> [Data]? {
        guard let url = try? fileURL(for: key),
              let data = try? Data(contentsOf: url),
              let frames = try? JSONDecoder().decode([Data].self, from: data)
        else {
            return nil
        }
        return frames
    }

    private static func store(_ frames: [Data], key: Key) {
        guard let url = try? fileURL(for: key),
              let data = try? JSONEncoder().encode(frames)
        else {
            return
        }
        try? data.write(to: url, options: .atomic)
        enforceBudget()
    }

    private static func touch(key: Key) {
        guard let url = try? fileURL(for: key) else { return }
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
    }

    private static func enforceBudget() {
        guard let dir = try? directory(),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: dir,
                  includingPropertiesForKeys: [
                      .contentModificationDateKey,
                      .fileSizeKey
                  ],
                  options: [.skipsHiddenFiles]
              )
        else {
            return
        }
        struct Entry {
            var url: URL
            var modified: Date
            var size: Int
        }
        var entries: [Entry] = files.compactMap { url in
            let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            )
            return Entry(
                url: url,
                modified: values?.contentModificationDate ?? .distantPast,
                size: values?.fileSize ?? 0
            )
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maximumBytes else { return }
        entries.sort { $0.modified < $1.modified }
        for entry in entries {
            guard total > maximumBytes else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

/// 轻量 hex digest，避免为缓存键引入 CryptoKit 依赖面。
private enum SHA256Lite {
    static func hex(_ string: String) -> String {
        var hash: UInt64 = 1_469_598_103_934_663_560
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        var hash2: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8.reversed() {
            hash2 ^= UInt64(byte)
            hash2 &*= 0x100_0000_01B3
        }
        return String(format: "%016llx%016llx", hash, hash2)
    }
}
