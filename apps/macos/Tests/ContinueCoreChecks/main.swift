import ContinueCore
import Foundation
import SQLite3

private enum CheckFailure: Error, CustomStringConvertible {
    case expected(String)

    var description: String {
        switch self {
        case let .expected(message):
            "Check failed: \(message)"
        }
    }
}

@main
struct ContinueCoreChecks {
    static func main() async throws {
        if CommandLine.arguments.count == 4,
           CommandLine.arguments[1] == "--verify-external-database"
        {
            try await verifyExternalDatabase(
                at: URL(fileURLWithPath: CommandLine.arguments[2]),
                expectedCheckpointID: CommandLine.arguments[3]
            )
            print("ContinueCoreChecks: external SQLite bridge passed")
            return
        }

        try checkpointContractRoundTripsThroughJSON()
        try await checkpointProviderReturnsNewestFirst()
        try await checkpointProviderHonorsZeroLimit()
        try await voiceProviderMovesBetweenListeningAndDisconnected()
        try await resumeProviderOnlyReturnsSelectedTargets()
        try waveformMathUsesStableSilenceFloor()
        try waveformMathClampsInputLevels()
        try resumeSelectionRejectsUnknownIdentifiers()
        try await resumeProviderRejectsUnknownCheckpoints()
        try previewPreferencesExposeConservativeDefaults()
        try await resumeProviderRejectsUnknownTargetIdentifiers()
        try canonicalCheckpointFixtureDecodesAndMaps()
        try normalizedActivityFixtureDecodesChronologically()
        try canonicalResumeTargetsRetainLocators()
        try await runtimeControllerMarksManualAwayWithoutStoppingCapture()
        try checkpointNextStepCanBeCorrectedWithoutChangingEvidence()
        try returnNotificationRequiresOneEnabledAwayToReturnTransition()
        try trackingScheduleHonorsWindow()
        try checkpointTriggerLimitsManualAndAutomatic()
        try preferencesNormalizeOptionsAndApplications()
        try preferencesPersistThroughStore()
        try appPreferencesDecodeLegacyPayload()
        try await runtimeControllerAppliesTrackingPolicy()
        try await sqliteCheckpointProviderReadsSharedMemory()
        try await storedResumeProviderUsesDatabaseTargets()
        try integrationConfigurationHonorsOverrides()

        print("ContinueCoreChecks: 26 checks passed")
    }

    private static func verifyExternalDatabase(
        at databaseURL: URL,
        expectedCheckpointID: String
    ) async throws {
        let provider = SQLiteCheckpointProvider(databaseURL: databaseURL)
        let latest = try await provider.latest()
        let history = try await provider.history(limit: 10)
        let emptyHistory = try await provider.history(limit: 0)

        try expect(
            latest?.id == expectedCheckpointID,
            "Swift must read the checkpoint written by the TypeScript memory store"
        )
        try expect(
            history.first?.id == expectedCheckpointID,
            "Swift history must preserve the TypeScript checkpoint order"
        )
        try expect(
            history.first?.resumeTargets.first?.locator == "https://example.com/continue",
            "Swift must retain resume target locators written by TypeScript"
        )
        try expect(emptyHistory.isEmpty, "A zero Swift history limit must return no checkpoints")
    }

    private static func checkpointContractRoundTripsThroughJSON() throws {
        let checkpoint = PreviewContent.latestCheckpoint
        let data = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(Checkpoint.self, from: data)

        try expect(decoded == checkpoint, "Checkpoint must survive a JSON round trip")
    }

    private static func checkpointProviderReturnsNewestFirst() async throws {
        let provider = PreviewCheckpointProvider()

        let latest = try await provider.latest()
        let history = try await provider.history(limit: 2)

        try expect(
            latest?.id == PreviewContent.latestCheckpoint.id,
            "Latest checkpoint must use the newest fixture"
        )
        try expect(
            history.map(\.id) == [
                PreviewContent.latestCheckpoint.id,
                PreviewContent.earlierCheckpoint.id
            ],
            "History must be newest first"
        )
    }

    private static func checkpointProviderHonorsZeroLimit() async throws {
        let provider = PreviewCheckpointProvider()
        let history = try await provider.history(limit: 0)

        try expect(history.isEmpty, "A zero history limit must return no checkpoints")
    }

    private static func voiceProviderMovesBetweenListeningAndDisconnected() async throws {
        let provider = PreviewVoiceProvider()

        try await provider.start(briefing: "Welcome back")
        let listening = await provider.snapshot()
        await provider.stop()
        let stopped = await provider.snapshot()

        try expect(listening.state == .listening, "Voice provider must enter listening state")
        try expect(
            listening.levels == PreviewContent.listeningLevels,
            "Listening state must expose deterministic fixture levels"
        )
        try expect(stopped.state == .disconnected, "Stopping voice must disconnect it")
    }

