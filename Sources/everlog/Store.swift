import CoreData
import Foundation

/// Write-side access to the Hummingbird store via CoreData.
///
/// Reads stay on the snapshot-SQLite path in `DB.swift`. Writes go through
/// Everlog's own compiled model (`Hummingbird.momd`, loaded straight out of
/// the app bundle) against the live group-container store, opened with
/// persistent-history tracking — the same multi-process pattern Everlog's
/// widget and share extensions use. The app's CloudKit mirror picks our
/// history transactions up and syncs them like any other local edit.
///
/// We never touch the SQLite directly on the write path.
enum Store {
    static let transactionAuthor = "everlog-cli"

    /// Everlog.app location; override with EVERLOG_APP for non-standard installs.
    static var appURL: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["EVERLOG_APP"]
            ?? "/Applications/Everlog.app")
    }

    /// Live store; override with EVERLOG_STORE (tests point this at a copy).
    static var storeURL: URL {
        if let override = ProcessInfo.processInfo.environment["EVERLOG_STORE"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.hummingbird/Hummingbird.sqlite")
    }

    enum StoreError: LocalizedError {
        case modelNotFound(String)
        case incompatibleStore
        case journalNotFound(String)
        case entryNotFound(String)
        case ambiguousEntry(String, Int)

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let path):
                return "Everlog data model not found at \(path). Is Everlog.app installed? (override with EVERLOG_APP)"
            case .incompatibleStore:
                return "The installed Everlog.app model does not match the store — Everlog.app likely needs to launch once to migrate. Refusing to write."
            case .journalNotFound(let name):
                return "Journal not found: \(name). List journals with `everlog journals`."
            case .entryNotFound(let id):
                return "No entry matches identifier: \(id)"
            case .ambiguousEntry(let id, let count):
                return "Identifier prefix \(id) matches \(count) entries — use more characters."
            }
        }
    }

    // MARK: - Stack

    static func loadModel() throws -> NSManagedObjectModel {
        let momd = appURL.appendingPathComponent("Contents/Resources/Hummingbird.momd")
        guard let model = NSManagedObjectModel(contentsOf: momd) else {
            throw StoreError.modelNotFound(momd.path)
        }
        return model
    }

    /// Open the store read-write with history tracking. Refuses to open a
    /// store the bundled model can't represent (never auto-migrate — that is
    /// the app's job).
    static func openContext() throws -> NSManagedObjectContext {
        let model = try loadModel()

        let meta = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite, at: storeURL, options: [NSReadOnlyPersistentStoreOption: true])
        guard model.isConfiguration(withName: nil, compatibleWithStoreMetadata: meta) else {
            throw StoreError.incompatibleStore
        }

        let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
        _ = try psc.addPersistentStore(type: .sqlite, at: storeURL, options: [
            NSPersistentHistoryTrackingKey: true,
            NSMigratePersistentStoresAutomaticallyOption: false,
            NSInferMappingModelAutomaticallyOption: false,
        ])

        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = psc
        ctx.transactionAuthor = transactionAuthor
        return ctx
    }

    // MARK: - Backups

    /// Copy sqlite + WAL + SHM into ~/.everlog-cli/backups/<stamp>/ before a
    /// write session. Keeps the newest `keep` backups.
    @discardableResult
    static func backup(keep: Int = 5) throws -> URL {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".everlog-cli/backups")
        let stampFormatter = DateFormatter()
        stampFormatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        stampFormatter.locale = Locale(identifier: "en_US_POSIX")
        let dir = root.appendingPathComponent(stampFormatter.string(from: Date()))
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        for ext in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: storeURL.path + ext)
            guard fm.fileExists(atPath: src.path) else { continue }
            try fm.copyItem(at: src, to: dir.appendingPathComponent(src.lastPathComponent))
        }

        // prune
        let all = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
            .filter(\.hasDirectoryPath)
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
        for stale in all.dropFirst(keep) {
            try? fm.removeItem(at: stale)
        }
        return dir
    }

    // MARK: - Lookups

    static func journal(_ ctx: NSManagedObjectContext, named name: String) throws -> NSManagedObject {
        let req = NSFetchRequest<NSManagedObject>(entityName: "Journal")
        req.predicate = NSPredicate(format: "name ==[c] %@", name)
        guard let j = try ctx.fetch(req).first else {
            throw StoreError.journalNotFound(name)
        }
        return j
    }

    static func entry(_ ctx: NSManagedObjectContext, identifierPrefix prefix: String) throws -> NSManagedObject {
        let req = NSFetchRequest<NSManagedObject>(entityName: "Entry")
        req.predicate = NSPredicate(format: "identifier BEGINSWITH[c] %@", prefix)
        let matches = try ctx.fetch(req)
        guard let first = matches.first else { throw StoreError.entryNotFound(prefix) }
        guard matches.count == 1 else { throw StoreError.ambiguousEntry(prefix, matches.count) }
        return first
    }

    /// Find a tag by title (case-insensitive) or create it.
    static func tag(_ ctx: NSManagedObjectContext, title: String) throws -> NSManagedObject {
        let req = NSFetchRequest<NSManagedObject>(entityName: "Tag")
        req.predicate = NSPredicate(format: "title ==[c] %@", title)
        if let existing = try ctx.fetch(req).first { return existing }
        let t = NSEntityDescription.insertNewObject(forEntityName: "Tag", into: ctx)
        t.setValue(title, forKey: "title")
        t.setValue(Date(), forKey: "dateCreated")
        return t
    }

    // MARK: - Derived fields

    /// Fill every field the app derives from body + date so its date-bucketed
    /// queries (day/month/year rollups) see our entries exactly like its own.
    static func applyDerivedFields(_ entry: NSManagedObject, body: String, date: Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let dayStart = cal.startOfDay(for: date)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: date))!

        entry.setValue(body, forKey: "text")
        entry.setValue(body, forKey: "content")
        entry.setValue(date, forKey: "date")
        entry.setValue(date, forKey: "sortDate")
        entry.setValue(dayStart, forKey: "day")
        entry.setValue(monthStart, forKey: "month")
        entry.setValue(comps.day!, forKey: "dayId")
        entry.setValue(comps.month!, forKey: "monthId")
        entry.setValue(comps.year!, forKey: "yearId")
        entry.setValue(comps.year! * 100 + comps.month!, forKey: "yearMonthId")
        entry.setValue(comps.year! * 10000 + comps.month! * 100 + comps.day!, forKey: "yearMonthDayId")
        entry.setValue(body.split(whereSeparator: \.isWhitespace).count, forKey: "wordCount")
        entry.setValue(TimeZone.current.secondsFromGMT(for: date) / 60, forKey: "timeZone")
    }

    // MARK: - Write operations

    struct CreatedEntry: Codable {
        let identifier: String
        let date: Date
        let journal: String
        let wordCount: Int
    }

    static func createEntry(
        body: String,
        journalName: String,
        date: Date = Date(),
        tags: [String] = [],
        bookmarked: Bool = false
    ) throws -> CreatedEntry {
        try backup()
        let ctx = try openContext()
        let journal = try Store.journal(ctx, named: journalName)

        let now = Date()
        let entry = NSEntityDescription.insertNewObject(forEntityName: "Entry", into: ctx)
        applyDerivedFields(entry, body: body, date: date)
        entry.setValue(now, forKey: "dateCreated")
        entry.setValue(now, forKey: "dateModified")
        entry.setValue(now, forKey: "textModifiedDate")
        entry.setValue(UUID().uuidString, forKey: "identifier")
        entry.setValue(false, forKey: "isTrashed")
        entry.setValue(bookmarked, forKey: "isBookmarked")
        entry.setValue(false, forKey: "migratedContent")
        entry.setValue(0, forKey: "touch")
        entry.setValue(0, forKey: "app")
        entry.setValue(0.0, forKey: "timeTyping")
        entry.setValue(journal, forKey: "journal")

        if !tags.isEmpty {
            let tagSet = entry.mutableSetValue(forKey: "tags")
            for title in tags {
                tagSet.add(try tag(ctx, title: title))
            }
        }

        try ctx.save()
        return CreatedEntry(
            identifier: entry.value(forKey: "identifier") as! String,
            date: date,
            journal: journalName,
            wordCount: entry.value(forKey: "wordCount") as! Int
        )
    }

    static func appendText(identifierPrefix: String, text: String) throws -> String {
        try backup()
        let ctx = try openContext()
        let entry = try Store.entry(ctx, identifierPrefix: identifierPrefix)
        let existing = entry.value(forKey: "text") as? String ?? ""
        let combined = existing.isEmpty ? text : existing + "\n" + text
        let date = entry.value(forKey: "date") as? Date ?? Date()
        applyDerivedFields(entry, body: combined, date: date)
        entry.setValue(Date(), forKey: "dateModified")
        entry.setValue(Date(), forKey: "textModifiedDate")
        try ctx.save()
        return entry.value(forKey: "identifier") as! String
    }

    static func trashEntry(identifierPrefix: String) throws -> String {
        try backup()
        let ctx = try openContext()
        let entry = try Store.entry(ctx, identifierPrefix: identifierPrefix)
        entry.setValue(true, forKey: "isTrashed")
        entry.setValue(Date(), forKey: "dateTrashed")
        entry.setValue(Date(), forKey: "dateModified")
        try ctx.save()
        return entry.value(forKey: "identifier") as! String
    }
}
