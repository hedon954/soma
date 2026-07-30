import Foundation

struct DataBackupCredential: Equatable, Sendable {
    var salt: Data
    var iterations: Int
    var keyData: Data
}

struct DataBackupHeader: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var snapshotSchemaVersion: Int
    var createdAt: Date
    var kdfAlgorithm: String
    var salt: Data
    var iterations: Int
    var keyByteCount: Int
    var encryptionAlgorithm: String
}

struct DataBackupEnvelope: Codable, Equatable, Sendable {
    var snapshot: PersonalDataSnapshot
    var media: [DataBackupMediaDescriptor]
}

struct DataBackupMediaDescriptor: Codable, Equatable, Sendable {
    var logicalPath: String
    var encryptedFilename: String
    var fileExtension: String
    var plaintextByteCount: Int
    var plaintextSHA256: String
}

struct DataBackupCompletion: Codable, Equatable, Sendable {
    var completedAt: Date
    var mediaCount: Int
    var encryptedSnapshotSHA256: String
}

struct DataBackupWriteResult: Equatable, Sendable {
    var directoryURL: URL
    var completedAt: Date
    var modelCount: Int
    var mediaCount: Int
}

struct PreparedDataRestore: Sendable {
    var snapshot: PersonalDataSnapshot
    var mediaPathMapping: [String: String]
    var createdMediaPaths: Set<String>
    var sourceDirectoryURL: URL
}

enum DataArchiveError: LocalizedError {
    case unsupportedSchema(Int)
    case unsupportedBackupFormat(Int)
    case invalidSnapshot
    case invalidBackup
    case invalidPasswordOrCorruptBackup
    case invalidPassword
    case missingMedia
    case noCompleteBackup
    case destinationUnavailable
    case backupNotConfigured
    case backupAlreadyRunning

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "这份备份的数据版本 \(version) 暂不受支持，请先更新 Soma。"
        case let .unsupportedBackupFormat(version):
            "这份备份的文件版本 \(version) 暂不受支持，请先更新 Soma。"
        case .invalidSnapshot, .invalidBackup:
            "备份结构不完整或已经损坏，当前数据没有改变。"
        case .invalidPasswordOrCorruptBackup:
            "密码不正确，或备份内容已经损坏。当前数据没有改变。"
        case .invalidPassword:
            "备份密码至少需要 8 个字符。"
        case .missingMedia:
            "有记录引用的图片或视频已不存在，本次备份未完成。"
        case .noCompleteBackup:
            "所选目录中没有找到完整的 Soma 备份。"
        case .destinationUnavailable:
            "无法访问所选文件夹，请重新选择后再试。"
        case .backupNotConfigured:
            "请先选择备份文件夹并设置密码。"
        case .backupAlreadyRunning:
            "已有备份正在进行，请稍后再试。"
        }
    }
}