    private static func resumeProviderOnlyReturnsSelectedTargets() async throws {
        let provider = PreviewResumeProvider()
        let selectedID = PreviewContent.latestCheckpoint.resumeTargets[1].id

        let results = try await provider.execute(
            checkpointID: PreviewContent.latestCheckpoint.id,
            targetIDs: [selectedID]
        )

        try expect(results.map(\.id) == [selectedID], "Only selected targets may run")
        try expect(results.first?.outcome == .opened, "Preview targets must report success")
    }

    private static func waveformMathUsesStableSilenceFloor() throws {
        let bars = WaveformMath.normalizedLevels([], barCount: 4)

        try expect(bars == [0.08, 0.08, 0.08, 0.08], "Silence must render at a stable floor")
        try expect(
            WaveformMath.normalizedLevels([0.5], barCount: 0).isEmpty,
            "A zero bar count must return no levels"
        )
    }

    private static func waveformMathClampsInputLevels() throws {
        let bars = WaveformMath.normalizedLevels([-1, 0.5, 2], barCount: 3)

        try expect(bars == [0.08, 0.5, 1], "Waveform levels must remain between floor and one")
    }

    private static func resumeSelectionRejectsUnknownIdentifiers() throws {
        let targets = PreviewContent.latestCheckpoint.resumeTargets
        var selection = ResumeSelection(targets: targets)
        let originalIDs = selection.selectedIDs

        try expect(originalIDs.isEmpty, "Reopen review must begin with nothing selected")
        selection.toggle("unknown-target")
        try expect(selection.selectedIDs == originalIDs, "Unknown target IDs must be ignored")

        selection.toggle(targets[0].id)
        try expect(selection.contains(targets[0].id), "Known targets must be individually selectable")
    }

    private static func resumeProviderRejectsUnknownCheckpoints() async throws {
        let provider = PreviewResumeProvider()

        do {
            _ = try await provider.preview(checkpointID: "unknown-checkpoint")
            throw CheckFailure.expected("Unknown checkpoints must not produce a resume preview")
        } catch ContinueServiceError.checkpointNotFound {
            return
        }
    }

    private static func previewPreferencesExposeConservativeDefaults() throws {
        let preferences = AppPreferences.previewDefaults

        try expect(preferences.interpretationEnabled, "Preview interpretation must be visible by default")
        try expect(preferences.voiceBriefingsEnabled, "Voice conversation control must start enabled")
        try expect(preferences.idleThresholdMinutes == 4, "Default away threshold must be 4 minutes")
        try expect(preferences.checkpointRetentionDays == 7, "Default checkpoint retention must be 7 days")
    }

    private static func resumeProviderRejectsUnknownTargetIdentifiers() async throws {
        let provider = PreviewResumeProvider()

        do {
            _ = try await provider.execute(
                checkpointID: PreviewContent.latestCheckpoint.id,
                targetIDs: ["unknown-target"]
            )
            throw CheckFailure.expected("Unknown target IDs must not execute")
        } catch ContinueServiceError.invalidResumeTargets {
            return
        }
    }

    private static func canonicalCheckpointFixtureDecodesAndMaps() throws {
        let contract = try ContractFixtures.sessionCheckpointV1()
        let checkpoint = try contract.makeCheckpoint(awayDurationMinutes: 42)

        try expect(contract.project == "continue.ai", "Contract fixture must retain the project")
        try expect(checkpoint.project == contract.project, "Checkpoint must retain the project")
        try expect(checkpoint.headline == contract.currentTask, "UI headline must map from currentTask")
        try expect(checkpoint.completed == [contract.lastAction], "Completed work must map from lastAction")
        try expect(checkpoint.nextSteps == [contract.nextAction], "Next steps must map from nextAction")
        try expect(checkpoint.confidence == .high, "Numeric confidence must map to the UI confidence band")
        try expect(checkpoint.awayDurationMinutes == 42, "Runtime away duration must remain separate from source window")
    }

    private static func normalizedActivityFixtureDecodesChronologically() throws {
        let events = try ContractFixtures.normalizedActivityV1()
        let formatter = ISO8601DateFormatter()
        let dates = events.compactMap { formatter.date(from: $0.timestamp) }

        try expect(events.count == 3, "Normalized activity fixture must contain three events")
        try expect(dates.count == events.count, "Every activity event must have an ISO-8601 timestamp")
        try expect(dates == dates.sorted(), "Normalized activity must be chronological")
    }

