import CoreData
import XCTest
@testable import everlog

/// Write-path tests. Every test copies the live store (plus WAL/SHM and the
/// AttachmentData store) into a temp directory and points EVERLOG_STORE /
/// EVERLOG_ATTACH_STORE at the copies, so the real store is never touched.
/// Skips silently when Everlog.app or its store aren't on the host (e.g. CI).
final class StoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        let fm = FileManager.default
        let liveStore = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.hummingbird/Hummingbird.sqlite")
        guard fm.fileExists(atPath: liveStore.path) else {
            throw XCTSkip("Hummingbird store not present on this machine.")
        }
        guard fm.fileExists(atPath: "/Applications/Everlog.app/Contents/Resources/Hummingbird.momd") else {
            throw XCTSkip("Everlog.app not installed on this machine.")
        }

        tempDir = fm.temporaryDirectory
            .appendingPathComponent("everlog-store-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let liveDir = liveStore.deletingLastPathComponent()
        for base in ["Hummingbird.sqlite", "AttachmentData.sqlite"] {
            for ext in ["", "-wal", "-shm"] {
                let src = liveDir.appendingPathComponent(base + ext)
                guard fm.fileExists(atPath: src.path) else { continue }
                try fm.copyItem(at: src, to: tempDir.appendingPathComponent(base + ext))
            }
        }
        setenv("EVERLOG_STORE", tempDir.appendingPathComponent("Hummingbird.sqlite").path, 1)
        setenv("EVERLOG_ATTACH_STORE", tempDir.appendingPathComponent("AttachmentData.sqlite").path, 1)
        // Keep test backups away from ~/.everlog-cli/backups so test runs
        // never prune out real pre-write backups of the live store.
        setenv("EVERLOG_BACKUP_DIR", tempDir.appendingPathComponent("backups").path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("EVERLOG_STORE")
        unsetenv("EVERLOG_ATTACH_STORE")
        unsetenv("EVERLOG_BACKUP_DIR")
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func firstJournalName() throws -> String {
        let ctx = try Store.openContext()
        let req = NSFetchRequest<NSManagedObject>(entityName: "Journal")
        req.fetchLimit = 1
        guard let j = try ctx.fetch(req).first,
              let name = j.value(forKey: "name") as? String, !name.isEmpty else {
            throw XCTSkip("No journals in store copy.")
        }
        return name
    }

    func testModelLoadsAndStoreIsCompatible() throws {
        _ = try Store.openContext()
    }

    func testCreateReadBackRoundTrip() throws {
        let journal = try firstJournalName()
        let created = try Store.createEntry(
            body: "round-trip body", journalName: journal,
            tags: ["xctest-tag"], bookmarked: true)

        let ctx = try Store.openContext()
        let entry = try Store.entry(ctx, identifierPrefix: created.identifier)
        XCTAssertEqual(entry.value(forKey: "text") as? String, "round-trip body")
        XCTAssertEqual(entry.value(forKey: "isBookmarked") as? Bool, true)
        XCTAssertEqual(entry.value(forKey: "wordCount") as? Int, 2)
        let tags = entry.value(forKey: "tags") as? Set<NSManagedObject> ?? []
        XCTAssertEqual(tags.compactMap { $0.value(forKey: "title") as? String }, ["xctest-tag"])
        let journalObj = entry.value(forKey: "journal") as? NSManagedObject
        XCTAssertEqual(journalObj?.value(forKey: "name") as? String, journal)
    }

    func testDerivedDateBucketsMatchCalendar() throws {
        let journal = try firstJournalName()
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 1; comps.hour = 12
        let date = Calendar.current.date(from: comps)!
        let created = try Store.createEntry(body: "backdated", journalName: journal, date: date)

        let ctx = try Store.openContext()
        let entry = try Store.entry(ctx, identifierPrefix: created.identifier)
        XCTAssertEqual(entry.value(forKey: "yearMonthDayId") as? Int, 20260801)
        XCTAssertEqual(entry.value(forKey: "yearMonthId") as? Int, 202608)
        XCTAssertEqual(entry.value(forKey: "dayId") as? Int, 1)
    }

    func testAppendUpdatesTextAndWordCount() throws {
        let journal = try firstJournalName()
        let created = try Store.createEntry(body: "one two", journalName: journal)
        _ = try Store.appendText(identifierPrefix: created.identifier, text: "three four five")

        let ctx = try Store.openContext()
        let entry = try Store.entry(ctx, identifierPrefix: created.identifier)
        XCTAssertEqual(entry.value(forKey: "text") as? String, "one two\nthree four five")
        XCTAssertEqual(entry.value(forKey: "wordCount") as? Int, 5)
    }

    func testTrashIsSoftDelete() throws {
        let journal = try firstJournalName()
        let created = try Store.createEntry(body: "to trash", journalName: journal)
        _ = try Store.trashEntry(identifierPrefix: created.identifier)

        let ctx = try Store.openContext()
        let entry = try Store.entry(ctx, identifierPrefix: created.identifier)
        XCTAssertEqual(entry.value(forKey: "isTrashed") as? Bool, true)
        XCTAssertNotNil(entry.value(forKey: "dateTrashed"))
    }

    func testImageAttachmentLandsInBothStores() throws {
        let journal = try firstJournalName()
        let png = tempDir.appendingPathComponent("test.png")
        try Self.tinyPNG().write(to: png)

        let created = try Store.createEntry(
            body: "with image", journalName: journal, imagePaths: [png.path])
        XCTAssertEqual(created.images, 1)

        let ctx = try Store.openContext()
        let entry = try Store.entry(ctx, identifierPrefix: created.identifier)
        let attachments = entry.value(forKey: "attachments") as? Set<NSManagedObject> ?? []
        XCTAssertEqual(attachments.count, 1)
        let attachment = try XCTUnwrap(attachments.first)
        let attachmentID = try XCTUnwrap(attachment.value(forKey: "identifier") as? String)

        let text = try XCTUnwrap(entry.value(forKey: "text") as? String)
        XCTAssertTrue(text.contains("![attachment](\(attachmentID))"))

        let blobReq = NSFetchRequest<NSManagedObject>(entityName: "AttachmentData")
        blobReq.predicate = NSPredicate(format: "identifier == %@", attachmentID)
        let blob = try XCTUnwrap(try ctx.fetch(blobReq).first)
        let data = try XCTUnwrap(blob.value(forKey: "data") as? Data)
        XCTAssertEqual(data, try Self.tinyPNG())
    }

    func testJournalNotFoundThrows() throws {
        XCTAssertThrowsError(
            try Store.createEntry(body: "x", journalName: "no-such-journal-xyz")
        ) { error in
            guard case Store.StoreError.journalNotFound = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    /// 1×1 red PNG, generated deterministically.
    static func tinyPNG() throws -> Data {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
        return Data(base64Encoded: base64)!
    }
}

import CoreData
