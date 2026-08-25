import Foundation

enum DiagnosticReportEvidenceSource: String, Codable, Equatable, Sendable {
    case metricKit = "metrickit"
}

/// ADR 0095：只有带 MetricKit 系统崩溃证据的报告可以落盘并发送。发送失败保留在盘上，
/// 下次启动继续重试；最多保留 5 份，
/// 避免长期离线堆积。
struct DiagnosticReport: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var createdAt: Date
    var subject: String
    var body: String
    var evidenceSource: DiagnosticReportEvidenceSource?
    var deliveryAttemptCount: Int
    var lastError: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        subject: String,
        body: String,
        evidenceSource: DiagnosticReportEvidenceSource? = nil,
        deliveryAttemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.subject = subject
        self.body = body
        self.evidenceSource = evidenceSource
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
    private var cachedReports: [DiagnosticReport]?

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
            cachedReports = nil
            pruneLocked()
        }
    }

    func remove(_ id: UUID) {
        queue.sync {
            try? fileManager.removeItem(at: url(for: id))
            cachedReports?.removeAll { $0.id == id }
        }
    }

    /// 待发送报告，按生成时间正序。
    func pendingReports() -> [DiagnosticReport] {
        queue.sync {
            loadLocked()
        }
    }

    /// 启动和投递路径用异步队列读取，避免最大 5 份大报告的 JSON 解码阻塞 MainActor。
    func pendingReportsAsync() async -> [DiagnosticReport] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.loadLocked())
            }
        }
    }

    func latestReport() -> DiagnosticReport? {
        queue.sync {
            loadLocked().last
        }
    }

    func latestReportAsync() async -> DiagnosticReport? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.loadLocked().last)
            }
        }
    }

    func removeAllAsync() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.removeAllLocked()
                continuation.resume()
            }
        }
    }

    private func url(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }

    private func loadLocked() -> [DiagnosticReport] {
        if let cachedReports {
            return cachedReports
        }
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        let reports: [DiagnosticReport] = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(
                    DiagnosticReport.self,
                    from: data
                )
            }
            .sorted { $0.createdAt < $1.createdAt }
        cachedReports = reports
        return reports
    }

    private func pruneLocked() {
        let reports = loadLocked()
        guard reports.count > Self.maximumRetainedReports else { return }
        for report in reports.prefix(reports.count - Self.maximumRetainedReports) {
            try? fileManager.removeItem(at: url(for: report.id))
        }
        cachedReports = Array(reports.suffix(Self.maximumRetainedReports))
    }

    private func removeAllLocked() {
        try? fileManager.removeItem(at: directory)
        cachedReports = []
    }
}
