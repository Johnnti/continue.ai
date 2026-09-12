import Foundation
import SQLite3

/// A SQLite-backed bridge between the native application and the activity worker.
///
/// The worker remains the authority for `runtime_state`. The native application
/// persists policy changes and places control commands in `runtime_commands`.
public actor SQLiteRuntimeProvider: RuntimeProviding, RuntimeControlling {
    public let databaseURL: URL

    private let heartbeatFreshnessWindow: TimeInterval = 90
    private var lastDatabaseError: String?

    public init(databaseURL: URL = ContinueIntegrationConfiguration().memoryDatabaseURL) {
        self.databaseURL = databaseURL
    }

    public func snapshot() async -> RuntimeSnapshot {
        do {
            let snapshot = try perform { database in
                let policy = try readPolicy(on: database)
                    ?? ActivityTrackingPolicy(preferences: .previewDefaults)

                if !policy.captureEnabled {
                    return RuntimeSnapshot(
                        phase: .observing,
                        captureStatus: .paused,
                        statusMessage: "Screenpipe recording paused",
                        lastActivityAt: nil
                    )
                }

                let state = try readState(on: database)

                guard let state else {
                    return unavailableSnapshot(
                        reason: "The activity worker heartbeat is unavailable."
                    )
                }

                let phase = try phase(from: state.phase)
                let lastActivityAt = try date(from: state.lastActivityAt, field: "last activity")
                guard let heartbeatAt = try date(from: state.heartbeatAt, field: "heartbeat") else {
                    return unavailableSnapshot(
                        phase: phase,
                        lastActivityAt: lastActivityAt,
                        reason: "The activity worker heartbeat is unavailable."
                    )
                }

                let heartbeatAge = Date().timeIntervalSince(heartbeatAt)
                guard heartbeatAge >= -5, heartbeatAge <= heartbeatFreshnessWindow else {
                    return unavailableSnapshot(
                        phase: phase,
                        lastActivityAt: lastActivityAt,
                        reason: "The activity worker heartbeat is older than 90 seconds."
                    )
                }

                let workerCaptureStatus = try captureStatus(
                    from: state.captureStatus,
                    statusMessage: state.statusMessage
                )

                let statusMessage: String
                if !policy.summariesEnabled, workerCaptureStatus == .recording {
                    statusMessage = "Continue summaries paused · Screenpipe is still recording"
                } else {
                    statusMessage = state.statusMessage
                }

                return RuntimeSnapshot(
                    phase: phase,
                    captureStatus: workerCaptureStatus,
                    statusMessage: statusMessage,
                    lastActivityAt: lastActivityAt
                )
            }

            lastDatabaseError = nil
            return snapshot
        } catch {
            let reason = message(for: error)
            lastDatabaseError = reason
            return unavailableSnapshot(reason: reason)
        }
    }

    public func markSteppingAway() async {
        do {
            try perform { database in
                let policy = try readPolicy(on: database)
                    ?? ActivityTrackingPolicy(preferences: .previewDefaults)
                guard policy.captureEnabled,
                      policy.summariesEnabled,
                      policy.checkpointTrigger.allowsManual
                else {
                    return
                }

                let statement = try prepare(
                    database,
                    sql: """
                        INSERT INTO runtime_commands (id, command, created_at, handled_at)
                        VALUES (?, 'manual_away', ?, NULL)
                        """
                )
                defer { sqlite3_finalize(statement) }

                try bindText(statement, at: 1, value: UUID().uuidString, database: database)
                try bindText(
                    statement,
                    at: 2,
                    value: Self.iso8601String(from: Date()),
                    database: database
                )
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw databaseError(
                        database,
                        fallback: "Could not enqueue the manual away command"
                    )
                }
            }
            lastDatabaseError = nil
        } catch {
            lastDatabaseError = message(for: error)
        }
    }

    public func setCaptureEnabled(_ isEnabled: Bool) async {
        do {
            let policy = try awaitPolicy()
            let updatedPolicy = ActivityTrackingPolicy(
                captureEnabled: isEnabled,
                summariesEnabled: policy.summariesEnabled,
                checkpointTrigger: policy.checkpointTrigger,
                idleThresholdMinutes: policy.idleThresholdMinutes,
                observationWindowMinutes: policy.observationWindowMinutes,
                schedule: policy.schedule,
                excludedApplications: policy.excludedApplications,
                checkpointRetentionDays: policy.checkpointRetentionDays,
                screenpipeRetentionDays: policy.screenpipeRetentionDays
            )
            await updateTrackingPolicy(updatedPolicy)
        } catch {
            lastDatabaseError = message(for: error)
        }
    }

    public func setSummariesEnabled(_ isEnabled: Bool) async {
        do {
            let policy = try awaitPolicy()
            let updatedPolicy = ActivityTrackingPolicy(
                captureEnabled: policy.captureEnabled,
                summariesEnabled: isEnabled,
                checkpointTrigger: policy.checkpointTrigger,
                idleThresholdMinutes: policy.idleThresholdMinutes,
                observationWindowMinutes: policy.observationWindowMinutes,
                schedule: policy.schedule,
                excludedApplications: policy.excludedApplications,
                checkpointRetentionDays: policy.checkpointRetentionDays,
                screenpipeRetentionDays: policy.screenpipeRetentionDays
            )
            await updateTrackingPolicy(updatedPolicy)
        } catch {
            lastDatabaseError = message(for: error)
        }
    }

    public func updateTrackingPolicy(_ policy: ActivityTrackingPolicy) async {
        do {
            let policyJSON = try encode(policy)
            let updatedAt = Self.iso8601String(from: Date())
            try perform { database in
                try execute(database, sql: "BEGIN IMMEDIATE")
                do {
                    let upsert = try prepare(
                        database,
                        sql: """
                            INSERT INTO runtime_policy (singleton, policy_json, updated_at)
                            VALUES (1, ?, ?)
                            ON CONFLICT(singleton) DO UPDATE SET
                                policy_json = excluded.policy_json,
                                updated_at = excluded.updated_at
                            """
                    )
                    defer { sqlite3_finalize(upsert) }

                    try bindText(upsert, at: 1, value: policyJSON, database: database)
                    try bindText(upsert, at: 2, value: updatedAt, database: database)
                    guard sqlite3_step(upsert) == SQLITE_DONE else {
                        throw databaseError(
                            database,
                            fallback: "Could not persist the tracking policy"
                        )
                    }

                    try pruneMemories(
                        on: database,
                        olderThan: policy.checkpointRetentionDays
                    )
                    try execute(database, sql: "COMMIT")
                } catch {
                    try? execute(database, sql: "ROLLBACK")
                    throw error
                }
            }
            lastDatabaseError = nil
        } catch {
            lastDatabaseError = message(for: error)
        }
    }

    private func awaitPolicy() throws -> ActivityTrackingPolicy {
        try perform { database in
            try readPolicy(on: database)
                ?? ActivityTrackingPolicy(preferences: .previewDefaults)
        }
    }

    private func perform<Value>(
        _ operation: (OpaquePointer) throws -> Value
    ) throws -> Value {
        let database = try openDatabase()
        defer { sqlite3_close(database) }
        return try operation(database)
    }

    private func openDatabase() throws -> OpaquePointer {
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw RuntimeProviderError(
                message: "Could not create the runtime database directory: \(error.localizedDescription)"
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
                ?? "Could not open the runtime database"
            if let database { sqlite3_close(database) }
            throw RuntimeProviderError(message: message)
        }

        guard sqlite3_busy_timeout(database, 5_000) == SQLITE_OK else {
            let error = databaseError(database, fallback: "Could not configure the SQLite busy timeout")
            sqlite3_close(database)
            throw error
        }

        do {
            try execute(database, sql: "PRAGMA journal_mode = WAL")
            try execute(database, sql: "PRAGMA synchronous = NORMAL")
            try executeSchema(on: database)
            return database
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    private func executeSchema(on database: OpaquePointer) throws {
        try execute(
            database,
            sql: """
                CREATE TABLE IF NOT EXISTS runtime_policy (
                    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                    policy_json TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS runtime_state (
                    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                    phase TEXT NOT NULL,
                    capture_status TEXT NOT NULL,
                    status_message TEXT NOT NULL,
                    last_activity_at TEXT,
                    heartbeat_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS runtime_commands (
                    id TEXT PRIMARY KEY,
                    command TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    handled_at TEXT
                );
                CREATE TABLE IF NOT EXISTS memories (
                    id TEXT PRIMARY KEY,
                    ended_at TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    memory_json TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS memories_ended_at_idx
                    ON memories (ended_at DESC);
                """
        )
    }

    private func readPolicy(on database: OpaquePointer) throws -> ActivityTrackingPolicy? {
        let statement = try prepare(
            database,
            sql: "SELECT policy_json FROM runtime_policy WHERE singleton = 1 LIMIT 1"
        )
        defer { sqlite3_finalize(statement) }

        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else {
            throw databaseError(database, fallback: "Could not read the tracking policy")
        }
        guard let rawJSON = textColumn(statement, at: 0) else {
            throw RuntimeProviderError(message: "The tracking policy row has no JSON payload")
        }

        do {
            return try JSONDecoder().decode(
                ActivityTrackingPolicy.self,
                from: Data(rawJSON.utf8)
            )
        } catch {
            throw RuntimeProviderError(
                message: "The tracking policy JSON could not be decoded: \(error.localizedDescription)"
            )
        }
    }

    private func readState(on database: OpaquePointer) throws -> RuntimeStateRecord? {
        let statement = try prepare(
            database,
            sql: """
                SELECT phase, capture_status, status_message, last_activity_at, heartbeat_at
                FROM runtime_state
                WHERE singleton = 1
                LIMIT 1
                """
        )
        defer { sqlite3_finalize(statement) }

        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else {
            throw databaseError(database, fallback: "Could not read the runtime state")
        }
        guard let phase = textColumn(statement, at: 0),
              let captureStatus = textColumn(statement, at: 1),
              let statusMessage = textColumn(statement, at: 2),
              let heartbeatAt = textColumn(statement, at: 4)
        else {
            throw RuntimeProviderError(message: "The runtime state row is incomplete")
        }

        return RuntimeStateRecord(
            phase: phase,
            captureStatus: captureStatus,
            statusMessage: statusMessage,
            lastActivityAt: textColumn(statement, at: 3),
            heartbeatAt: heartbeatAt
        )
    }

    private func pruneMemories(
        on database: OpaquePointer,
        olderThan retentionDays: Int
    ) throws {
        let cutoff = Date().addingTimeInterval(-TimeInterval(max(0, retentionDays)) * 86_400)
        let statement = try prepare(
            database,
            sql: "DELETE FROM memories WHERE julianday(ended_at) < julianday(?)"
        )
        defer { sqlite3_finalize(statement) }

        try bindText(
            statement,
            at: 1,
            value: Self.iso8601String(from: cutoff),
            database: database
        )
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError(database, fallback: "Could not prune expired memories")
        }
    }

    private func phase(from value: String) throws -> RuntimePhase {
        guard let phase = RuntimePhase(rawValue: value) else {
            throw RuntimeProviderError(message: "The runtime worker returned an unknown phase: \(value)")
        }
        return phase
    }

    private func captureStatus(
        from value: String,
        statusMessage: String
    ) throws -> CaptureStatus {
        switch value {
        case "recording":
            return .recording
        case "paused":
            return .paused
        case "unavailable":
            return .unavailable(
                reason: statusMessage.isEmpty ? "The activity worker reports unavailable capture." : statusMessage
            )
        default:
            throw RuntimeProviderError(
                message: "The runtime worker returned an unknown capture status: \(value)"
            )
        }
    }

    private func date(from value: String?, field: String) throws -> Date? {
        guard let value else { return nil }
        guard let date = Self.parseISO8601(value) else {
            throw RuntimeProviderError(message: "The runtime worker returned an invalid \(field) timestamp")
        }
        return date
    }

    private func encode(_ policy: ActivityTrackingPolicy) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return String(
                decoding: try encoder.encode(policy),
                as: UTF8.self
            )
        } catch {
            throw RuntimeProviderError(
                message: "The tracking policy could not be encoded: \(error.localizedDescription)"
            )
        }
    }

    private func prepare(
        _ database: OpaquePointer,
        sql: String
    ) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sql.withCString { sqlPointer in
            sqlite3_prepare_v2(database, sqlPointer, -1, &statement, nil)
        }
        guard result == SQLITE_OK, let statement else {
            throw databaseError(database, fallback: "Could not prepare the SQLite statement")
        }
        return statement
    }

    private func execute(_ database: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sql.withCString { sqlPointer in
            sqlite3_exec(database, sqlPointer, nil, nil, &errorMessage)
        }
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw RuntimeProviderError(message: message)
        }
    }

    private func bindText(
        _ statement: OpaquePointer,
        at index: Int32,
        value: String,
        database: OpaquePointer
    ) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result = value.withCString { valuePointer in
            sqlite3_bind_text(statement, index, valuePointer, -1, transient)
        }
        guard result == SQLITE_OK else {
            throw databaseError(database, fallback: "Could not bind SQLite text")
        }
    }

    private func textColumn(_ statement: OpaquePointer, at index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func databaseError(
        _ database: OpaquePointer,
        fallback: String
    ) -> RuntimeProviderError {
        let message = String(cString: sqlite3_errmsg(database))
        return RuntimeProviderError(message: message.isEmpty ? fallback : message)
    }

    private func message(for error: Error) -> String {
        if let runtimeError = error as? RuntimeProviderError {
            return runtimeError.message
        }
        return error.localizedDescription
    }

    private func unavailableSnapshot(
        phase: RuntimePhase = .booting,
        lastActivityAt: Date? = nil,
        reason: String
    ) -> RuntimeSnapshot {
        RuntimeSnapshot(
            phase: phase,
            captureStatus: .unavailable(reason: reason),
            statusMessage: reason,
            lastActivityAt: lastActivityAt
        )
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}

private struct RuntimeStateRecord {
    let phase: String
    let captureStatus: String
    let statusMessage: String
    let lastActivityAt: String?
    let heartbeatAt: String
}

private struct RuntimeProviderError: Error, LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}
