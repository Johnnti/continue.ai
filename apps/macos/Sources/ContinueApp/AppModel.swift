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
    @Published private(set) var history: [Checkpoint] = []
    @Published private(set) var preferences = AppPreferences.previewDefaults
    @Published private(set) var voice = VoiceSnapshot(
        state: .disconnected,
        levels: Array(repeating: 0.08, count: 16)
    )
    @Published private(set) var isLoading = false
    @Published private(set) var isVoiceTransitioning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var historyErrorMessage: String?
    @Published private(set) var voiceErrorMessage: String?
    @Published private(set) var resumePreview: ResumePreview?
    @Published private(set) var resumeSelection = ResumeSelection(targets: [])
    @Published private(set) var resumeResults: [ResumeResult] = []
    @Published private(set) var resumeErrorMessage: String?
    @Published private(set) var isPreparingResume = false
    @Published private(set) var isResuming = false

    private let runtimeProvider: any RuntimeProviding
    private let checkpointProvider: any CheckpointProviding
    private let voiceProvider: any VoiceProviding
    private let resumeProvider: any ResumeProviding

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
        historyErrorMessage = nil
        runtime = await runtimeProvider.snapshot()
        voice = await voiceProvider.snapshot()

        do {
            checkpoint = try await checkpointProvider.latest()
        } catch {
            errorMessage = "Continue could not load the latest checkpoint."
        }

        do {
            history = try await checkpointProvider.history(limit: 20)
        } catch {
            historyErrorMessage = "Continue could not load checkpoint history."
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

    func prepareResume() {
        guard let checkpoint, !isPreparingResume else { return }

        Task {
            isPreparingResume = true
            resumeErrorMessage = nil

            do {
                let preview = try await resumeProvider.preview(checkpointID: checkpoint.id)
                resumeSelection = ResumeSelection(targets: preview.targets)
                resumeResults = []
                resumePreview = preview
            } catch {
                resumeErrorMessage = "Continue could not prepare the resume review."
            }

            isPreparingResume = false
        }
    }

    func toggleResumeTarget(_ targetID: String) {
        var updatedSelection = resumeSelection
        updatedSelection.toggle(targetID)
        resumeSelection = updatedSelection
    }

    func confirmResume() {
        guard
            let preview = resumePreview,
            !resumeSelection.selectedIDs.isEmpty,
            !isResuming
        else { return }

        Task {
            isResuming = true
            resumeErrorMessage = nil

            do {
                resumeResults = try await resumeProvider.execute(
                    checkpointID: preview.checkpointID,
                    targetIDs: resumeSelection.selectedIDs
                )
            } catch {
                resumeErrorMessage = "Continue could not resume the selected items."
            }

            isResuming = false
        }
    }

    func dismissResumeReview() {
        guard !isResuming else { return }
        resumePreview = nil
        resumeResults = []
        resumeErrorMessage = nil
    }

    func setInterpretationEnabled(_ isEnabled: Bool) {
        var updatedPreferences = preferences
        updatedPreferences.interpretationEnabled = isEnabled
        preferences = updatedPreferences
    }

    func setVoiceBriefingsEnabled(_ isEnabled: Bool) {
        var updatedPreferences = preferences
        updatedPreferences.voiceBriefingsEnabled = isEnabled
        preferences = updatedPreferences

        if !isEnabled {
            stopVoiceBriefing()
        }
    }

    func setIdleThreshold(minutes: Int) {
        var updatedPreferences = preferences
        updatedPreferences.idleThresholdMinutes = min(max(minutes, 5), 60)
        preferences = updatedPreferences
    }

    func setCheckpointRetention(days: Int) {
        guard [1, 7, 30].contains(days) else { return }
        var updatedPreferences = preferences
        updatedPreferences.checkpointRetentionDays = days
        preferences = updatedPreferences
    }
}
