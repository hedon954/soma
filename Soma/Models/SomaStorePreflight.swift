import Foundation
import SQLite3

enum SomaStorePreflight {
    static func repairProjectionKeysIfNeeded(at storeURL: URL) throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(storeURL.path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(database)
            throw SomaStorePreflightError.openFailed(message)
        }
        defer { sqlite3_close(database) }
        try execute(database, "PRAGMA busy_timeout = 2000;")

        guard table(database, named: "ZWORKOUTENTRY"),
              column(database, table: "ZWORKOUTENTRY", named: "ZPROJECTIONKEY"),
              column(database, table: "ZWORKOUTENTRY", named: "ZID")
        else {
            return
        }

        try execute(
            database,
            """
            UPDATE ZWORKOUTENTRY
            SET ZPROJECTIONKEY = 'entry:' || lower(
                substr(hex(ZID), 1, 8) || '-' ||
                substr(hex(ZID), 9, 4) || '-' ||
                substr(hex(ZID), 13, 4) || '-' ||
                substr(hex(ZID), 17, 4) || '-' ||
                substr(hex(ZID), 21, 12)
            )
            WHERE ZPROJECTIONKEY IS NULL OR ZPROJECTIONKEY = '';
            """
        )
        try execute(database, "PRAGMA wal_checkpoint(FULL);")
    }

    static func entryKey(fromUUIDBlobHex hex: String) -> String? {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count == 32,
              normalized.allSatisfy(\.isHexDigit)
        else {
            return nil
        }
        let lower = normalized.lowercased()
        let first = String(lower.prefix(8))
        let second = String(lower.dropFirst(8).prefix(4))
        let third = String(lower.dropFirst(12).prefix(4))
        let fourth = String(lower.dropFirst(16).prefix(4))
        let fifth = String(lower.suffix(12))
        return "entry:\(first)-\(second)-\(third)-\(fourth)-\(fifth)"
    }

    private static func table(_ database: OpaquePointer, named name: String) -> Bool {
        columnCount(
            database,
            sql: "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            bind: name
        ) > 0
    }

    private static func column(
        _ database: OpaquePointer,
        table: String,
        named name: String
    ) -> Bool {
        var statement: OpaquePointer?
        let sql = "PRAGMA table_info(\(table))"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let raw = sqlite3_column_text(statement, 1) {
                let columnName = String(cString: raw)
                if columnName == name {
                    return true
                }
            }
        }
        return false
    }

    private static func columnCount(
        _ database: OpaquePointer,
        sql: String,
        bind: String
    ) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, bind, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        return sqlite3_step(statement) == SQLITE_ROW ? 1 : 0
    }

    private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        let sqliteMessage: String
        if let errorMessage {
            sqliteMessage = String(cString: errorMessage)
            sqlite3_free(errorMessage)
        } else {
            sqliteMessage = String(cString: sqlite3_errmsg(database))
        }
        guard status == SQLITE_OK else {
            throw SomaStorePreflightError.execFailed(sqliteMessage)
        }
    }
}

enum SomaStorePreflightError: LocalizedError {
    case openFailed(String)
    case execFailed(String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            "无法打开本地库以补齐训练投影键：\(message)"
        case let .execFailed(message):
            "补齐训练投影键时本地库写入失败：\(message)"
        }
    }
}
