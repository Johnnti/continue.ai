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
        try await voiceProviderMovesBetweenSpeakingAndDisconnected()
        try await resumeProviderOnlyReturnsSelectedTargets()
        try waveformMathUsesStableSilenceFloor()
        try waveformMathClampsInputLevels()
        try resumeSelectionRejectsUnknownIdentifiers()
        try await resumeProviderRejectsUnknownCheckpoints()

        print("ContinueCoreChecks: 9 checks passed")
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

    private static func voiceProviderMovesBetweenSpeakingAndDisconnected() async throws {
        let provider = PreviewVoiceProvider()

        try await provider.start(briefing: "Welcome back")
        let speaking = await provider.snapshot()
        await provider.stop()
        let stopped = await provider.snapshot()

        try expect(speaking.state == .speaking, "Voice provider must enter speaking state")
        try expect(
            speaking.levels == PreviewContent.listeningLevels,
            "Speaking state must expose deterministic fixture levels"
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

        selection.toggle("unknown-target")
        try expect(selection.selectedIDs == originalIDs, "Unknown target IDs must be ignored")

        selection.toggle(targets[0].id)
        try expect(!selection.contains(targets[0].id), "Known targets must be individually removable")
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

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw CheckFailure.expected(message)
        }
    }
}
