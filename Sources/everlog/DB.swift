// SQLite reader for the Hummingbird (Everlog) database.
//
// All operations are read-only. The live DB is copied to /tmp/ before
// querying to avoid WAL/lock conflicts with the running Everlog.app.
// We bind the system sqlite3 (linked in Package.swift) — no dependency.

import Foundation
import SQLite3

// SQLite expects these C bind destructors at non-static memory addresses.
let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

enum DBError: Error, CustomStringConvertible {
    case databaseMissing(URL)
    case openFailed(String)
    case prepareFailed(String)

    var description: String {
        switch self {
        case .databaseMissing(let url):
            return """
            Everlog database not found at \(url.path).
            Is Everlog installed and has it synced at least once on this Mac?
            """
        case .openFailed(let msg): return "Could not open SQLite: \(msg)"
        case .prepareFailed(let msg): return "SQLite prepare failed: \(msg)"
        }
    }
}

// Foundation's Date(timeIntervalSinceReferenceDate:) already uses the Cocoa
// epoch (2001-01-01) — same units as Hummingbird's ZDATE columns. No offset
// needed, unlike the Python port.

enum DB {
    static var groupContainer: URL {
        if let override = ProcessInfo.processInfo.environment["EVERLOG_GROUP_CONTAINER"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.hummingbird", isDirectory: true)
    }

    static var snapshotPath: URL {
        if let override = ProcessInfo.processInfo.environment["EVERLOG_DB"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: "/tmp/everlog-ro.sqlite")
    }

    /// Copy the live SQLite (and WAL/SHM sidecars) to a /tmp/ working file,
    /// then open it read-only.
    static func open() throws -> OpaquePointer {
        let src = groupContainer.appendingPathComponent("Hummingbird.sqlite")
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw DBError.databaseMissing(src)
        }

        let dst = snapshotPath
        let fm = FileManager.default
        try? fm.removeItem(at: dst)
        try fm.copyItem(at: src, to: dst)
        for ext in ["-wal", "-shm"] {
            let s = URL(fileURLWithPath: src.path + ext)
            let d = URL(fileURLWithPath: dst.path + ext)
            if fm.fileExists(atPath: s.path) {
                try? fm.removeItem(at: d)
                try? fm.copyItem(at: s, to: d)
            }
        }
        // Entries can be sensitive — tighten perms on the copy
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dst.path)

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(dst.path, &db, flags, nil) == SQLITE_OK, let handle = db else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw DBError.openFailed(msg)
        }
        return handle
    }

    static func close(_ db: OpaquePointer) {
        sqlite3_close(db)
    }

    /// Open the live database directly (no snapshot copy). Used by `everlog watch`
    /// for low-overhead polling. SQLite WAL mode lets us read concurrently while
    /// Everlog writes — each query starts a fresh read transaction.
    static func openLive() throws -> OpaquePointer {
        let src = groupContainer.appendingPathComponent("Hummingbird.sqlite")
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw DBError.databaseMissing(src)
        }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(src.path, &db, flags, nil) == SQLITE_OK, let handle = db else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw DBError.openFailed(msg)
        }
        return handle
    }
}

// MARK: - Statement helper

final class Statement {
    private var stmt: OpaquePointer?
    private let db: OpaquePointer

    init(_ db: OpaquePointer, _ sql: String) throws {
        self.db = db
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    deinit {
        sqlite3_finalize(stmt)
    }

    @discardableResult
    func bind(_ index: Int32, _ value: String) -> Self {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        return self
    }

    @discardableResult
    func bind(_ index: Int32, _ value: Int) -> Self {
        sqlite3_bind_int64(stmt, index, Int64(value))
        return self
    }

    @discardableResult
    func bind(_ index: Int32, _ value: Double) -> Self {
        sqlite3_bind_double(stmt, index, value)
        return self
    }

    func step() -> Bool {
        sqlite3_step(stmt) == SQLITE_ROW
    }

    func text(_ col: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: cstr)
    }

    func int(_ col: Int32) -> Int64 {
        sqlite3_column_int64(stmt, col)
    }

    func double(_ col: Int32) -> Double {
        sqlite3_column_double(stmt, col)
    }

    func isNull(_ col: Int32) -> Bool {
        sqlite3_column_type(stmt, col) == SQLITE_NULL
    }
}

// MARK: - Queries

