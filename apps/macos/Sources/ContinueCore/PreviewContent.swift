import Foundation

public enum PreviewContent {
    public static let referenceDate = Date(timeIntervalSince1970: 1_788_563_100)

    public static let runtimeSnapshot = RuntimeSnapshot(
        phase: .returning,
        captureStatus: .recording,
        statusMessage: "Screenpipe recording · activity updated 2 minutes ago",
        lastActivityAt: referenceDate.addingTimeInterval(-120)
    )

    public static let latestCheckpoint = Checkpoint(
        id: "checkpoint-hackrice-demo",
        createdAt: referenceDate.addingTimeInterval(-2_520),
        awayDurationMinutes: 42,
        headline: "You were connecting the return flow",
        summary: "The desktop shell and context contracts are in place. The next useful step is to connect the approval screen without changing the three service packages.",
        completed: [
            "Defined the native macOS architecture",
            "Separated product UI from service adapters"
        ],
        nextSteps: [
            "Review the proposed files and browser tab",
            "Connect the approved resume action"
        ],
        confidence: .high,
        evidence: [
            EvidenceReference(
                id: "evidence-architecture",
                sourceLabel: "IMPLEMENTATION_ARCHITECTURE.md",
                capturedAt: referenceDate.addingTimeInterval(-3_000)
            )
        ],
        resumeTargets: [
            ResumeTarget(
                id: "target-xcode",
                kind: .application,
                title: "ContinueApp",
                detail: "Native SwiftUI package",
                locator: "apps/macos/Package.swift"
            ),
            ResumeTarget(
                id: "target-architecture",
                kind: .file,
                title: "Implementation architecture",
                detail: "Team contracts and implementation sequence",
                locator: "docs/IMPLEMENTATION_ARCHITECTURE.md"
            ),
            ResumeTarget(
                id: "target-screenpipe-docs",
                kind: .url,
                title: "Screenpipe local API",
                detail: "Reference for the data adapter",
                locator: "https://docs.screenpi.pe/docs/api-reference"
            )
        ]
    )

    public static let earlierCheckpoint = Checkpoint(
        id: "checkpoint-initial-plan",
        createdAt: referenceDate.addingTimeInterval(-86_400),
        awayDurationMinutes: 18,
        headline: "You mapped the four workstreams",
        summary: "The team split ownership across capture, context, voice, and product integration.",
        completed: ["Assigned conflict-free directories"],
        nextSteps: ["Start the native product shell"],
        confidence: .high,
        evidence: [],
        resumeTargets: []
    )

    public static let listeningLevels: [Double] = [
        0.10, 0.18, 0.32, 0.48, 0.72, 0.54, 0.38, 0.24,
        0.16, 0.28, 0.52, 0.84, 0.66, 0.44, 0.26, 0.14
    ]
}

