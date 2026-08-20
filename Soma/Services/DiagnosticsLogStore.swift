import Foundation
import OSLog

/// ADR 0083：OSLog 只留在本次进程和系统 logd 里，崩溃后无法回读，所以本机再留一份滚动文本
/// 日志。它只记录可解释故障需要的结构化面包屑，密钥类内容恒定脱敏，媒体二进制永不写入。
final class DiagnosticsLogStore: @unchecked Sendable {
    static let shared = DiagnosticsLogStore()

    /// 单个日志文件上限；超过后滚动到 `.1`，总占用不超过两倍。
    private let maximumFileBytes: Int
    private let queue = DispatchQueue(label: "top.hedon.soma.diagnostics-log")
    private let fileManager = FileManager.default
    private let directory: URL
    private let logger = Logger(
        subsystem: "top.hedon.soma",
        category: "Diagnostics"
    )

    init(
        directory: URL? = nil,
        maximumFileBytes: Int = 512 * 1024
    ) {
        self.maximumFileBytes = maximumFileBytes
        if let directory {
            self.directory = directory
        } else {
            let base = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.directory = base.appending(path: "SomaDiagnostics", directoryHint: .isDirectory)
        }
    }

    private var currentURL: URL {
        directory.appending(path: "app-log.txt")
    }

    private var rotatedURL: URL {
        directory.appending(path: "app-log.1.txt")
    }

    func append(
        category: String,
        message: String,
        fields: [String: String] = [:],
        at date: Date = .now
    ) {
        let line = Self.line(
            category: category,
            message: message,
            fields: fields,
            at: date
        )
        queue.async { [weak self] in
            self?.write(line)
        }
    }

    /// 读取最近的日志文本，最多 `maximumBytes`。滚动文件在前，当前文件在后。
    func recentText(maximumBytes: Int = 256 * 1024) -> String {
        queue.sync {
            let rotated = (try? String(contentsOf: rotatedURL, encoding: .utf8)) ?? ""
            let current = (try? String(contentsOf: currentURL, encoding: .utf8)) ?? ""
            let combined = rotated + current
            guard combined.utf8.count > maximumBytes else { return combined }
            let tail = combined.suffix(maximumBytes / 3)
            return "…（更早日志已省略）\n" + String(tail)
        }
    }

    func clear() {
        queue.sync {
            try? fileManager.removeItem(at: currentURL)
            try? fileManager.removeItem(at: rotatedURL)
        }
    }

    /// 供报告拼装读取：日志文件当前占用字节。
    func storedByteCount() -> Int {
        queue.sync {
            byteCount(of: currentURL) + byteCount(of: rotatedURL)
        }
    }

    // MARK: - 纯函数部分（可测试）

    static func line(
        category: String,
        message: String,
        fields: [String: String],
        at date: Date
    ) -> String {
        var parts = [
            Self.timestampFormatter.string(from: date),
            "[\(category)]",
            redact(message)
        ]
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            parts.append("\(key)=\(redact(value))")
        }
        return parts.joined(separator: " ") + "\n"
    }

    /// 密钥、Bearer 头和长随机串恒定脱敏。日志、诊断报告与反馈邮件共用这一条规则。
    static func redact(_ text: String) -> String {
        var output = text
        for pattern in redactionPatterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "[已脱敏]",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return output
    }

    private static let redactionPatterns = [
        #"(?:sk|pk|rk)-[A-Za-z0-9_\-]{8,}"#,
        #"Bearer\s+[A-Za-z0-9._\-]+"#,
        #"(?:api[_\- ]?key|authorization|token|secret|password)\s*[:=]\s*\S+"#,
        #"data:[a-z]+/[a-z0-9.+\-]+;base64,[A-Za-z0-9+/=]+"#
    ]

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter
    }()

    // MARK: - 写入

    private func write(_ line: String) {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            rotateIfNeeded()
            guard let data = line.data(using: .utf8) else { return }
            if fileManager.fileExists(atPath: currentURL.path) {
                let handle = try FileHandle(forWritingTo: currentURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: currentURL, options: .atomic)
            }
        } catch {
            logger.error("诊断日志写入失败 \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rotateIfNeeded() {
        guard byteCount(of: currentURL) >= maximumFileBytes else { return }
        try? fileManager.removeItem(at: rotatedURL)
        try? fileManager.moveItem(at: currentURL, to: rotatedURL)
    }

    private func byteCount(of url: URL) -> Int {
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: url.path
        ) else { return 0 }
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }
}
