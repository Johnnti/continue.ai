import ContinueCore
import Foundation

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

        print("ContinueCoreChecks: 17 checks passed")
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

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw CheckFailure.expected(message)
        }
    }
}
