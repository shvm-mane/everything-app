// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

struct AgentOpenCodeProgress {
    var open: [String: (updated: Int64, length: Int64, changed: Date)] = [:]
    var tail: [(rowid: Int64, id: String)] = []
}

enum AgentOpenCodeReader {
    static let database = "opencode.db"

    static let tailLength = 64
    static let abandoned: TimeInterval = 86_400

    private static let values: [(name: String, path: String)] = [
        ("role", "$.role"), ("parentID", "$.parentID"), ("modelID", "$.modelID"), ("model_id", "$.model_id"),
        ("model", "$.model"), ("tokens", "$.tokens"), ("cost", "$.cost"), ("finish", "$.finish"),
        ("time", "$.time"), ("cwd", "$.path.cwd"), ("status", "$.status"), ("outcome", "$.outcome"),
    ]

    static func modified(_ path: String) -> Date? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        var wal = stat()
        let walModified = stat(path + "-wal", &wal) == 0 ? date(wal.st_mtimespec) : .distantPast
        return max(date(info.st_mtimespec), walModified)
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }

    static func readAppended(_ cursor: AgentLogCursor, since horizon: Date = .distantPast,
                             shouldContinue: () -> Bool = { true }, line: (Data) -> Void) {
        guard shouldContinue() else { return }
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let identity = UInt64(info.st_ino)

        if identity != cursor.identity {
            let replaced = cursor.identity != 0
            cursor.identity = identity
            restart(cursor, announce: replaced, line: line)
        }
        cursor.modified = modified(cursor.path) ?? date(info.st_mtimespec)

        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(cursor.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return
        }
        sqlite3_busy_timeout(db, 2000)

        let version2 = exists(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'session_v2'")
        let messageTable = version2 ? "session_message" : "message"
        let sessionTable = version2 ? "session_v2" : "session"
        if !resumes(db, cursor, table: messageTable) { restart(cursor, announce: true, line: line) }
        let floor = Int64(max(0, horizon.timeIntervalSince1970) * 1000)
        if cursor.offset == 0 {
            let indexed = version2 ? firstIndexedRow(db, since: floor) : nil
            cursor.offset = UInt64(indexed ?? firstRow(db, table: messageTable, since: floor))
        }
        let recent = version2 && floor > 0 ? "m.time_created >= \(floor) AND " : ""

        let hasParentID = exists(db, "SELECT 1 FROM pragma_table_info('\(sessionTable)') WHERE name = 'parent_id'")
        let hasParts = exists(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'part'")
        let role = version2 ? "m.type" : field("m.data", "$.role")

        let toolCalls = version2 ? """
            CASE WHEN \(recent)\(role) = 'assistant'
                AND \(field("m.data", "$.finish")) NOT IN ('tool-calls', 'unknown')
            THEN EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(m.data)
                THEN json_extract(m.data, '$.content') ELSE '[]' END) c
                WHERE json_extract(c.value, '$.type') = 'tool'
                    AND coalesce(json_extract(c.value, '$.executed'), 0) = 0)
            ELSE 0 END
            """ : hasParts ? """
            CASE WHEN \(field("m.data", "$.role")) = 'assistant'
                AND \(field("m.data", "$.finish")) NOT IN ('tool-calls', 'unknown')
            THEN EXISTS (SELECT 1 FROM part p WHERE p.message_id = m.id
                AND \(field("p.data", "$.type")) = 'tool'
                AND coalesce(\(field("p.data", "$.metadata.providerExecuted")), 0) = 0
                AND NOT (coalesce(\(field("p.data", "$.state.status")), '') = 'error'
                    AND coalesce(\(field("p.data", "$.state.metadata.interrupted")), 0) = 1))
            ELSE 0 END
            """ : "0"
        let autoCompaction = !version2 && hasParts ? """
            CASE WHEN \(field("m.data", "$.role")) = 'assistant' AND \(field("m.data", "$.summary")) = 1
            THEN EXISTS (SELECT 1 FROM part p WHERE p.message_id = \(field("m.data", "$.parentID"))
                AND \(field("p.data", "$.type")) = 'compaction' AND \(field("p.data", "$.auto")) = 1)
            ELSE 0 END
            """ : "0"
        let writing = """
            (\(recent)(coalesce(\(role) = 'assistant'
                AND \(field("m.data", "$.time.completed")) IS NULL, 0)
            OR coalesce(\(role) = 'compaction' AND \(field("m.data", "$.status")) = 'running', 0)))
            """
        let parentCol = hasParentID ? "s.parent_id" : "NULL"
        let fields = values.map { "json_extract(m.data, '\($0.path)')" }.joined(separator: ", ")
        let size = recent.isEmpty ? "length(m.data)" : "CASE WHEN \(recent)1 THEN length(m.data) END"
        let select = """
        SELECT m.rowid, m.id, m.session_id, m.time_created, m.time_updated, \(size), s.directory,
            \(parentCol), CASE WHEN \(recent)json_valid(m.data) THEN json_array(\(role), \(fields)) END,
            \(toolCalls), \(autoCompaction), \(writing),
            CASE WHEN \(recent)json_valid(m.data) THEN json_type(m.data, '$.error') END
        FROM \(messageTable) m
        JOIN \(sessionTable) s ON m.session_id = s.id
        """
        let now = Date()

        let open = Array(cursor.openCode.open.keys)
        if !open.isEmpty {
            let marks = Array(repeating: "?", count: open.count).joined(separator: ", ")
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, select + " WHERE m.id IN (\(marks)) ORDER BY m.rowid", -1, &stmt, nil) == SQLITE_OK
            else { return }
            defer { sqlite3_finalize(stmt) }
            for (index, id) in open.enumerated() {
                sqlite3_bind_text(stmt, Int32(index + 1), id, -1, transient)
            }
            var found = Set<String>()
            while shouldContinue() && sqlite3_step(stmt) == SQLITE_ROW {
                guard let id = text(stmt, 1), let known = cursor.openCode.open[id] else { continue }
                found.insert(id)
                let updated = sqlite3_column_int64(stmt, 4)
                let length = sqlite3_column_int64(stmt, 5)
                if updated == known.updated && length == known.length {
                    if now.timeIntervalSince(known.changed) > abandoned { cursor.openCode.open[id] = nil }
                    continue
                }
                handOver(stmt, cursor: cursor, now: now, version2: version2, line: line)
            }
            guard shouldContinue() else { return }
            for id in open where !found.contains(id) { cursor.openCode.open[id] = nil }
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, select + " WHERE m.rowid > ? ORDER BY m.rowid", -1, &stmt, nil) == SQLITE_OK
        else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(cursor.offset))
        while shouldContinue() && sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = sqlite3_column_int64(stmt, 0)
            cursor.offset = UInt64(max(0, rowid))
            if let id = text(stmt, 1) {
                cursor.openCode.tail.append((rowid, id))
                if cursor.openCode.tail.count > tailLength { cursor.openCode.tail.removeFirst() }
            }
            handOver(stmt, cursor: cursor, now: now, version2: version2, line: line)
        }
    }

    private static func handOver(_ stmt: OpaquePointer?, cursor: AgentLogCursor, now: Date, version2: Bool,
                                 line: (Data) -> Void) {
        guard let id = text(stmt, 1), let sessionID = text(stmt, 2),
              sqlite3_column_type(stmt, 3) != SQLITE_NULL else { return }
        let created = sqlite3_column_int64(stmt, 3)
        let updated = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? created : sqlite3_column_int64(stmt, 4)
        if sqlite3_column_int64(stmt, 11) != 0 {
            cursor.openCode.open[id] = (sqlite3_column_int64(stmt, 4), sqlite3_column_int64(stmt, 5), now)
        } else {
            cursor.openCode.open[id] = nil
        }

        guard let extracted = text(stmt, 8),
              let found = (try? JSONSerialization.jsonObject(with: Data(extracted.utf8))) as? [Any],
              found.count == values.count + 1 else { return }
        var json: [String: Any] = [:]
        if !(found[0] is NSNull) { json["role"] = found[0] }
        for (value, read) in zip(values, found.dropFirst()) where !(read is NSNull) { json[value.name] = read }
        if let cwd = json.removeValue(forKey: "cwd") { json["path"] = ["cwd": cwd] }
        json["id"] = id
        json["session_id"] = sessionID
        json["parent_session_id"] = text(stmt, 7) ?? ""
        json["directory"] = text(stmt, 6) ?? ""
        json["time_created"] = created
        json["time_updated"] = updated
        if sqlite3_column_int64(stmt, 9) != 0 { json["tool_calls"] = true }
        if sqlite3_column_int64(stmt, 10) != 0 { json["auto_compaction"] = true }
        if let error = text(stmt, 12), error != "null" { json["error"] = true }
        if version2, json["role"] as? String == "assistant", json["finish"] == nil, json["error"] == nil,
           json["tokens"] == nil, (json["time"] as? [String: Any])?["completed"] != nil { return }
        if version2 { json["version"] = 2 }

        if let mergedData = try? JSONSerialization.data(withJSONObject: json) {
            line(mergedData)
        }
    }

    private static func restart(_ cursor: AgentLogCursor, announce: Bool, line: (Data) -> Void) {
        cursor.offset = 0
        cursor.openCode = AgentOpenCodeProgress()
        cursor.state = AgentLogState()
        if announce {
            line(Data(#"{"type":"reset"}"#.utf8))
        }
    }

    private static func resumes(_ db: OpaquePointer?, _ cursor: AgentLogCursor, table: String) -> Bool {
        let tail = cursor.openCode.tail
        guard !tail.isEmpty else { return true }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id FROM \(table) WHERE rowid = ?", -1, &stmt, nil) == SQLITE_OK else {
            return true
        }
        defer { sqlite3_finalize(stmt) }
        for position in tail.indices.reversed() {
            sqlite3_reset(stmt)
            sqlite3_bind_int64(stmt, 1, tail[position].rowid)
            guard sqlite3_step(stmt) == SQLITE_ROW, text(stmt, 0) == tail[position].id else { continue }
            cursor.offset = UInt64(tail[position].rowid)
            cursor.openCode.tail.removeLast(tail.count - 1 - position)
            return true
        }
        return false
    }

    private static func firstRow(_ db: OpaquePointer?, table: String, since floor: Int64) -> Int64 {
        guard floor > 0 else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT rowid, time_created FROM \(table) WHERE rowid >= ? ORDER BY rowid LIMIT 1",
                                 -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        var last: OpaquePointer?
        var high: Int64 = 0
        if sqlite3_prepare_v2(db, "SELECT max(rowid) FROM \(table)", -1, &last, nil) == SQLITE_OK,
           sqlite3_step(last) == SQLITE_ROW {
            high = sqlite3_column_int64(last, 0)
        }
        sqlite3_finalize(last)
        var low: Int64 = 0
        while low < high {
            let middle = low + (high - low + 1) / 2
            sqlite3_reset(stmt)
            sqlite3_bind_int64(stmt, 1, middle)
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                high = middle - 1
                continue
            }
            let rowid = sqlite3_column_int64(stmt, 0)
            if sqlite3_column_type(stmt, 1) == SQLITE_NULL || sqlite3_column_int64(stmt, 1) < floor {
                low = rowid
            } else {
                high = middle - 1
            }
        }
        return low
    }

    private static func firstIndexedRow(_ db: OpaquePointer?, since floor: Int64) -> Int64? {
        guard floor > 0 else { return 0 }
        var stmt: OpaquePointer?
        let query = """
            SELECT (SELECT min(rowid) FROM session_message INDEXED BY session_message_time_created_idx
                    WHERE time_created >= ?),
                (SELECT max(rowid) FROM session_message)
            """
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, floor)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return sqlite3_column_int64(stmt, 1) }
        return max(0, sqlite3_column_int64(stmt, 0) - 1)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }

    private static func field(_ column: String, _ path: String) -> String {
        "(CASE WHEN json_valid(\(column)) THEN json_extract(\(column), '\(path)') END)"
    }

    private static func exists(_ db: OpaquePointer?, _ query: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }
}
