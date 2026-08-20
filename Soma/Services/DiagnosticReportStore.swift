import Foundation

/// ADR 0083：崩溃报告先落盘再发送。发送失败保留在盘上，下次启动继续重试；最多保留 5 份，
/// 避免长期离线堆积。
struct DiagnosticReport: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var createdAt: Date
    var subject: String
    var body: String
    var deliveryAttemptCount: Int
    var lastError: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        subject: String,
        body: String,
        deliveryAttemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.subject = subject
        self.body = body
        self.deliveryAttemptCount = deliveryAttemptCount
        self.lastError = lastError
    }
}

final class DiagnosticReportStore: @unchecked Sendable {
    static let shared = DiagnosticReportStore()
    static let maximumRetainedReports = 5
    /// 超过这个次数不再重试，避免同一份坏报告永久占位。
    static let maximumDeliveryAttempts = 5

    private let directory: URL
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "top.hedon.soma.diagnostic-reports")

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.directory = base.appending(
                path: "SomaDiagnostics/reports",
                directoryHint: .isDirectory
            )
        }
    }

    func save(_ report: DiagnosticReport) {
        queue.sync {
            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            guard let data = try? JSONEncoder().encode(report) else { return }
            try? data.write(to: url(for: report.id), options: .atomic)
            pruneLocked()
        }
    }

    func remove(_ id: UUID) {
        queue.sync {
            try? fileManager.removeItem(at: url(for: id))
        }
    }

    /// 待发送报告，按生成时间正序。
    func pendingReports() -> [DiagnosticReport] {
        queue.sync {
            loadLocked()
        }
    }

    func latestReport() -> DiagnosticReport? {
        queue.sync {
            loadLocked().last
        }
    }

    func removeAll() {
        queue.sync {
            try? fileManager.removeItem(at: directory)
        }
    }

    private func url(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }

    private func loadLocked() -> [DiagnosticReport] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(
                    DiagnosticReport.self,
                    from: data
                )
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func pruneLocked() {
        let reports = loadLocked()
        guard reports.count > Self.maximumRetainedReports else { return }
        for report in reports.prefix(reports.count - Self.maximumRetainedReports) {
            try? fileManager.removeItem(at: url(for: report.id))
        }
    }
}
