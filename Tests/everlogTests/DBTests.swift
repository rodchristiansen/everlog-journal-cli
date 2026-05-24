import XCTest
@testable import everlog

final class DBTests: XCTestCase {
    /// Smoke-test the DB layer against the real Hummingbird SQLite.
    /// Skips silently if Everlog isn't installed on the host (e.g. CI).
    func testListJournalsSmoke() throws {
        let db: OpaquePointer
        do {
            db = try DB.open()
        } catch DBError.databaseMissing {
            throw XCTSkip("Hummingbird DB not present on this machine.")
        }
        defer { DB.close(db) }

        let rows = try DB.listJournals(db)
        // We just check the call succeeds and returns coherent shape.
        if !rows.isEmpty {
            XCTAssertFalse(rows[0].name.isEmpty)
            XCTAssertGreaterThanOrEqual(rows[0].count, 0)
        }
    }

    func testCocoaToISOIsAtEpoch() {
        // Cocoa epoch is 2001-01-01 UTC
        let iso = DB.cocoaToISO(0)
        XCTAssertTrue(iso.hasPrefix("2001-01-01"), "got \(iso)")
    }
}
