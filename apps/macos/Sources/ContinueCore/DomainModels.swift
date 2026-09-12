import Foundation

public enum RuntimePhase: String, Codable, Sendable {
    case booting
    case observing
    case away
    case returning
}

public enum CaptureStatus: Equatable, Sendable {
    case checking
    case available
    case unavailable(reason: String)
}

public struct RuntimeSnapshot: Equatable, Sendable {
    public let phase: RuntimePhase
    public let captureStatus: CaptureStatus
    public let statusMessage: String
    public let lastActivityAt: Date?

    public init(
        phase: RuntimePhase,
        captureStatus: CaptureStatus,
        statusMessage: String,
        lastActivityAt: Date?
    ) {
        self.phase = phase
        self.captureStatus = captureStatus
        self.statusMessage = statusMessage
        self.lastActivityAt = lastActivityAt
    }
}

public enum Confidence: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct EvidenceReference: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sourceLabel: String
    public let capturedAt: Date

    public init(id: String, sourceLabel: String, capturedAt: Date) {
        self.id = id
        self.sourceLabel = sourceLabel
        self.capturedAt = capturedAt
    }
}

public enum ResumeTargetKind: String, Codable, Sendable {
    case application
    case file
    case url
}

public struct ResumeTarget: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: ResumeTargetKind
    public let title: String
    public let detail: String
    public let locator: String

    public init(
        id: String,
        kind: ResumeTargetKind,
        title: String,
        detail: String,
        locator: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.locator = locator
    }
}

public struct Checkpoint: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let awayDurationMinutes: Int
    public let headline: String
    public let summary: String
    public let completed: [String]
    public let nextSteps: [String]
    public let confidence: Confidence
    public let evidence: [EvidenceReference]
    public let resumeTargets: [ResumeTarget]

    public init(
        id: String,
        createdAt: Date,
        awayDurationMinutes: Int,
        headline: String,
        summary: String,
        completed: [String],
        nextSteps: [String],
        confidence: Confidence,
        evidence: [EvidenceReference],
        resumeTargets: [ResumeTarget]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.awayDurationMinutes = awayDurationMinutes
        self.headline = headline
        self.summary = summary
        self.completed = completed
        self.nextSteps = nextSteps
        self.confidence = confidence
        self.evidence = evidence
        self.resumeTargets = resumeTargets
    }
}

public enum VoiceState: Equatable, Sendable {
    case disconnected
    case connecting
    case listening
    case thinking
    case speaking
    case muted
    case failed(message: String)
}

public struct VoiceSnapshot: Equatable, Sendable {
    public let state: VoiceState
    public let levels: [Double]

    public init(state: VoiceState, levels: [Double]) {
        self.state = state
        self.levels = levels
    }
}

public struct ResumePreview: Equatable, Sendable {
    public let checkpointID: String
    public let targets: [ResumeTarget]

    public init(checkpointID: String, targets: [ResumeTarget]) {
        self.checkpointID = checkpointID
        self.targets = targets
    }
}

public enum ResumeOutcome: Equatable, Sendable {
    case opened
    case failed(message: String)
}

public struct ResumeResult: Equatable, Identifiable, Sendable {
    public let target: ResumeTarget
    public let outcome: ResumeOutcome

    public var id: String { target.id }

    public init(target: ResumeTarget, outcome: ResumeOutcome) {
        self.target = target
        self.outcome = outcome
    }
}

public struct NormalizedActivitySummary: Equatable, Sendable {
    public let interval: DateInterval
    public let applications: [String]
    public let windowTitles: [String]
    public let textDigest: String
    public let isMeaningful: Bool

    public init(
        interval: DateInterval,
        applications: [String],
        windowTitles: [String],
        textDigest: String,
        isMeaningful: Bool
    ) {
        self.interval = interval
        self.applications = applications
        self.windowTitles = windowTitles
        self.textDigest = textDigest
        self.isMeaningful = isMeaningful
    }
}
