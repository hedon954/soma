import CoreData
import Foundation
import SQLite3
import SwiftData

enum SomaMigrationDiagnostics {
    static func report(
        error: Error,
        context: String,
        origin: String,
        isStoredInMemoryOnly: Bool,
        demoContainerPresent: Bool,
        personalContainerPresent: Bool,
        storeURLs: [URL]? = nil
    ) -> String {
        var lines: [String] = [
            "=== Soma 迁移诊断 ===",
            "警告：含训练记录结构样例（动作名、projection key、ID、组次数重量）。",
            "不含身体测量、饮食原文、聊天正文、媒体文件和密钥。请勿发到公开 Issue。",
            "生成时间：\(iso8601.string(from: Date()))",
            "来源：\(origin)",
            "上下文：\(context)",
            "App：\(bundleValue("CFBundleShortVersionString")) (\(bundleValue("CFBundleVersion"))) \(bundleValue("CFBundleIdentifier"))",
            "系统：\(ProcessInfo.processInfo.operatingSystemVersionString)",
            "设备：\(machineIdentifier())",
            "内存库：\(isStoredInMemoryOnly)",
            "演示容器已打开：\(demoContainerPresent)",
            "个人容器已打开：\(personalContainerPresent)",
            "当前 schemaVersion：\(SomaDataMigration.currentVersion)",
            "",
            "--- 错误 ---"
        ]
        lines.append(contentsOf: describeError(error, prefix: "Error"))
        lines.append("")
        lines.append("--- 堆栈 ---")
        lines.append(contentsOf: Thread.callStackSymbols)
        lines.append("")
        lines.append("--- 返回地址 ---")
        lines.append(
            Thread.callStackReturnAddresses
                .map { String(format: "0x%llx", $0.uintValue) }
                .joined(separator: " ")
        )

        if !isStoredInMemoryOnly {
            lines.append("")
            lines.append("--- 本地库文件 ---")
            let urls = storeURLs ?? defaultStoreURLs()
            lines.append(contentsOf: describeFiles(around: urls))
            for storeURL in urls where storeURL.pathExtension == "store" {
                lines.append("")
                lines.append("--- SQLite \(storeURL.lastPathComponent) ---")
                lines.append(contentsOf: SomaStoreDiagnostics.inspect(at: storeURL))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func describeError(_ error: Error, prefix: String) -> [String] {
        var lines = [
            "\(prefix)Type：\(String(describing: type(of: error)))",
            "\(prefix)Describing：\(truncate(String(describing: error)))",
            "\(prefix)Reflecting：\(truncate(String(reflecting: error)))",
            "\(prefix)Localized：\(truncate(error.localizedDescription))"
        ]
        if let localized = error as? LocalizedError {
            if let value = localized.errorDescription {
                lines.append("\(prefix)ErrorDescription：\(truncate(value))")
            }
            if let value = localized.failureReason {
                lines.append("\(prefix)FailureReason：\(truncate(value))")
            }
            if let value = localized.recoverySuggestion {
                lines.append("\(prefix)RecoverySuggestion：\(truncate(value))")
            }
            if let value = localized.helpAnchor {
                lines.append("\(prefix)HelpAnchor：\(truncate(value))")
            }
        }
        if let migration = error as? DataMigrationError {
            switch migration {
            case let .stepFailed(step, underlying):
                lines.append("\(prefix)MigrationStep：\(step)")
                lines.append(contentsOf: describeError(underlying, prefix: "\(prefix).Step"))
            case let .markerVerificationFailed(space):
                lines.append("\(prefix)MarkerSpace：\(space.rawValue)")
            case let .invalidTrainingSnapshot(kind, id):
                lines.append("\(prefix)SnapshotKind：\(kind)")
                lines.append("\(prefix)SnapshotID：\(id.uuidString)")
            }
        }
        if let preflight = error as? SomaStorePreflightError {
            lines.append("\(prefix)Preflight：\(String(describing: preflight))")
        }
        if let swiftData = error as? SwiftDataError {
            lines.append("\(prefix)SwiftDataError：\(truncate(String(reflecting: swiftData)))")
        }

        var dumpOutput = ""
        dump(error, to: &dumpOutput, name: prefix, indent: 0, maxDepth: 8, maxItems: 40)
        for line in dumpOutput.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append("\(prefix)Dump：\(truncate(String(line)))")
        }

        let mirror = Mirror(reflecting: error)
        lines.append("\(prefix)MirrorDisplay：\(String(describing: mirror.displayStyle))")
        for child in mirror.children.prefix(40) {
            let label = child.label ?? "_"
            lines.append(
                "\(prefix)Mirror.\(label)：\(truncate(describeValue(child.value, depth: 0)))"
            )
        }

        let nsError = error as NSError
        lines.append("\(prefix)NSDomain：\(nsError.domain)")
        lines.append("\(prefix)NSCode：\(nsError.code)")
        lines.append(
            "\(prefix)NSKeys：\(Array(nsError.userInfo.keys.map { String(describing: $0) }).sorted())"
        )
        for key in nsError.userInfo.keys.map({ String(describing: $0) }).sorted() {
            guard let value = nsError.userInfo[key] else { continue }
            lines.append(
                "\(prefix)NSUserInfo.\(key)：\(truncate(describeValue(value, depth: 0)))"
            )
        }
        return lines
    }

    private static func describeValue(_ value: Any, depth: Int) -> String {
        if depth > 6 {
            return "<max-depth \(type(of: value))>"
        }
        if let error = value as? Error, depth > 0 {
            return describeError(error, prefix: "Nested").joined(separator: " | ")
        }
        if let object = value as? NSManagedObject {
            return "NSManagedObject entity=\(object.entity.name ?? "?") id=\(object.objectID)"
        }
        if let data = value as? Data {
            return "Data(count=\(data.count), hexPrefix=\(data.prefix(16).map { String(format: "%02x", $0) }.joined()))"
        }
        if let url = value as? URL {
            return url.path
        }
        if let date = value as? Date {
            return iso8601.string(from: date)
        }
        if value is NSNull {
            return "NSNull"
        }
        if let array = value as? [Any] {
            let items = array.prefix(20).enumerated().map { index, item in
                "[\(index)]=\(describeValue(item, depth: depth + 1))"
            }
            let suffix = array.count > 20 ? " … +\(array.count - 20)" : ""
            return "Array(\(array.count)) { \(items.joined(separator: "; "))\(suffix) }"
        }
        if let dictionary = value as? [String: Any] {
            let items = dictionary.keys.sorted().prefix(30).map { key in
                "\(key)=\(describeValue(dictionary[key] as Any, depth: depth + 1))"
            }
            return "Dict(\(dictionary.count)) { \(items.joined(separator: "; ")) }"
        }
        if let dictionary = value as? [AnyHashable: Any] {
            let items = dictionary.keys.map { String(describing: $0) }.sorted().prefix(30).map { key in
                let raw = dictionary.first { String(describing: $0.key) == key }?.value
                return "\(key)=\(describeValue(raw as Any, depth: depth + 1))"
            }
            return "Dict(\(dictionary.count)) { \(items.joined(separator: "; ")) }"
        }
        if let string = value as? String {
            return redactSecret(truncate(string, limit: 400))
        }
        return redactSecret(truncate(String(describing: value), limit: 400))
    }

    private static func describeFiles(around storeURLs: [URL]) -> [String] {
        var lines: [String] = []
        var seen = Set<String>()
        for storeURL in storeURLs {
            let directory = storeURL.deletingLastPathComponent()
            guard seen.insert(directory.path).inserted else { continue }
            lines.append("目录：\(directory.path)")
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let relevant = contents.filter { url in
                let name = url.lastPathComponent
                return name.hasSuffix(".store")
                    || name.hasSuffix(".store-wal")
                    || name.hasSuffix(".store-shm")
                    || name.hasSuffix(".sqlite")
                    || name.contains("soma-migration-recovery")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if relevant.isEmpty {
                lines.append("相关文件：无")
            }
            for url in relevant {
                lines.append(fileLine(url))
            }
            let backupRoot = directory.appendingPathComponent(".soma-migration-recovery")
            if FileManager.default.fileExists(atPath: backupRoot.path) {
                let backups = (try? FileManager.default.contentsOfDirectory(
                    at: backupRoot,
                    includingPropertiesForKeys: nil
                )) ?? []
                lines.append("恢复备份目录数：\(backups.count)")
            }
        }
        for url in storeURLs {
            lines.append(fileLine(url))
        }
        return lines
    }

    private static func fileLine(_ url: URL) -> String {
        var values: URLResourceValues?
        do {
            values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .isRegularFileKey
            ])
        } catch {
            return "文件：\(url.lastPathComponent) 无法读取（\(error.localizedDescription)）"
        }
        guard values?.isRegularFile == true else {
            return "文件：\(url.lastPathComponent) 不存在"
        }
        let size = values?.fileSize ?? 0
        let modified = values?.contentModificationDate.map { iso8601.string(from: $0) } ?? "?"
        return "文件：\(url.lastPathComponent) size=\(size) mtime=\(modified)"
    }

    private static func defaultStoreURLs() -> [URL] {
        let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        guard let directory else { return [] }
        return [
            directory.appendingPathComponent("default.store"),
            directory.appendingPathComponent("PersonalData.store")
        ]
    }

    private static func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key).map { String(describing: $0) } ?? "?"
    }

    private static func machineIdentifier() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    private static func redactSecret(_ text: String) -> String {
        let markers = ["sk-", "Bearer ", "AIza", "-----BEGIN", "api_key", "apikey"]
        if markers.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return "<redacted-secret len=\(text.count)>"
        }
        return text
    }

    private static func truncate(_ text: String, limit: Int = 800) -> String {
        if text.count <= limit {
            return text
        }
        return String(text.prefix(limit)) + "… <len=\(text.count)>"
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