    private static func canonicalResumeTargetsRetainLocators() throws {
        let contract = try ContractFixtures.sessionCheckpointV1()
        let checkpoint = try contract.makeCheckpoint(awayDurationMinutes: 42)

        try expect(
            checkpoint.resumeTargets.map(\.locator) == contract.resumeTargets.map(\.value),
            "Swift resume targets must retain every canonical locator"
        )
        try expect(
            checkpoint.resumeTargets.map(\.kind) == [.url, .url, .file],
            "Canonical target types must map to Swift target kinds"
        )
    }

    private static func runtimeControllerMarksManualAwayWithoutStoppingCapture() async throws {
        let provider = PreviewRuntimeProvider()

        await provider.markSteppingAway()
        let awaySnapshot = await provider.snapshot()

        try expect(awaySnapshot.phase == .away, "Manual away must update the runtime phase")
        try expect(
            awaySnapshot.captureStatus == .recording,
            "Manual away must not stop Screenpipe recording"
        )

        await provider.setSummariesEnabled(false)
        let pausedSummarySnapshot = await provider.snapshot()

        try expect(
            pausedSummarySnapshot.captureStatus == .recording,
            "Pausing Continue summaries must not stop Screenpipe recording"
        )
        try expect(
            pausedSummarySnapshot.statusMessage.contains("Screenpipe is still recording"),
            "Paused summary copy must state that Screenpipe still records"
        )
    }

    private static func checkpointNextStepCanBeCorrectedWithoutChangingEvidence() throws {
        let original = PreviewContent.latestCheckpoint
        let updated = original.replacingNextSteps(with: ["Test the corrected return flow"])

        try expect(updated.nextSteps == ["Test the corrected return flow"], "Next step must be replaceable")
        try expect(updated.id == original.id, "Editing the next step must retain checkpoint identity")
        try expect(updated.evidence == original.evidence, "Editing the next step must retain its evidence")
    }

    private static func returnNotificationRequiresOneEnabledAwayToReturnTransition() throws {
        try expect(
            RuntimeTransition.shouldNotifyReturn(
                previous: .away,
                current: .returning,
                summariesEnabled: true
            ),
            "An enabled away-to-return transition must produce a return notification"
        )
        try expect(
            !RuntimeTransition.shouldNotifyReturn(
                previous: .observing,
                current: .returning,
                summariesEnabled: true
            ),
            "Opening a returning snapshot must not produce a duplicate notification"
        )
        try expect(
            !RuntimeTransition.shouldNotifyReturn(
                previous: .away,
                current: .returning,
                summariesEnabled: false
            ),
            "Paused summaries must suppress return notifications"
        )
    }

    private static func trackingScheduleHonorsWindow() throws {
        try expect(
            TrackingSchedule.allDay.contains(hour: 3),
            "A disabled schedule must include every hour"
        )

        let workday = TrackingSchedule(isEnabled: true, startHour: 9, endHour: 17)
        try expect(workday.contains(hour: 9), "The schedule must include its start hour")
        try expect(workday.contains(hour: 16), "The schedule must include hours before its end")
        try expect(!workday.contains(hour: 17), "The schedule must exclude its end hour")
        try expect(!workday.contains(hour: 8), "The schedule must exclude hours before its start")
        try expect(workday.displayRange == "9 AM–5 PM", "The display range must format both hours")

        let overnight = TrackingSchedule(isEnabled: true, startHour: 22, endHour: 6)
        try expect(overnight.contains(hour: 23), "An overnight schedule must include late hours")
        try expect(overnight.contains(hour: 5), "An overnight schedule must include early hours")
        try expect(!overnight.contains(hour: 12), "An overnight schedule must exclude midday")

        let degenerate = TrackingSchedule(isEnabled: true, startHour: 12, endHour: 12)
        try expect(degenerate.contains(hour: 4), "Equal start and end hours must include every hour")

        let clamped = TrackingSchedule(isEnabled: true, startHour: -3, endHour: 42)
        try expect(clamped.startHour == 0, "Schedule hours must clamp to the start of the day")
        try expect(clamped.endHour == 23, "Schedule hours must clamp to the end of the day")
    }

