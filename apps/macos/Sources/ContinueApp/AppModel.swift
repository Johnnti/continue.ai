import Combine
import ContinueCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var runtime = RuntimeSnapshot(
        phase: .booting,
        captureStatus: .checking,
        statusMessage: "Checking local capture…",
        lastActivityAt: nil
    )
    @Published private(set) var checkpoint: Checkpoint?
    @Published private(set) var voice = VoiceSnapshot(
        state: .disconnected,
        levels: Array(repeating: 0.08, count: 16)
    )
    @Published private(set) var isLoading = false
    @Published private(set) var isVoiceTransitioning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var voiceErrorMessage: String?

    let resumeProvider: any ResumeProviding
    private let runtimeProvider: any RuntimeProviding
    private let checkpointProvider: any CheckpointProviding
    private let voiceProvider: any VoiceProviding

    init(
        runtimeProvider: any RuntimeProviding,
        checkpointProvider: any CheckpointProviding,
        voiceProvider: any VoiceProviding,
        resumeProvider: any ResumeProviding
    ) {
        self.runtimeProvider = runtimeProvider
        self.checkpointProvider = checkpointProvider
        self.voiceProvider = voiceProvider
        self.resumeProvider = resumeProvider
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        runtime = await runtimeProvider.snapshot()
        voice = await voiceProvider.snapshot()

        do {
            checkpoint = try await checkpointProvider.latest()
        } catch {
            errorMessage = "Continue could not load the latest checkpoint."
        }

        isLoading = false
    }

    func retry() {
        Task {
            await load()
        }
    }

    func startVoiceBriefing() {
        guard let checkpoint, !isVoiceTransitioning else { return }

        Task {
            isVoiceTransitioning = true
            voiceErrorMessage = nil
            voice = VoiceSnapshot(state: .connecting, levels: voice.levels)

            do {
                let briefing = ([checkpoint.summary] + checkpoint.nextSteps).joined(separator: " ")
                try await voiceProvider.start(briefing: briefing)
                voice = await voiceProvider.snapshot()
            } catch {
                voice = VoiceSnapshot(
                    state: .failed(message: "Voice briefing could not start."),
                    levels: voice.levels
                )
                voiceErrorMessage = "Voice briefing could not start."
            }

            isVoiceTransitioning = false
        }
    }

    func stopVoiceBriefing() {
        guard !isVoiceTransitioning else { return }

        Task {
            isVoiceTransitioning = true
            await voiceProvider.stop()
            voice = await voiceProvider.snapshot()
            isVoiceTransitioning = false
        }
    }
}