public actor PreviewRuntimeProvider: RuntimeProviding, RuntimeControlling {
    private var currentSnapshot: RuntimeSnapshot
    private var trackingPolicy = ActivityTrackingPolicy(preferences: .previewDefaults)

    public init(snapshot: RuntimeSnapshot = PreviewContent.runtimeSnapshot) {
        currentSnapshot = snapshot
    }

    public func snapshot() async -> RuntimeSnapshot {
        currentSnapshot
    }

    public func markSteppingAway() async {
        guard trackingPolicy.captureEnabled, trackingPolicy.summariesEnabled else { return }

        currentSnapshot = RuntimeSnapshot(
            phase: .away,
            captureStatus: currentSnapshot.captureStatus,
            statusMessage: "Manual away mode is active",
            lastActivityAt: currentSnapshot.lastActivityAt
        )
    }

    public func setCaptureEnabled(_ isEnabled: Bool) async {
        trackingPolicy = ActivityTrackingPolicy(
            captureEnabled: isEnabled,
            summariesEnabled: trackingPolicy.summariesEnabled,
            checkpointTrigger: trackingPolicy.checkpointTrigger,
            idleThresholdMinutes: trackingPolicy.idleThresholdMinutes,
            observationWindowMinutes: trackingPolicy.observationWindowMinutes,
            schedule: trackingPolicy.schedule,
            excludedApplications: trackingPolicy.excludedApplications,
            checkpointRetentionDays: trackingPolicy.checkpointRetentionDays,
            screenpipeRetentionDays: trackingPolicy.screenpipeRetentionDays
        )

        currentSnapshot = RuntimeSnapshot(
            phase: isEnabled ? currentSnapshot.phase : .observing,
            captureStatus: isEnabled ? .recording : .paused,
            statusMessage: isEnabled
                ? "Screenpipe recording resumed"
                : "Screenpipe recording paused",
            lastActivityAt: currentSnapshot.lastActivityAt
        )
    }

    public func setSummariesEnabled(_ isEnabled: Bool) async {
        trackingPolicy = ActivityTrackingPolicy(
            captureEnabled: trackingPolicy.captureEnabled,
            summariesEnabled: isEnabled,
            checkpointTrigger: trackingPolicy.checkpointTrigger,
            idleThresholdMinutes: trackingPolicy.idleThresholdMinutes,
            observationWindowMinutes: trackingPolicy.observationWindowMinutes,
            schedule: trackingPolicy.schedule,
            excludedApplications: trackingPolicy.excludedApplications,
            checkpointRetentionDays: trackingPolicy.checkpointRetentionDays,
            screenpipeRetentionDays: trackingPolicy.screenpipeRetentionDays
        )

        currentSnapshot = RuntimeSnapshot(
            phase: isEnabled ? currentSnapshot.phase : .observing,
            captureStatus: currentSnapshot.captureStatus,
            statusMessage: isEnabled
                ? "Continue summaries resumed \u{00B7} Screenpipe is still recording"
                : "Continue summaries paused \u{00B7} Screenpipe is still recording",
            lastActivityAt: currentSnapshot.lastActivityAt
        )
    }

    public func updateTrackingPolicy(_ policy: ActivityTrackingPolicy) async {
        trackingPolicy = policy

        let captureStatus: CaptureStatus = policy.captureEnabled ? .recording : .paused
        let phase: RuntimePhase = policy.captureEnabled && policy.summariesEnabled
            ? currentSnapshot.phase
            : .observing

        currentSnapshot = RuntimeSnapshot(
            phase: phase,
            captureStatus: captureStatus,
            statusMessage: statusMessage(for: policy),
            lastActivityAt: currentSnapshot.lastActivityAt
        )
    }

    public func currentTrackingPolicy() -> ActivityTrackingPolicy {
        trackingPolicy
    }

    private func statusMessage(for policy: ActivityTrackingPolicy) -> String {
        if !policy.captureEnabled {
            return "Screenpipe recording paused"
        }
        if !policy.summariesEnabled {
            return "Continue summaries paused \u{00B7} Screenpipe is still recording"
        }
        if policy.schedule.isEnabled {
            return "Screenpipe recording \u{00B7} Continue summaries \(policy.schedule.displayRange)"
        }
        return "Screenpipe recording \u{00B7} Continue summaries enabled"
    }
}

public struct PreviewCheckpointProvider: CheckpointProviding {
    private let checkpoints: [Checkpoint]

    public init(
        checkpoints: [Checkpoint] = [
            PreviewContent.latestCheckpoint,
            PreviewContent.earlierCheckpoint
        ]
    ) {
        self.checkpoints = checkpoints.sorted { $0.createdAt > $1.createdAt }
    }

    public func latest() async throws -> Checkpoint? {
        checkpoints.first
    }

    public func history(limit: Int) async throws -> [Checkpoint] {
        Array(checkpoints.prefix(max(0, limit)))
    }
}

public actor PreviewVoiceProvider: VoiceProviding {
    private var currentSnapshot = VoiceSnapshot(
        state: .disconnected,
        levels: Array(repeating: 0.08, count: 16)
    )
    private var resumeRequestHandler: ResumeRequestHandler?

    public init() {}

    public func snapshot() async -> VoiceSnapshot {
        currentSnapshot
    }

    public func start(briefing: String) async throws {
        currentSnapshot = VoiceSnapshot(
            state: .listening,
            levels: PreviewContent.listeningLevels
        )
    }

    public func stop() async {
        currentSnapshot = VoiceSnapshot(
            state: .disconnected,
            levels: Array(repeating: 0.08, count: 16)
        )
    }

    public func setResumeRequestHandler(_ handler: ResumeRequestHandler?) async {
        resumeRequestHandler = handler
    }
}

public struct PreviewResumeProvider: ResumeProviding {
    private let checkpoint: Checkpoint

    public init(checkpoint: Checkpoint = PreviewContent.latestCheckpoint) {
        self.checkpoint = checkpoint
    }

    public func preview(checkpointID: String) async throws -> ResumePreview {
        guard checkpointID == checkpoint.id else {
            throw ContinueServiceError.checkpointNotFound
        }

        return ResumePreview(
            checkpointID: checkpoint.id,
            targets: checkpoint.resumeTargets
        )
    }

    public func execute(
        checkpointID: String,
        targetIDs: Set<String>
    ) async throws -> [ResumeResult] {
        let preview = try await preview(checkpointID: checkpointID)
        let availableIDs = Set(preview.targets.map(\.id))
        guard targetIDs.isSubset(of: availableIDs) else {
            throw ContinueServiceError.invalidResumeTargets
        }

        return preview.targets
            .filter { targetIDs.contains($0.id) }
            .map { ResumeResult(target: $0, outcome: .opened) }
    }
}
