import XCTest
import SQLite3
@testable import Lexvane

final class LexvaneTests: XCTestCase {
    func testAppIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "app.lexvane")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "lexvane")
    }

    func testPersistenceSaveReopenReadAndDelete() throws {
        try withTemporaryDatabase { url in
            let writer = SQLiteProbeStore(fileURL: url)
            XCTAssertNil(try writer.value(forKey: 7))
            try writer.save(key: 7, value: 42)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

            // A different helper and connection must read committed on-disk data.
            let reader = SQLiteProbeStore(fileURL: url)
            XCTAssertEqual(try reader.value(forKey: 7), 42)
            XCTAssertEqual(try rawScalar(url, sql: "PRAGMA user_version"), 1)
            try reader.save(key: 7, value: -99)
            XCTAssertEqual(try writer.value(forKey: 7), -99)
            try reader.delete(key: 7)
            XCTAssertNil(try SQLiteProbeStore(fileURL: url).value(forKey: 7))
            print("Simulator SQLite \(String(cString: sqlite3_libversion())); source ID: \(String(cString: sqlite3_sourceid()))")
        }
    }

    func testPersistenceFailedMigrationPreservesExistingData() throws {
        try withTemporaryDatabase { url in
            // A conflicting unversioned table must fail, not reset existing data.
            try rawExecute(url, sql: "CREATE TABLE probe_values (key INTEGER PRIMARY KEY, value INTEGER NOT NULL); INSERT INTO probe_values VALUES (7, 42)")
            XCTAssertThrowsError(try SQLiteProbeStore(fileURL: url).save(key: 7, value: 99)) { error in
                guard case SQLiteProbeStore.Failure.sqlite = error else {
                    return XCTFail("Expected SQLite migration error, got \(error)")
                }
            }
            XCTAssertEqual(try rawScalar(url, sql: "PRAGMA user_version"), 0)
            XCTAssertEqual(try rawScalar(url, sql: "SELECT value FROM probe_values WHERE key = 7"), 42)
        }
    }

    func testPersistenceRejectsNewerSchemaWithoutDowngrading() throws {
        try withTemporaryDatabase { url in
            try rawExecute(url, sql: "PRAGMA user_version = 2")
            XCTAssertThrowsError(try SQLiteProbeStore(fileURL: url).save(key: 7, value: 42)) { error in
                XCTAssertEqual(error as? SQLiteProbeStore.Failure, .unsupportedSchema(2))
            }
            XCTAssertEqual(try rawScalar(url, sql: "PRAGMA user_version"), 2)
            XCTAssertEqual(try rawScalar(url, sql: "SELECT count(*) FROM sqlite_master WHERE name = 'probe_values'"), 0)
        }
    }

    private func withTemporaryDatabase(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Lexvane-T002-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                XCTFail("Could not clean persistence fixture: \(error)")
            }
        }
        try body(directory.appendingPathComponent("probe.sqlite"))
    }

    private func withRawDatabase<T>(_ url: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        var handle: OpaquePointer?
        let result = sqlite3_open(url.path, &handle)
        let database = try XCTUnwrap(handle)
        defer { sqlite3_close(database) }
        XCTAssertEqual(result, SQLITE_OK)
        return try body(database)
    }

    private func rawExecute(_ url: URL, sql: String) throws {
        try withRawDatabase(url) { database in
            XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(database)))
        }
    }

    private func rawScalar(_ url: URL, sql: String) throws -> Int64 {
        try withRawDatabase(url) { database in
            var handle: OpaquePointer?
            let result = sqlite3_prepare_v2(database, sql, -1, &handle, nil)
            defer { sqlite3_finalize(handle) }
            XCTAssertEqual(result, SQLITE_OK)
            let statement = try XCTUnwrap(handle)
            XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
            return sqlite3_column_int64(statement, 0)
        }
    }
}
