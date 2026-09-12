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
    func setSummariesEnabled(_ isEnabled: Bool) async
}

public protocol CheckpointProviding: Sendable {
    func latest() async throws -> Checkpoint?
    func history(limit: Int) async throws -> [Checkpoint]
}

public protocol VoiceProviding: Sendable {
    func snapshot() async -> VoiceSnapshot
    func start(briefing: String) async throws
    func stop() async
}

public protocol ResumeProviding: Sendable {
    func preview(checkpointID: String) async throws -> ResumePreview
    func execute(checkpointID: String, targetIDs: Set<String>) async throws -> [ResumeResult]
}

public enum ContinueServiceError: Error, Equatable, Sendable {
    case checkpointNotFound
    case invalidResumeTargets
}