extension DB {
    static func listJournals(_ db: OpaquePointer) throws -> [Journal] {
        let sql = """
        SELECT j.ZNAME, COUNT(e.Z_PK)
        FROM ZJOURNAL j
        LEFT JOIN ZENTRY e ON e.ZJOURNAL = j.Z_PK AND e.ZISTRASHED = 0
        WHERE j.ZISHIDDEN = 0
        GROUP BY j.ZNAME
        ORDER BY 2 DESC
        """
        let stmt = try Statement(db, sql)
        var out: [Journal] = []
        while stmt.step() {
            out.append(Journal(name: stmt.text(0) ?? "", count: Int(stmt.int(1))))
        }
        return out
    }

    static func listTags(_ db: OpaquePointer) throws -> [Tag] {
        let sql = """
        SELECT t.ZTITLE, COUNT(j.Z_17ENTRIES1)
        FROM ZTAG t
        LEFT JOIN Z_17TAGS j ON j.Z_22TAGS = t.Z_PK
        GROUP BY t.ZTITLE
        ORDER BY 2 DESC
        """
        let stmt = try Statement(db, sql)
        var out: [Tag] = []
        while stmt.step() {
            out.append(Tag(name: stmt.text(0) ?? "", count: Int(stmt.int(1))))
        }
        return out
    }

    static func showJournal(_ db: OpaquePointer, journal: String, limit: Int) throws -> [Entry] {
        let sql = """
        SELECT e.ZIDENTIFIER, e.ZDATE, j.ZNAME, e.ZWORDCOUNT, substr(e.ZTEXT, 1, 200)
        FROM ZENTRY e
        JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL
        WHERE j.ZNAME = ?1 AND e.ZISTRASHED = 0
        ORDER BY e.ZDATE DESC
        LIMIT ?2
        """
        let stmt = try Statement(db, sql).bind(1, journal).bind(2, limit)
        return collectEntries(stmt)
    }

    static func search(
        _ db: OpaquePointer,
        query: String,
        journal: String?,
        tag: String?,
        limit: Int
    ) throws -> [Entry] {
        var sql = """
        SELECT DISTINCT e.ZIDENTIFIER, e.ZDATE, j.ZNAME, e.ZWORDCOUNT, substr(e.ZTEXT, 1, 200)
        FROM ZENTRY e
        JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL
        """
        var bindIdx: Int32 = 1
        var tagBind: Int32 = 0
        var queryBind: Int32 = 0
        var journalBind: Int32 = 0
        if tag != nil {
            sql += " JOIN Z_17TAGS jt ON jt.Z_17ENTRIES1 = e.Z_PK"
            sql += " JOIN ZTAG t ON t.Z_PK = jt.Z_22TAGS AND t.ZTITLE = ?\(bindIdx)"
            tagBind = bindIdx
            bindIdx += 1
        }
        sql += " WHERE e.ZISTRASHED = 0 AND e.ZTEXT LIKE ?\(bindIdx)"
        queryBind = bindIdx
        bindIdx += 1
        if journal != nil {
            sql += " AND j.ZNAME = ?\(bindIdx)"
            journalBind = bindIdx
            bindIdx += 1
        }
        sql += " ORDER BY e.ZDATE DESC LIMIT ?\(bindIdx)"
        let limitBind = bindIdx

        let stmt = try Statement(db, sql)
        if let t = tag { stmt.bind(tagBind, t) }
        stmt.bind(queryBind, "%\(query)%")
        if let j = journal { stmt.bind(journalBind, j) }
        stmt.bind(limitBind, limit)
        return collectEntries(stmt)
    }

