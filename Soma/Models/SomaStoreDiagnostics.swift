import Foundation
import SQLite3

enum SomaStoreDiagnostics {
    static func inspect(at storeURL: URL) -> [String] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return ["文件不存在：\(storeURL.lastPathComponent)"]
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(storeURL.path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(database)
            return ["无法只读打开：\(message)"]
        }
        defer { sqlite3_close(database) }
        _ = execute(database, "PRAGMA busy_timeout = 2000;")

        var lines: [String] = []
        lines.append(contentsOf: pragmaLines(database))
        lines.append("tables：\(joinedQuery(database, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"))")
        lines.append("indexes：")
        lines.append(contentsOf: query(
            database,
            "SELECT IFNULL(name, ''), IFNULL(tbl_name, ''), IFNULL(sql, '') FROM sqlite_master WHERE type = 'index' ORDER BY tbl_name, name"
        ))
        lines.append("table SQL：")
        lines.append(contentsOf: query(
            database,
            """
            SELECT name, sql FROM sqlite_master
            WHERE type = 'table' AND name IN (
                'ZWORKOUTENTRY', 'ZWORKOUTSESSION', 'ZDATAMIGRATIONMARKER',
                'ZBUSINESSIDSEQUENCE', 'ZTEMPLATESETPRESCRIPTION', 'ZWORKOUTEFFORT',
                'ZWORKOUTSET', 'ZEXERCISEPERFORMANCE',
                'Z_METADATA', 'Z_PRIMARYKEY'
            )
            ORDER BY name
            """,
            textLimit: 4000
        ))
        lines.append("row counts：")
        lines.append(contentsOf: tableCounts(database))
        lines.append(contentsOf: inspectMetadata(database))
        lines.append(contentsOf: inspectPrimaryKey(database))
        lines.append(contentsOf: inspectMarker(database))
        lines.append(contentsOf: inspectWorkoutEntries(database))
        lines.append(contentsOf: inspectWorkoutSession(database))
        lines.append(contentsOf: inspectUniqueDuplicates(database))
        return lines
    }

    private static func pragmaLines(_ database: OpaquePointer) -> [String] {
        [
            "journal_mode：\(scalar(database, "PRAGMA journal_mode"))",
            "quick_check：\(scalar(database, "PRAGMA quick_check"))",
            "schema_version：\(scalar(database, "PRAGMA schema_version"))",
            "user_version：\(scalar(database, "PRAGMA user_version"))",
            "page_count：\(scalar(database, "PRAGMA page_count"))",
            "page_size：\(scalar(database, "PRAGMA page_size"))",
            "freelist_count：\(scalar(database, "PRAGMA freelist_count"))",
            "wal_autocheckpoint：\(scalar(database, "PRAGMA wal_autocheckpoint"))"
        ]
    }

    private static func tableCounts(_ database: OpaquePointer) -> [String] {
        let names = query(database, "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'Z%' ORDER BY name")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.map { name in
            let count = scalar(database, "SELECT COUNT(*) FROM \(name)")
            return "\(name)=\(count)"
        }
    }

    private static func inspectMetadata(_ database: OpaquePointer) -> [String] {
        guard tableExists(database, "Z_METADATA") else {
            return ["Z_METADATA：不存在"]
        }
        var lines = ["Z_METADATA："]
        lines.append(contentsOf: query(
            database,
            "SELECT Z_VERSION, Z_UUID, length(Z_PLIST) FROM Z_METADATA"
        ))
        let blobs = blobColumn(database, "SELECT Z_PLIST FROM Z_METADATA LIMIT 1")
        guard let plistData = blobs.first else {
            return lines
        }
        do {
            let object = try PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            )
            guard let dictionary = object as? [String: Any] else {
                lines.append("Z_PLIST：非字典")
                return lines
            }
            for key in dictionary.keys.sorted() {
                if key == "NSStoreModelVersionHashes",
                   let hashes = dictionary[key] as? [String: Data]
                {
                    lines.append("modelHashes：")
                    for entity in hashes.keys.sorted() {
                        let hex = hashes[entity]?.map { String(format: "%02x", $0) }.joined() ?? "?"
                        lines.append("  \(entity)=\(hex)")
                    }
                } else {
                    lines.append("meta.\(key)=\(truncate(String(describing: dictionary[key] ?? "nil")))")
                }
            }
        } catch {
            lines.append("Z_PLIST 解析失败：\(error.localizedDescription)")
        }
        return lines
    }

    private static func inspectPrimaryKey(_ database: OpaquePointer) -> [String] {
        guard tableExists(database, "Z_PRIMARYKEY") else {
            return ["Z_PRIMARYKEY：不存在"]
        }
        var lines = ["Z_PRIMARYKEY："]
        lines.append(contentsOf: query(
            database,
            "SELECT Z_ENT, Z_NAME, Z_SUPER, Z_MAX FROM Z_PRIMARYKEY ORDER BY Z_NAME"
        ))
        return lines
    }

    private static func inspectMarker(_ database: OpaquePointer) -> [String] {
        guard tableExists(database, "ZDATAMIGRATIONMARKER") else {
            return ["ZDATAMIGRATIONMARKER：不存在"]
        }
        let columns = tableColumns(database, "ZDATAMIGRATIONMARKER")
        var lines = ["ZDATAMIGRATIONMARKER 列：\(columns.joined(separator: ", "))"]
        lines.append(contentsOf: query(database, "SELECT * FROM ZDATAMIGRATIONMARKER"))
        return lines
    }

    private static func inspectWorkoutEntries(_ database: OpaquePointer) -> [String] {
        guard tableExists(database, "ZWORKOUTENTRY") else {
            return ["ZWORKOUTENTRY：不存在"]
        }
        let columns = Set(tableColumns(database, "ZWORKOUTENTRY"))
        var lines = [
            "ZWORKOUTENTRY 列：\(tableColumns(database, "ZWORKOUTENTRY").joined(separator: ", "))",
            "ZWORKOUTENTRY 行数：\(scalar(database, "SELECT COUNT(*) FROM ZWORKOUTENTRY"))"
        ]
        if columns.contains("ZPROJECTIONKEY") {
            lines.append(
                "空 projectionKey：\(scalar(database, "SELECT COUNT(*) FROM ZWORKOUTENTRY WHERE ZPROJECTIONKEY IS NULL OR ZPROJECTIONKEY = ''"))"
            )
            lines.append("重复或空 projectionKey：")
            lines.append(contentsOf: query(
                database,
                """
                SELECT IFNULL(ZPROJECTIONKEY, '<NULL>'), COUNT(*)
                FROM ZWORKOUTENTRY
                GROUP BY ZPROJECTIONKEY
                HAVING COUNT(*) > 1 OR ZPROJECTIONKEY IS NULL OR ZPROJECTIONKEY = ''
                ORDER BY COUNT(*) DESC
                LIMIT 40
                """
            ))
        }
        if columns.contains("ZID") {
            lines.append(
                "ZID length 分布：\(joinedQuery(database, "SELECT length(ZID), COUNT(*) FROM ZWORKOUTENTRY GROUP BY length(ZID) ORDER BY 1"))"
            )
        }

        var selectParts: [String] = []
        if columns.contains("Z_PK") {
            selectParts.append("Z_PK")
        }
        if columns.contains("ZID") {
            selectParts.append("hex(ZID)")
            selectParts.append("length(ZID)")
        }
        if columns.contains("ZPROJECTIONKEY") {
            selectParts.append("ZPROJECTIONKEY")
        }
        if columns.contains("ZEXERCISE") {
            selectParts.append("ZEXERCISE")
        }
        if columns.contains("ZDATE") {
            selectParts.append("ZDATE")
        }
        if columns.contains("ZSETS") {
            selectParts.append("ZSETS")
        }
        if columns.contains("ZREPS") {
            selectParts.append("ZREPS")
        }
        if columns.contains("ZWEIGHT") {
            selectParts.append("ZWEIGHT")
        }
        if columns.contains("ZBUSINESSID") {
            selectParts.append("ZBUSINESSID")
        }
        if columns.contains("ZSOURCEPERFORMANCEID") {
            selectParts.append("hex(ZSOURCEPERFORMANCEID)")
        }
        if columns.contains("ZNOTES") {
            selectParts.append("length(ZNOTES)")
        }
        if columns.contains("ZMEDIAPATH") {
            selectParts.append(
                "CASE WHEN ZMEDIAPATH IS NULL OR ZMEDIAPATH = '' THEN 0 ELSE 1 END"
            )
        }
        if !selectParts.isEmpty {
            lines.append("训练记录样例（最多 30 条；NOTES 只给长度，MEDIA 只给是否存在）：")
            lines.append(contentsOf: query(
                database,
                "SELECT \(selectParts.joined(separator: ", ")) FROM ZWORKOUTENTRY ORDER BY Z_PK LIMIT 30"
            ))
        }
        return lines
    }

    private static func inspectWorkoutSession(_ database: OpaquePointer) -> [String] {
        guard tableExists(database, "ZWORKOUTSESSION") else {
            return ["ZWORKOUTSESSION：不存在"]
        }
        let columns = tableColumns(database, "ZWORKOUTSESSION")
        let expected = [
            "ZAUTOMATICRECORDINGPAUSED",
            "ZAUTOMATICRECORDINGPAUSECODERAW",
            "ZAUTOMATICRECORDINGPAUSEREASON"
        ]
        let missing = expected.filter { !columns.contains($0) }
        return [
            "ZWORKOUTSESSION 列：\(columns.joined(separator: ", "))",
            "ZWORKOUTSESSION 行数：\(scalar(database, "SELECT COUNT(*) FROM ZWORKOUTSESSION"))",
            "缺失可选列：\(missing.isEmpty ? "无" : missing.joined(separator: ", "))"
        ]
    }

    private static func inspectUniqueDuplicates(_ database: OpaquePointer) -> [String] {
        let checks: [(table: String, column: String)] = [
            ("ZWORKOUTENTRY", "ZPROJECTIONKEY"),
            ("ZEXERCISEDEFINITION", "ZCANONICALNAMEKEY"),
            ("ZAGENTJOB", "ZCLIENTJOBKEY"),
            ("ZPERSISTENTAGENTEVENT", "ZEVENTKEY"),
            ("ZDATAMIGRATIONMARKER", "ZKEY"),
            ("ZBUSINESSIDSEQUENCE", "ZNAMESPACE")
        ]
        var lines = ["唯一列重复检查："]
        for check in checks {
            guard tableExists(database, check.table),
                  tableColumns(database, check.table).contains(check.column)
            else {
                lines.append("\(check.table).\(check.column)：列不存在")
                continue
            }
            let duplicates = query(
                database,
                """
                SELECT IFNULL(\(check.column), '<NULL>'), COUNT(*)
                FROM \(check.table)
                GROUP BY \(check.column)
                HAVING COUNT(*) > 1
                LIMIT 20
                """
            )
            if duplicates.isEmpty {
                lines.append("\(check.table).\(check.column)：无重复")
            } else {
                lines.append("\(check.table).\(check.column) 重复：")
                lines.append(contentsOf: duplicates)
            }
        }
        return lines
    }

    private static func tableExists(_ database: OpaquePointer, _ name: String) -> Bool {
        scalar(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '\(name)'"
        ) != "0"
    }

    private static func tableColumns(_ database: OpaquePointer, _ table: String) -> [String] {
        query(database, "PRAGMA table_info(\(table))").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count > 1 else { return nil }
            return String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func joinedQuery(_ database: OpaquePointer, _ sql: String) -> String {
        let rows = query(database, sql)
        return rows.isEmpty ? "<empty>" : rows.joined(separator: " ; ")
    }

    private static func scalar(_ database: OpaquePointer, _ sql: String) -> String {
        query(database, sql).first ?? "<empty>"
    }

    private static func blobColumn(_ database: OpaquePointer, _ sql: String) -> [Data] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        var blobs: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if sqlite3_column_type(statement, 0) == SQLITE_BLOB {
                let bytes = sqlite3_column_bytes(statement, 0)
                if let pointer = sqlite3_column_blob(statement, 0), bytes > 0 {
                    blobs.append(Data(bytes: pointer, count: Int(bytes)))
                }
            }
        }
        return blobs
    }

    private static func query(
        _ database: OpaquePointer,
        _ sql: String,
        textLimit: Int = 240
    ) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return ["SQL 失败：\(String(cString: sqlite3_errmsg(database))) | \(sql)"]
        }
        defer { sqlite3_finalize(statement) }
        var rows: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let count = sqlite3_column_count(statement)
            var parts: [String] = []
            for index in 0 ..< count {
                parts.append(columnValue(statement, index, textLimit: textLimit))
            }
            rows.append(parts.joined(separator: " | "))
            if rows.count >= 80 {
                rows.append("… truncated")
                break
            }
        }
        return rows
    }

    private static func columnValue(
        _ statement: OpaquePointer?,
        _ index: Int32,
        textLimit: Int = 240
    ) -> String {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL:
            return "<NULL>"
        case SQLITE_INTEGER:
            return String(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return String(sqlite3_column_double(statement, index))
        case SQLITE_BLOB:
            let bytes = sqlite3_column_bytes(statement, index)
            if let pointer = sqlite3_column_blob(statement, index), bytes > 0 {
                let data = Data(bytes: pointer, count: min(Int(bytes), 24))
                let hex = data.map { String(format: "%02x", $0) }.joined()
                return "BLOB(len=\(bytes), hexPrefix=\(hex))"
            }
            return "BLOB(len=\(bytes))"
        default:
            if let raw = sqlite3_column_text(statement, index) {
                return truncate(String(cString: raw), limit: textLimit)
            }
            return "<text?>"
        }
    }

    private static func execute(_ database: OpaquePointer, _ sql: String) -> Bool {
        sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    private static func truncate(_ text: String, limit: Int = 400) -> String {
        if text.count <= limit {
            return text
        }
        return String(text.prefix(limit)) + "… <len=\(text.count)>"
    }
}
