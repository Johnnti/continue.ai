import Foundation
import SQLite3

public actor SQLiteCheckpointProvider: CheckpointProviding {
    public let databaseURL: URL

    public init(databaseURL: URL = ContinueIntegrationConfiguration().memoryDatabaseURL) {
        self.databaseURL = databaseURL
    }

    public func latest() async throws -> Checkpoint? {
        try read(limit: 1).first
    }

    public func history(limit: Int) async throws -> [Checkpoint] {
        guard limit > 0 else { return [] }
        return try read(limit: min(limit, 100))
    }

    private func read(limit: Int) throws -> [Checkpoint] {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let query = """
            SELECT memory_json
            FROM memories
            ORDER BY ended_at DESC, rowid DESC
            LIMIT ?
            """
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw databaseError(database, fallback: "Could not prepare the checkpoint query")
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_int(statement, 1, Int32(limit)) == SQLITE_OK else {
            throw databaseError(database, fallback: "Could not bind the checkpoint limit")
        }

        var checkpoints: [Checkpoint] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw databaseError(database, fallback: "Could not read checkpoint data")
            }

            guard let rawJSON = sqlite3_column_text(statement, 0) else {
                throw ContinueServiceError.databaseUnavailable("A checkpoint row had no JSON payload")
            }

            let payload = String(cString: rawJSON)
            do {
                checkpoints.append(try Self.decodeCheckpoint(from: Data(payload.utf8)))
            } catch {
                throw ContinueServiceError.databaseUnavailable(
                    "A checkpoint row could not be decoded: \(error.localizedDescription)"
                )
            }
        }

        return checkpoints
    }

    private func openDatabase() throws -> OpaquePointer {
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw ContinueServiceError.databaseUnavailable(
                "Could not create the database directory: \(error.localizedDescription)"
            )
        }

        var database: OpaquePointer?
        let result = databaseURL.path.withCString { path in
            sqlite3_open_v2(
                path,
                &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                nil
            )
        }

        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Could not open the database"
            if let database { sqlite3_close(database) }
            throw ContinueServiceError.databaseUnavailable(message)
        }

        sqlite3_busy_timeout(database, 5_000)
        do {
            try executeSchema(on: database)
            return database
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    private func executeSchema(on database: OpaquePointer) throws {
        let schema = """
            CREATE TABLE IF NOT EXISTS memories (
                id TEXT PRIMARY KEY,
                ended_at TEXT NOT NULL,
                created_at TEXT NOT NULL,
                memory_json TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS memories_ended_at_idx
                ON memories (ended_at DESC);
            """
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, schema, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw ContinueServiceError.databaseUnavailable(message)
        }
    }

    private func databaseError(
        _ database: OpaquePointer,
        fallback: String
    ) -> ContinueServiceError {
        ContinueServiceError.databaseUnavailable(
            String(cString: sqlite3_errmsg(database)).isEmpty
                ? fallback
                : String(cString: sqlite3_errmsg(database))
        )
    }

    private static func decodeCheckpoint(from data: Data) throws -> Checkpoint {
        let decoder = JSONDecoder()
        if let canonical = try? decoder.decode(SessionCheckpointV1.self, from: data) {
            return try canonical.makeCheckpoint(awayDurationMinutes: 0)
        }

        return try decoder.decode(Checkpoint.self, from: data)
    }
}
