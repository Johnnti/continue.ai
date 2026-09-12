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

        print("ContinueCoreChecks: 5 checks passed")
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

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw CheckFailure.expected(message)
        }
    }
}