    static func readEntry(_ db: OpaquePointer, identifierPrefix: String) throws -> Entry? {
        // Allow short prefix matching, like git short SHA
        let sql = """
        SELECT e.ZIDENTIFIER, e.ZDATE, j.ZNAME, e.ZWORDCOUNT, e.ZTEXT,
               e.ZLATITUDE, e.ZLONGITUDE, e.ZISBOOKMARKED
        FROM ZENTRY e
        JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL
        WHERE e.ZIDENTIFIER LIKE ?1 AND e.ZISTRASHED = 0
        LIMIT 1
        """
        let stmt = try Statement(db, sql).bind(1, "\(identifierPrefix)%")
        guard stmt.step() else { return nil }
        let ident = stmt.text(0) ?? ""
        let date = stmt.double(1)
        let journal = stmt.text(2) ?? ""
        let wc = Int(stmt.int(3))
        let text = stmt.text(4) ?? ""
        let lat = stmt.isNull(5) ? nil : stmt.double(5)
        let lng = stmt.isNull(6) ? nil : stmt.double(6)
        let bookmarked = stmt.int(7) == 1

        // Load tags
        let tagSql = """
        SELECT t.ZTITLE
        FROM Z_17TAGS j
        JOIN ZTAG t ON t.Z_PK = j.Z_22TAGS
        JOIN ZENTRY e ON e.Z_PK = j.Z_17ENTRIES1
        WHERE e.ZIDENTIFIER = ?1
        """
        let tagStmt = try Statement(db, tagSql).bind(1, ident)
        var tags: [String] = []
        while tagStmt.step() {
            if let t = tagStmt.text(0) { tags.append(t) }
        }

        let location: Entry.Location? = (lat != nil && lng != nil)
            ? .init(lat: lat!, lng: lng!) : nil

        return Entry(
            identifier: ident,
            date: cocoaToISO(date),
            journal: journal,
            wordcount: wc,
            preview: nil,
            text: text,
            tags: tags,
            location: location,
            bookmarked: bookmarked
        )
    }

    static func onThisDay(_ db: OpaquePointer) throws -> [Entry] {
        // Match month-day in the user's local timezone
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        formatter.timeZone = .current
        let today = formatter.string(from: Date())

        // ZDATE is Cocoa-epoch seconds (matches Date.timeIntervalSinceReferenceDate).
        // Convert to Unix via +978307200 inside SQLite for the date() formatter.
        let sql = """
        SELECT e.ZIDENTIFIER, e.ZDATE, j.ZNAME, e.ZWORDCOUNT, substr(e.ZTEXT, 1, 200)
        FROM ZENTRY e
        JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL
        WHERE e.ZISTRASHED = 0
          AND strftime('%m-%d', datetime(e.ZDATE + 978307200, 'unixepoch')) = ?1
        ORDER BY e.ZDATE DESC
        """
        let stmt = try Statement(db, sql).bind(1, today)
        return collectEntries(stmt)
    }

    static func allEntries(
        _ db: OpaquePointer,
        journal: String? = nil,
        includingTrashed: Bool = false
    ) throws -> [Entry] {
        var sql = """
        SELECT e.ZIDENTIFIER, e.ZDATE, j.ZNAME, e.ZWORDCOUNT, e.ZTEXT,
               e.ZLATITUDE, e.ZLONGITUDE, e.ZISBOOKMARKED, e.Z_PK
        FROM ZENTRY e
        JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL
        """
        var conds: [String] = []
        if !includingTrashed { conds.append("e.ZISTRASHED = 0") }
        if journal != nil { conds.append("j.ZNAME = ?1") }
        if !conds.isEmpty { sql += " WHERE " + conds.joined(separator: " AND ") }
        sql += " ORDER BY e.ZDATE ASC"

        let stmt = try Statement(db, sql)
        if let j = journal { stmt.bind(1, j) }

        var entries: [Entry] = []
        var pks: [String: Int64] = [:]
        while stmt.step() {
            let ident = stmt.text(0) ?? ""
            let lat = stmt.isNull(5) ? nil : stmt.double(5)
            let lng = stmt.isNull(6) ? nil : stmt.double(6)
            let loc: Entry.Location? = (lat != nil && lng != nil) ? .init(lat: lat!, lng: lng!) : nil
            entries.append(Entry(
                identifier: ident,
                date: cocoaToISO(stmt.double(1)),
                journal: stmt.text(2) ?? "",
                wordcount: Int(stmt.int(3)),
                preview: nil,
                text: stmt.text(4),
                tags: [],
                location: loc,
                bookmarked: stmt.int(7) == 1
            ))
            pks[ident] = stmt.int(8)
        }

        // Bulk-load tags per entry (one query, then group)
        let tagSql = """
        SELECT e.ZIDENTIFIER, t.ZTITLE
        FROM Z_17TAGS j
        JOIN ZTAG t ON t.Z_PK = j.Z_22TAGS
        JOIN ZENTRY e ON e.Z_PK = j.Z_17ENTRIES1
        """
        let tagStmt = try Statement(db, tagSql)
        var tagsByEntry: [String: [String]] = [:]
        while tagStmt.step() {
            guard let id = tagStmt.text(0), let tag = tagStmt.text(1) else { continue }
            tagsByEntry[id, default: []].append(tag)
        }

        // Re-emit with tags filled in (Entry is a struct, so build new array)
        return entries.map { e in
            Entry(
                identifier: e.identifier,
                date: e.date,
                journal: e.journal,
                wordcount: e.wordcount,
                preview: e.preview,
                text: e.text,
                tags: (tagsByEntry[e.identifier] ?? []).sorted(),
                location: e.location,
                bookmarked: e.bookmarked
            )
        }
    }

