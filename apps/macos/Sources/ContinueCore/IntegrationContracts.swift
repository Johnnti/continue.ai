import Foundation

public struct ActivityEventV1: Codable, Equatable, Sendable {
    public let timestamp: String
    public let appName: String?
    public let windowTitle: String?
    public let text: String?
    public let url: String?
    public let filePath: String?
    public let durationSeconds: Double?

    public init(
        timestamp: String,
        appName: String? = nil,
        windowTitle: String? = nil,
        text: String? = nil,
        url: String? = nil,
        filePath: String? = nil,
        durationSeconds: Double? = nil
    ) {
        self.timestamp = timestamp
        self.appName = appName
        self.windowTitle = windowTitle
        self.text = text
        self.url = url
        self.filePath = filePath
        self.durationSeconds = durationSeconds
    }
}

public enum ResumeTargetTypeV1: String, Codable, Sendable {
    case url
    case file
    case app
}

public struct ResumeTargetV1: Codable, Equatable, Sendable {
    public let type: ResumeTargetTypeV1
    public let value: String
    public let label: String?

    public init(type: ResumeTargetTypeV1, value: String, label: String? = nil) {
        self.type = type
        self.value = value
        self.label = label
    }
}

public struct SessionCheckpointV1: Codable, Equatable, Sendable {
    public let id: String
    public let startedAt: String?
    public let endedAt: String
    public let project: String
    public let currentTask: String
    public let summary: String
    public let lastAction: String
    public let nextAction: String
    public let resumeTargets: [ResumeTargetV1]
    public let confidence: Double
    public let sourceWindowMinutes: Int

    public init(
        id: String,
        startedAt: String? = nil,
        endedAt: String,
        project: String,
        currentTask: String,
        summary: String,
        lastAction: String,
        nextAction: String,
        resumeTargets: [ResumeTargetV1],
        confidence: Double,
        sourceWindowMinutes: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.project = project
        self.currentTask = currentTask
        self.summary = summary
        self.lastAction = lastAction
        self.nextAction = nextAction
        self.resumeTargets = resumeTargets
        self.confidence = confidence
        self.sourceWindowMinutes = sourceWindowMinutes
    }

    public func makeCheckpoint(awayDurationMinutes: Int) throws -> Checkpoint {
        guard
            !id.isEmpty,
            !project.isEmpty,
            !currentTask.isEmpty,
            !summary.isEmpty,
            !lastAction.isEmpty,
            !nextAction.isEmpty,
            (0...1).contains(confidence),
            sourceWindowMinutes > 0,
            resumeTargets.allSatisfy({ !$0.value.isEmpty })
        else {
            throw ContractValidationError.invalidCheckpoint
        }

        guard let endedAtDate = Self.parseDate(endedAt) else {
            throw ContractValidationError.invalidTimestamp(endedAt)
        }

        return Checkpoint(
            id: id,
            project: project,
            createdAt: endedAtDate,
            awayDurationMinutes: max(0, awayDurationMinutes),
            headline: currentTask,
            summary: summary,
            completed: [lastAction],
            nextSteps: [nextAction],
            confidence: mappedConfidence,
            evidence: [
                EvidenceReference(
                    id: "\(id)-source",
                    sourceLabel: "Screenpipe · \(sourceWindowMinutes)-minute window",
                    capturedAt: endedAtDate
                )
            ],
            resumeTargets: resumeTargets.enumerated().map { index, target in
                ResumeTarget(
                    id: "\(id)-target-\(index)",
                    kind: target.type.mappedKind,
                    title: target.label ?? target.value,
                    detail: target.type.displayName,
                    locator: target.value
                )
            }
        )
    }

    private var mappedConfidence: Confidence {
        if confidence >= 0.8 { return .high }
        if confidence >= 0.5 { return .medium }
        return .low
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}

public enum ContractValidationError: Error, Equatable, Sendable {
    case fixtureMissing(String)
    case invalidCheckpoint
    case invalidTimestamp(String)
}

public enum ContractFixtures {
    public static func sessionCheckpointV1() throws -> SessionCheckpointV1 {
        try decode(SessionCheckpointV1.self, named: "session-checkpoint-v1")
    }

    public static func normalizedActivityV1() throws -> [ActivityEventV1] {
        try decode([ActivityEventV1].self, named: "normalized-activity-v1")
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        named name: String
    ) throws -> Value {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Contracts"
        ) else {
            throw ContractValidationError.fixtureMissing(name)
        }

        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }
}

private extension ResumeTargetTypeV1 {
    var mappedKind: ResumeTargetKind {
        switch self {
        case .url:
            .url
        case .file:
            .file
        case .app:
            .application
        }
    }

    var displayName: String {
        switch self {
        case .url:
            "Browser tab"
        case .file:
            "File"
        case .app:
            "Application"
        }
    }
}
