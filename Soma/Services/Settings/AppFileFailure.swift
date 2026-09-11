import Foundation

enum AppFileFailure {
    case noSpace, permission, missing, corrupt

    init?(_ error: NSError) {
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, CocoaError.fileWriteOutOfSpace.rawValue),
             (NSPOSIXErrorDomain, Int(POSIXErrorCode.ENOSPC.rawValue)):
            self = .noSpace
        case (NSCocoaErrorDomain, CocoaError.fileReadNoPermission.rawValue),
             (NSCocoaErrorDomain, CocoaError.fileWriteNoPermission.rawValue),
             (NSPOSIXErrorDomain, Int(POSIXErrorCode.EACCES.rawValue)),
             (NSPOSIXErrorDomain, Int(POSIXErrorCode.EPERM.rawValue)):
            self = .permission
        case (NSCocoaErrorDomain, CocoaError.fileNoSuchFile.rawValue),
             (NSCocoaErrorDomain, CocoaError.fileReadNoSuchFile.rawValue),
             (NSPOSIXErrorDomain, Int(POSIXErrorCode.ENOENT.rawValue)):
            self = .missing
        case (NSCocoaErrorDomain, CocoaError.fileReadCorruptFile.rawValue):
            self = .corrupt
        default: return nil
        }
    }

    var cause: String {
        switch self {
        case .noSpace: "设备可用存储空间不足"
        case .permission: "没有访问这个文件或文件夹的权限"
        case .missing: "需要的文件已移动或无法找到"
        case .corrupt: "这个文件的内容已损坏，无法读取"
        }
    }

    var recovery: String {
        switch self {
        case .noSpace: "请在系统设置中释放一些空间后重试。"
        case .permission: "请重新选择位置并允许访问后重试。"
        case .missing: "请重新选择文件后重试。"
        case .corrupt: "请重新选择完整文件或另一份备份。"
        }
    }
}