    static func randomEntry(_ db: OpaquePointer, journal: String?) throws -> Entry? {
        var sql = """
        SELECT e.ZIDENTIFIER, e.ZDATE, j.ZNAME, e.ZWORDCOUNT, substr(e.ZTEXT, 1, 400)
        FROM ZENTRY e
        JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL
        WHERE e.ZISTRASHED = 0 AND e.ZTEXT IS NOT NULL AND length(e.ZTEXT) > 50
        """
        if journal != nil {
            sql += " AND j.ZNAME = ?1"
        }
        sql += " ORDER BY RANDOM() LIMIT 1"
        let stmt = try Statement(db, sql)
        if let j = journal { stmt.bind(1, j) }
        guard stmt.step() else { return nil }
        return Entry(
            identifier: stmt.text(0) ?? "",
            date: cocoaToISO(stmt.double(1)),
            journal: stmt.text(2) ?? "",
            wordcount: Int(stmt.int(3)),
            preview: stmt.text(4),
            text: nil,
            tags: [],
            location: nil,
            bookmarked: false
        )
    }

    // MARK: - helpers

    private static func collectEntries(_ stmt: Statement) -> [Entry] {
        var out: [Entry] = []
        while stmt.step() {
            out.append(Entry(
                identifier: stmt.text(0) ?? "",
                date: cocoaToISO(stmt.double(1)),
                journal: stmt.text(2) ?? "",
                wordcount: Int(stmt.int(3)),
                preview: stmt.text(4),
                text: nil,
                tags: [],
                location: nil,
                bookmarked: false
            ))
        }
        return out
    }

    // MARK: - Watch support

    static func maxEntryPK(_ db: OpaquePointer) throws -> Int64 {
        let stmt = try Statement(db, "SELECT COALESCE(MAX(Z_PK), 0) FROM ZENTRY WHERE ZISTRASHED = 0")
        guard stmt.step() else { return 0 }
        return stmt.int(0)
    }

    /// Returns entries with `Z_PK > pk`, oldest-first, suitable for tailing. Each tuple
    /// pairs the user-facing Entry with its internal Z_PK so the caller can advance
    /// `lastSeen` across polls.
    static func entriesAfterWithPKs(
        _ db: OpaquePointer,
        pk: Int64,
        journal: String? = nil
    ) throws -> [(Entry, Int64)] {
        var sql = """
        SELECT e.ZIDENTIFIER, e.ZDATE, j.ZNAME, e.ZWORDCOUNT, e.ZTEXT,
               e.ZLATITUDE, e.ZLONGITUDE, e.ZISBOOKMARKED, e.Z_PK
        FROM ZENTRY e
        JOIN ZJOURNAL j ON j.Z_PK = e.ZJOURNAL
        WHERE e.ZISTRASHED = 0 AND e.Z_PK > ?1
        """
        if journal != nil { sql += " AND j.ZNAME = ?2" }
        sql += " ORDER BY e.Z_PK ASC"

        let stmt = try Statement(db, sql).bind(1, Int(pk))
        if let j = journal { stmt.bind(2, j) }

        var out: [(Entry, Int64)] = []
        while stmt.step() {
            let ident = stmt.text(0) ?? ""
            let lat = stmt.isNull(5) ? nil : stmt.double(5)
            let lng = stmt.isNull(6) ? nil : stmt.double(6)
            let loc: Entry.Location? = (lat != nil && lng != nil) ? .init(lat: lat!, lng: lng!) : nil
            let entry = Entry(
                identifier: ident,
                date: cocoaToISO(stmt.double(1)),
                journal: stmt.text(2) ?? "",
                wordcount: Int(stmt.int(3)),
                preview: nil,
                text: stmt.text(4),
                tags: [],
                location: loc,
                bookmarked: stmt.int(7) == 1
            )
            out.append((entry, stmt.int(8)))
        }
        return out
    }

    static func cocoaToISO(_ cocoaTimestamp: Double) -> String {
        let date = Date(timeIntervalSinceReferenceDate: cocoaTimestamp)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