    private static func checkpointTriggerLimitsManualAndAutomatic() throws {
        try expect(
            CheckpointTrigger.automatic.allowsAutomatic,
            "The automatic trigger must allow automatic checkpoints"
        )
        try expect(
            !CheckpointTrigger.automatic.allowsManual,
            "The automatic trigger must reject manual away mode"
        )
        try expect(
            CheckpointTrigger.manual.allowsManual,
            "The manual trigger must allow manual away mode"
        )
        try expect(
            !CheckpointTrigger.manual.allowsAutomatic,
            "The manual trigger must reject automatic checkpoints"
        )
        try expect(
            CheckpointTrigger.automaticAndManual.allowsAutomatic
                && CheckpointTrigger.automaticAndManual.allowsManual,
            "The combined trigger must allow both checkpoint paths"
        )
    }

    private static func preferencesNormalizeOptionsAndApplications() throws {
        let preferences = AppPreferences(
            interpretationEnabled: true,
            voiceBriefingsEnabled: true,
            idleThresholdMinutes: 90,
            checkpointRetentionDays: 12,
            observationWindowMinutes: 7,
            excludedApplications: [" Messages ", "messages", "", "  ", "Mail"]
        )

        try expect(
            preferences.idleThresholdMinutes == 60,
            "The away threshold must clamp to 60 minutes"
        )
        try expect(
            preferences.checkpointRetentionDays == 7,
            "Unknown checkpoint retention must fall back to 7 days"
        )
        try expect(
            preferences.observationWindowMinutes == 5,
            "The observation window must snap to the nearest option"
        )
        try expect(
            preferences.excludedApplications == ["Messages", "Mail"],
            "Exclusions must trim, drop empty entries, and deduplicate case-insensitively"
        )
        try expect(
            preferences.screenpipeRetentionDays == 0,
            "Unknown Screenpipe retention must fall back to Screenpipe-managed"
        )
    }

    private static func preferencesPersistThroughStore() throws {
        let suiteName = "ContinueCoreChecks.preferences"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw CheckFailure.expected("A UserDefaults suite must be available for the store check")
        }
        defer {
            AppPreferencesStore.remove(from: defaults)
            defaults.removePersistentDomain(forName: suiteName)
        }

        var preferences = AppPreferences.previewDefaults
        preferences.captureEnabled = false
        preferences.observationWindowMinutes = 15
        preferences.checkpointTrigger = .manual
        preferences.trackingSchedule = TrackingSchedule(isEnabled: true, startHour: 9, endHour: 17)
        preferences.excludedApplications = ["Messages"]

        AppPreferencesStore.save(preferences, to: defaults)

        try expect(
            AppPreferencesStore.load(from: defaults) == preferences,
            "Saved preferences must reload without changes"
        )

