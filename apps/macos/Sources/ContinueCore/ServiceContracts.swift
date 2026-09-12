import Foundation

public protocol ActivityProviding: Sendable {
    func health() async -> CaptureStatus
    func summary(for interval: DateInterval) async throws -> NormalizedActivitySummary
}

public protocol RuntimeProviding: Sendable {
    func snapshot() async -> RuntimeSnapshot
}

public protocol RuntimeControlling: Sendable {
    func markSteppingAway() async
    func setCaptureEnabled(_ isEnabled: Bool) async
    func setSummariesEnabled(_ isEnabled: Bool) async
    func updateTrackingPolicy(_ policy: ActivityTrackingPolicy) async
}

public protocol CheckpointProviding: Sendable {
    func latest() async throws -> Checkpoint?
    func history(limit: Int) async throws -> [Checkpoint]
}

public protocol VoiceProviding: Sendable {
    func snapshot() async -> VoiceSnapshot
    func start(briefing: String) async throws
    func stop() async
    func setResumeRequestHandler(_ handler: ResumeRequestHandler?) async
}

public typealias ResumeRequestHandler = @MainActor @Sendable () -> Void

public protocol ResumeProviding: Sendable {
    func preview(checkpointID: String) async throws -> ResumePreview
    func execute(checkpointID: String, targetIDs: Set<String>) async throws -> [ResumeResult]
}

public enum ContinueServiceError: Error, Equatable, LocalizedError, Sendable {
    case checkpointNotFound
    case invalidResumeTargets
    case databaseUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .checkpointNotFound:
            "The requested checkpoint was not found."
        case .invalidResumeTargets:
            "The selected resume targets are no longer available."
        case let .databaseUnavailable(message):
            "The local checkpoint database is unavailable: \(message)"
        }
    }
}
