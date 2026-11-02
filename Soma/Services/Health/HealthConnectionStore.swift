import Foundation

/// 只保存读取开关；generation 拒绝断开后的迟到连接请求。
actor HealthConnectionStore {
    private let cacheDirectory: URL
    private let connectionDirectory: URL
    private var generation = 0
    private var connected = false
    private var trainingAccessRequested = false

    func hasRequestedTrainingAccess() -> Bool {
        trainingAccessRequested
    }

    init(cacheDirectory: URL? = nil, connectionDirectory: URL? = nil) {
        let manager = FileManager.default
        self.cacheDirectory = cacheDirectory ?? manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "HealthKitDailyActivity/personal", directoryHint: .isDirectory)
        self.connectionDirectory = connectionDirectory ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "HealthKitConnection", directoryHint: .isDirectory)
    }

    func prepare() -> Bool {
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
        let saved = try? Data(contentsOf: connectionDirectory.appending(path: "enabled"))
        connected = saved == Data([1]) || saved == Data([2])
        trainingAccessRequested = saved == Data([2])
        return connected
    }

    @discardableResult
    func setConnected(_ enabled: Bool, generation requested: Int) throws -> Bool {
        guard requested >= generation else { return false }
        generation = requested
        if enabled {
            try write(Data([2]), to: connectionDirectory.appending(path: "enabled"))
            connected = true
            trainingAccessRequested = true
        } else {
            connected = false
            trainingAccessRequested = false
            for directory in [connectionDirectory, cacheDirectory] where FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        return true
    }

    private func write(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        var directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        try directory.setResourceValues(excluded)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var protectedURL = url
        try protectedURL.setResourceValues(excluded)
    }
}