        AppPreferencesStore.remove(from: defaults)
        try expect(
            AppPreferencesStore.load(from: defaults) == .previewDefaults,
            "Removing stored preferences must restore the conservative defaults"
        )
    }

    private static func appPreferencesDecodeLegacyPayload() throws {
        let legacy = """
        {"interpretationEnabled":false,"voiceBriefingsEnabled":false,\
        "idleThresholdMinutes":9,"checkpointRetentionDays":30}
        """
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: Data(legacy.utf8))

        try expect(decoded.captureEnabled, "Legacy payloads must default capture to enabled")
        try expect(!decoded.interpretationEnabled, "Legacy payloads must retain stored values")
        try expect(decoded.idleThresholdMinutes == 9, "Legacy payloads must retain the threshold")
        try expect(
            decoded.observationWindowMinutes == 30,
            "Legacy payloads must default the observation window"
        )
        try expect(
            decoded.checkpointTrigger == .automaticAndManual,
            "Legacy payloads must default the checkpoint trigger"
        )
        try expect(decoded.trackingSchedule == .allDay, "Legacy payloads must default the schedule")
        try expect(decoded.excludedApplications.isEmpty, "Legacy payloads must default exclusions")
        try expect(
            decoded.screenpipeRetentionDays == 0,
            "Legacy payloads must default Screenpipe retention"
        )
    }

    private static func runtimeControllerAppliesTrackingPolicy() async throws {
        let provider = PreviewRuntimeProvider()

        await provider.setCaptureEnabled(false)
        let paused = await provider.snapshot()
        try expect(paused.captureStatus == .paused, "Disabling capture must pause Screenpipe")
        try expect(paused.phase == .observing, "Disabling capture must leave the away phase")

        var preferences = AppPreferences.previewDefaults
        preferences.captureEnabled = true
        preferences.trackingSchedule = TrackingSchedule(isEnabled: true, startHour: 9, endHour: 17)
        let policy = ActivityTrackingPolicy(preferences: preferences)

        await provider.updateTrackingPolicy(policy)
        let scheduled = await provider.snapshot()
        try expect(
            scheduled.captureStatus == .recording,
            "Re-enabling capture must resume Screenpipe recording"
        )
        try expect(
            scheduled.statusMessage.contains("9 AM–5 PM"),
            "An enabled schedule must surface its display range"
        )
        let appliedPolicy = await provider.currentTrackingPolicy()
        try expect(
            appliedPolicy == policy,
            "The runtime must retain the applied tracking policy"
        )

        await provider.setSummariesEnabled(false)
        await provider.markSteppingAway()
        let suppressed = await provider.snapshot()
        try expect(
            suppressed.phase != .away,
            "Manual away must be ignored while summaries are paused"
        )
    }

    private static func sqliteCheckpointProviderReadsSharedMemory() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("continue-core-check-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try createSharedMemoryFixture(at: databaseURL)
        let provider = SQLiteCheckpointProvider(databaseURL: databaseURL)

        let latest = try await provider.latest()
        let history = try await provider.history(limit: 10)

        try expect(
            latest?.id == "live-checkpoint",
            "SQLite provider must decode the shared memory database payload"
        )
        try expect(
            history.first?.resumeTargets.first?.locator == "https://example.com",
            "SQLite provider must retain canonical resume target locators"
        )
    }

    private static func storedResumeProviderUsesDatabaseTargets() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("continue-resume-check-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try createSharedMemoryFixture(at: databaseURL)
        let checkpointProvider = SQLiteCheckpointProvider(databaseURL: databaseURL)
        let resumeProvider = StoredCheckpointResumeProvider(checkpointProvider: checkpointProvider)
        let preview = try await resumeProvider.preview(checkpointID: "live-checkpoint")
        let results = try await resumeProvider.execute(
            checkpointID: preview.checkpointID,
            targetIDs: Set(preview.targets.map(\.id))
        )

        try expect(
            results.count == preview.targets.count,
            "Database-backed resume must validate and return stored targets"
        )
    }

    private static func integrationConfigurationHonorsOverrides() throws {
        let configuration = ContinueIntegrationConfiguration(environment: [
            "CONTINUE_MEMORY_DATABASE_PATH": "/tmp/continue-checks.sqlite",
            "CONTINUE_ELEVENLABS_AGENT_ID": "agent_test",
            "CONTINUE_ELEVENLABS_TOKEN_URL": "https://localhost/token",
            "CONTINUE_ELEVENLABS_USER_ID": "continue-checks"
        ])

        try expect(
            configuration.memoryDatabaseURL.path == "/tmp/continue-checks.sqlite",
            "The database path must be configurable without changing source code"
        )
        try expect(
            configuration.elevenLabsAgentID == "agent_test",
            "The ElevenLabs agent ID must be configurable"
        )
        try expect(
            configuration.elevenLabsTokenURL?.absoluteString == "https://localhost/token",
            "The private-agent token endpoint must be configurable"
        )
        try expect(
            configuration.elevenLabsUserID == "continue-checks",
            "The ElevenLabs user ID must be configurable"
        )
    }

    private static func createSharedMemoryFixture(at databaseURL: URL) throws {
        var database: OpaquePointer?
        let openResult = databaseURL.path.withCString { path in
            sqlite3_open(path, &database)
        }
        guard openResult == SQLITE_OK, let database else {
            throw CheckFailure.expected("The SQLite fixture database must open")
        }
        defer { sqlite3_close(database) }

        let schema = """
            CREATE TABLE memories (
                id TEXT PRIMARY KEY,
                ended_at TEXT NOT NULL,
                created_at TEXT NOT NULL,
                memory_json TEXT NOT NULL
            );
            """
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
            throw CheckFailure.expected("The SQLite fixture schema must be created")
        }

        let payload = """
            {"id":"live-checkpoint","endedAt":"2026-09-12T10:00:00Z","project":"continue.ai","currentTask":"Connecting the live adapters","summary":"The database adapter has a committed checkpoint.","lastAction":"Added the SQLite boundary","nextAction":"Start the voice session","resumeTargets":[{"type":"url","value":"https://example.com","label":"Example"}],"confidence":0.9,"sourceWindowMinutes":5}
            """
        let escapedPayload = payload.replacingOccurrences(of: "'", with: "''")
        let insert = """
            INSERT INTO memories (id, ended_at, created_at, memory_json)
            VALUES ('live-checkpoint', '2026-09-12T10:00:00Z', '2026-09-12T10:00:00Z', '\(escapedPayload)');
            """
        guard sqlite3_exec(database, insert, nil, nil, nil) == SQLITE_OK else {
            throw CheckFailure.expected("The SQLite fixture checkpoint must be inserted")
        }
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw CheckFailure.expected(message)
        }
    }
}
