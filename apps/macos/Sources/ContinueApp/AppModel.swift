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
    @Published private(set) var preferences: AppPreferences
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
    @Published private(set) var isUpdatingRuntime = false
    @Published private(set) var notificationAuthorization: ReturnNotificationAuthorization = .checking
    @Published private(set) var isRequestingNotificationAuthorization = false
    let dataSourceLabel: String

    private let runtimeProvider: any RuntimeProviding
    private let runtimeController: any RuntimeControlling
    private let checkpointProvider: any CheckpointProviding
    private let voiceProvider: any VoiceProviding
    private let resumeProvider: any ResumeProviding
    private let returnNotifier: any ReturnNotifying
    private var monitoringTask: Task<Void, Never>?
    private var dismissedCheckpointIDs: Set<String> = []
    private var checkpointEdits: [String: Checkpoint] = [:]

    init(
        runtimeProvider: any RuntimeProviding,
        runtimeController: any RuntimeControlling,
        checkpointProvider: any CheckpointProviding,
        voiceProvider: any VoiceProviding,
        resumeProvider: any ResumeProviding,
        returnNotifier: any ReturnNotifying,
        dataSourceLabel: String = "LIVE DATA"
    ) {
        self.runtimeProvider = runtimeProvider
        self.runtimeController = runtimeController
        self.checkpointProvider = checkpointProvider
        self.voiceProvider = voiceProvider
        self.resumeProvider = resumeProvider
        self.returnNotifier = returnNotifier
        self.dataSourceLabel = dataSourceLabel
        preferences = AppPreferencesStore.load()

        Task { [voiceProvider] in
            await voiceProvider.setResumeRequestHandler { @MainActor [weak self] in
                self?.prepareResume()
            }
        }
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [weak self] in
            guard let self else { return }
            await self.load()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }

                await self.refreshRuntime(notifyOnReturn: true)
            }
        }
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        historyErrorMessage = nil
        await refreshRuntime(notifyOnReturn: false)
        voice = await voiceProvider.snapshot()
        notificationAuthorization = await returnNotifier.authorizationStatus()

        do {
            if let latest = try await checkpointProvider.latest() {
                let resolved = checkpointEdits[latest.id] ?? latest
                checkpoint = dismissedCheckpointIDs.contains(latest.id) ? nil : resolved
            } else {
                checkpoint = nil
            }
        } catch {
            errorMessage = "Continue could not load the latest checkpoint: \(error.localizedDescription)"
        }

        do {
            history = try await checkpointProvider.history(limit: 20).map {
                checkpointEdits[$0.id] ?? $0
            }
        } catch {
            historyErrorMessage = "Continue could not load checkpoint history: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func retry() {
        Task {
            await load()
        }
    }

    func startVoiceConversation() {
        guard let checkpoint, !isVoiceTransitioning else { return }

        Task {
            isVoiceTransitioning = true
            voiceErrorMessage = nil
            voice = VoiceSnapshot(state: .connecting, levels: voice.levels)

            do {
                let conversationContext = ([checkpoint.summary] + checkpoint.nextSteps)
                    .joined(separator: " ")
                try await voiceProvider.start(briefing: conversationContext)
                voice = await voiceProvider.snapshot()
            } catch {
                let message = error.localizedDescription
                voice = VoiceSnapshot(
                    state: .failed(message: message),
                    levels: voice.levels
                )
                voiceErrorMessage = message
            }

            isVoiceTransitioning = false
        }
    }

    func stopVoiceConversation() {
        guard !isVoiceTransitioning else { return }

        Task {
            isVoiceTransitioning = true
            await voiceProvider.stop()
            voice = await voiceProvider.snapshot()
            isVoiceTransitioning = false
        }
    }

    func markSteppingAway() {
        guard
            preferences.captureEnabled,
            preferences.interpretationEnabled,
            preferences.checkpointTrigger.allowsManual,
            !isUpdatingRuntime
        else { return }

        Task {
            isUpdatingRuntime = true
            await runtimeController.markSteppingAway()
            await refreshRuntime(notifyOnReturn: false)
            isUpdatingRuntime = false
        }
    }

    func updateNextStep(_ nextStep: String) {
        let normalized = nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let checkpoint, !normalized.isEmpty else { return }

        let updated = checkpoint.replacingNextSteps(with: [normalized])
        checkpointEdits[updated.id] = updated
        self.checkpoint = updated
        history = history.map { $0.id == updated.id ? updated : $0 }
    }

    func dismissCheckpoint() {
        guard let checkpoint else { return }
        dismissedCheckpointIDs.insert(checkpoint.id)
        self.checkpoint = nil
        stopVoiceConversation()
    }

    func requestNotificationAuthorization() {
        guard !isRequestingNotificationAuthorization else { return }

        Task {
            isRequestingNotificationAuthorization = true
            _ = await returnNotifier.requestAuthorization()
            notificationAuthorization = await returnNotifier.authorizationStatus()
            isRequestingNotificationAuthorization = false
        }
    }

    func prepareResume() {
        guard let checkpoint, !isPreparingResume else { return }

        Task {
            isPreparingResume = true
            resumeErrorMessage = nil

            do {
                let preview = try await resumeProvider.preview(checkpointID: checkpoint.id)
                resumeSelection = ResumeSelection(targets: preview.targets, selectsAll: false)
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
                resumeErrorMessage = "Continue could not open the selected items."
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
        updatePreferences(updatedPreferences)
    }

    func setCaptureEnabled(_ isEnabled: Bool) {
        var updatedPreferences = preferences
        updatedPreferences.captureEnabled = isEnabled
        updatePreferences(updatedPreferences)
    }

    func setVoiceBriefingsEnabled(_ isEnabled: Bool) {
        var updatedPreferences = preferences
        updatedPreferences.voiceBriefingsEnabled = isEnabled
        updatePreferences(updatedPreferences)

        if !isEnabled {
            stopVoiceConversation()
        }
    }

    func setIdleThreshold(minutes: Int) {
        var updatedPreferences = preferences
        updatedPreferences.idleThresholdMinutes = min(max(minutes, 1), 60)
        updatePreferences(updatedPreferences)
    }

    func setCheckpointRetention(days: Int) {
        guard AppPreferences.checkpointRetentionOptions.contains(days) else { return }
        var updatedPreferences = preferences
        updatedPreferences.checkpointRetentionDays = days
        updatePreferences(updatedPreferences)
    }

    func setObservationWindow(minutes: Int) {
        var updatedPreferences = preferences
        updatedPreferences.observationWindowMinutes = minutes
        updatePreferences(updatedPreferences)
    }

    func setCheckpointTrigger(_ trigger: CheckpointTrigger) {
        var updatedPreferences = preferences
        updatedPreferences.checkpointTrigger = trigger
        updatePreferences(updatedPreferences)
    }

    func setTrackingScheduleEnabled(_ isEnabled: Bool) {
        var updatedPreferences = preferences
        updatedPreferences.trackingSchedule.isEnabled = isEnabled
        updatePreferences(updatedPreferences)
    }

    func setTrackingScheduleStart(hour: Int) {
        var updatedPreferences = preferences
        updatedPreferences.trackingSchedule.startHour = min(max(hour, 0), 23)
        updatePreferences(updatedPreferences)
    }

    func setTrackingScheduleEnd(hour: Int) {
        var updatedPreferences = preferences
        updatedPreferences.trackingSchedule.endHour = min(max(hour, 0), 23)
        updatePreferences(updatedPreferences)
    }

    func addExcludedApplication(_ application: String) {
        let normalized = AppPreferences.normalizedApplications(
            preferences.excludedApplications + [application]
        )
        guard normalized.count != preferences.excludedApplications.count else { return }

        var updatedPreferences = preferences
        updatedPreferences.excludedApplications = normalized
        updatePreferences(updatedPreferences)
    }

    func removeExcludedApplication(_ application: String) {
        var updatedPreferences = preferences
        updatedPreferences.excludedApplications.removeAll { $0 == application }
        updatePreferences(updatedPreferences)
    }

    func setScreenpipeRetention(days: Int) {
        var updatedPreferences = preferences
        updatedPreferences.screenpipeRetentionDays = days
        updatePreferences(updatedPreferences)
    }

    private func updatePreferences(_ updatedPreferences: AppPreferences) {
        preferences = updatedPreferences
        AppPreferencesStore.save(updatedPreferences)

        let policy = ActivityTrackingPolicy(preferences: updatedPreferences)
        Task {
            await runtimeController.updateTrackingPolicy(policy)
            await refreshRuntime(notifyOnReturn: false)
        }
    }

    private func refreshRuntime(notifyOnReturn: Bool) async {
        let previousPhase = runtime.phase
        let updatedRuntime = await runtimeProvider.snapshot()
        runtime = updatedRuntime

        guard
            notifyOnReturn,
            RuntimeTransition.shouldNotifyReturn(
                previous: previousPhase,
                current: updatedRuntime.phase,
                summariesEnabled: preferences.interpretationEnabled
            )
        else { return }

        do {
            guard let latest = try await checkpointProvider.latest() else { return }
            let resolved = checkpointEdits[latest.id] ?? latest
            guard !dismissedCheckpointIDs.contains(latest.id) else { return }
            checkpoint = resolved
        } catch {
            errorMessage = "Continue could not load the latest checkpoint: \(error.localizedDescription)"
            return
        }

        await returnNotifier.notifyReturnSummaryReady()
    }
}
