import Foundation

public actor StoredCheckpointResumeProvider: ResumeProviding {
    private let checkpointProvider: any CheckpointProviding

    public init(checkpointProvider: any CheckpointProviding) {
        self.checkpointProvider = checkpointProvider
    }

    public func preview(checkpointID: String) async throws -> ResumePreview {
        let checkpoints = try await checkpointProvider.history(limit: 100)
        guard let checkpoint = checkpoints.first(where: { $0.id == checkpointID }) else {
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
