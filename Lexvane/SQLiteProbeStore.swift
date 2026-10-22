import Foundation
import SQLite3

/// Disposable M0 integer key/value storage, not a product data schema.
/// Each operation owns and closes its connection; no UI or shared connection state.
struct SQLiteProbeStore {
    enum Failure: Error, Equatable {
        case sqlite(code: Int32, message: String)
        case unsupportedSchema(Int64)
    }

    let fileURL: URL

    func save(key: Int64, value: Int64) throws {
        try withDatabase { database in
            try withStatement(database, sql: "INSERT INTO probe_values (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value") { statement in
                try check(sqlite3_bind_int64(statement, 1, key), expected: SQLITE_OK, database: database)
                try check(sqlite3_bind_int64(statement, 2, value), expected: SQLITE_OK, database: database)
                try check(sqlite3_step(statement), expected: SQLITE_DONE, database: database)
            }
        }
    }

    func value(forKey key: Int64) throws -> Int64? {
        try withDatabase { database in
            try withStatement(database, sql: "SELECT value FROM probe_values WHERE key = ?") { statement in
                try check(sqlite3_bind_int64(statement, 1, key), expected: SQLITE_OK, database: database)
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return nil }
                try check(result, expected: SQLITE_ROW, database: database)
                return sqlite3_column_int64(statement, 0)
            }
        }
    }

    func delete(key: Int64) throws {
        try withDatabase { database in
            try withStatement(database, sql: "DELETE FROM probe_values WHERE key = ?") { statement in
                try check(sqlite3_bind_int64(statement, 1, key), expected: SQLITE_OK, database: database)
                try check(sqlite3_step(statement), expected: SQLITE_DONE, database: database)
            }
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var handle: OpaquePointer?
        let result = sqlite3_open(fileURL.path, &handle)
        guard let database = handle else {
            throw Failure.sqlite(code: result, message: "SQLite did not return a connection")
        }
        defer { sqlite3_close(database) }
        try check(result, expected: SQLITE_OK, database: database)

        // Schema and version changes commit together. Failure preserves the old file.
        try execute(database, sql: "BEGIN IMMEDIATE")
        do {
            let version = try withStatement(database, sql: "PRAGMA user_version") { statement in
                try check(sqlite3_step(statement), expected: SQLITE_ROW, database: database)
                return sqlite3_column_int64(statement, 0)
            }
            switch version {
            case 0:
                try execute(database, sql: "CREATE TABLE probe_values (key INTEGER PRIMARY KEY, value INTEGER NOT NULL)")
                try execute(database, sql: "PRAGMA user_version = 1")
            case 1:
                break
            default:
                throw Failure.unsupportedSchema(version)
            }
            let value = try body(database)
            try execute(database, sql: "COMMIT")
            return value
        } catch {
            // Preserve the original failure; closing also rolls back an open transaction.
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    private func execute(_ database: OpaquePointer, sql: String) throws {
        try check(sqlite3_exec(database, sql, nil, nil, nil), expected: SQLITE_OK, database: database)
    }

    private func withStatement<T>(
        _ database: OpaquePointer,
        sql: String,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        try check(result, expected: SQLITE_OK, database: database)
        guard let statement else {
            throw Failure.sqlite(code: SQLITE_ERROR, message: "SQLite did not return a statement")
        }
        return try body(statement)
    }

    private func check(_ code: Int32, expected: Int32, database: OpaquePointer) throws {
        guard code == expected else {
            throw Failure.sqlite(code: code, message: String(cString: sqlite3_errmsg(database)))
        }
    }
}
