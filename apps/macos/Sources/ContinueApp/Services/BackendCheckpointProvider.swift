import ContinueCore
import Foundation

actor BackendCheckpointProvider: CheckpointProviding, SummaryGenerating {
    private let baseURL: URL

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? Self.configuredBaseURL()
    }

    func latest() async throws -> Checkpoint? {
        let envelope: CheckpointEnvelope = try await request(
            path: "api/checkpoint",
            method: "GET"
        )
        guard let payload = envelope.checkpoint else { return nil }
        return try payload.makeCheckpoint()
    }

    func history(limit: Int) async throws -> [Checkpoint] {
        guard limit > 0 else { return [] }

        let envelope: CheckpointEnvelope = try await request(
            path: "api/checkpoint",
            method: "GET"
        )
        return try envelope.checkpoints
            .prefix(limit)
            .map { try $0.makeCheckpoint() }
    }

    func generateSummary() async throws {
        let _: SummaryResponse = try await request(
            path: "api/summary",
            method: "POST"
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = method == "POST" ? 90 : 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BackendCheckpointError.network(
                path: path,
                baseURL: baseURL.absoluteString,
                message: error.localizedDescription
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendCheckpointError.invalidResponse(path: path)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BackendCheckpointError.http(
                path: path,
                statusCode: httpResponse.statusCode,
                message: Self.serverMessage(from: data)
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw BackendCheckpointError.invalidPayload(
                path: path,
                message: error.localizedDescription
            )
        }
    }

    private static func configuredBaseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let candidates = [
            environment["CONTINUE_BACKEND_URL"],
            Bundle.main.object(forInfoDictionaryKey: "ContinueBackendURL") as? String,
            "http://127.0.0.1:3000"
        ]

        for candidate in candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            guard let url = URL(string: candidate), url.scheme != nil, url.host != nil else {
                continue
            }
            return url
        }

        return URL(string: "http://127.0.0.1:3000")!
    }

    private static func serverMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        for key in ["error", "message"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

private struct CheckpointEnvelope: Decodable, Sendable {
    let checkpoint: SessionCheckpointPayload?
    let checkpoints: [SessionCheckpointPayload]

    private enum CodingKeys: String, CodingKey {
        case checkpoint
        case checkpoints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkpoint = try container.decodeIfPresent(SessionCheckpointPayload.self, forKey: .checkpoint)
        checkpoints = try container.decodeIfPresent([SessionCheckpointPayload].self, forKey: .checkpoints) ?? []
    }
}

private struct SummaryResponse: Decodable, Sendable {
    let summary: String?
    let checkpoint: SessionCheckpointPayload?
}

private struct SessionCheckpointPayload: Decodable, Sendable {
    struct KeyActivity: Decodable, Sendable {
        let timestamp: String?
        let app: String
        let action: String
        let subject: String?
        let evidence: String
    }

    struct ResumeTarget: Decodable, Sendable {
        let type: String
        let value: String
        let label: String?
    }

    let id: String
    let startedAt: String?
    let endedAt: String
    let project: String
    let currentTask: String
    let summary: String
    let lastAction: String
    let nextAction: String
    let keyActivities: [KeyActivity]
    let resumeTargets: [ResumeTarget]
    let confidence: Double
    let sourceWindowMinutes: Int
    let sourceEventCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case endedAt
        case project
        case currentTask
        case summary
        case lastAction
        case nextAction
        case keyActivities
        case resumeTargets
        case confidence
        case sourceWindowMinutes
        case sourceEventCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        endedAt = try container.decode(String.self, forKey: .endedAt)
        project = try container.decode(String.self, forKey: .project)
        currentTask = try container.decode(String.self, forKey: .currentTask)
        summary = try container.decode(String.self, forKey: .summary)
        lastAction = try container.decode(String.self, forKey: .lastAction)
        nextAction = try container.decode(String.self, forKey: .nextAction)
        keyActivities = try container.decodeIfPresent([KeyActivity].self, forKey: .keyActivities) ?? []
        resumeTargets = try container.decodeIfPresent([ResumeTarget].self, forKey: .resumeTargets) ?? []
        confidence = try container.decode(Double.self, forKey: .confidence)
        sourceWindowMinutes = try container.decode(Int.self, forKey: .sourceWindowMinutes)
        sourceEventCount = try container.decodeIfPresent(Int.self, forKey: .sourceEventCount)
    }

    func makeCheckpoint() throws -> Checkpoint {
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
            throw BackendCheckpointError.invalidCheckpoint(id: id)
        }

        guard let createdAt = Self.parseDate(endedAt) else {
            throw BackendCheckpointError.invalidTimestamp(endedAt)
        }

        let evidence = keyActivities.enumerated().map { index, activity in
            EvidenceReference(
                id: "\(id)-activity-\(index)",
                sourceLabel: activityLabel(activity),
                capturedAt: activity.timestamp.flatMap(Self.parseDate) ?? createdAt
            )
        }

        let resolvedEvidence = evidence.isEmpty
            ? [EvidenceReference(
                id: "\(id)-source",
                sourceLabel: "\(project) · Screenpipe activity",
                capturedAt: createdAt
            )]
            : evidence

        return Checkpoint(
            id: id,
            createdAt: createdAt,
            awayDurationMinutes: sourceWindowMinutes,
            headline: currentTask,
            summary: summary,
            completed: [lastAction],
            nextSteps: [nextAction],
            confidence: mappedConfidence,
            evidence: resolvedEvidence,
            resumeTargets: resumeTargets.enumerated().map { index, target in
                ContinueCore.ResumeTarget(
                    id: "\(id)-target-\(index)",
                    kind: target.kind,
                    title: target.label ?? target.value,
                    detail: target.displayName,
                    locator: target.value
                )
            },
            isPreview: false
        )
    }

    private var mappedConfidence: Confidence {
        if confidence >= 0.8 { return .high }
        if confidence >= 0.5 { return .medium }
        return .low
    }

    private func activityLabel(_ activity: KeyActivity) -> String {
        let subject = activity.subject.map { " — \($0)" } ?? ""
        return "\(activity.app): \(activity.action)\(subject) · \(activity.evidence)"
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private extension SessionCheckpointPayload.ResumeTarget {
    var kind: ResumeTargetKind {
        switch type {
        case "app":
            .application
        case "file":
            .file
        default:
            .url
        }
    }

    var displayName: String {
        switch type {
        case "app":
            "Application"
        case "file":
            "File"
        default:
            "Browser tab"
        }
    }
}

private enum BackendCheckpointError: LocalizedError {
    case network(path: String, baseURL: String, message: String)
    case invalidResponse(path: String)
    case http(path: String, statusCode: Int, message: String?)
    case invalidPayload(path: String, message: String)
    case invalidCheckpoint(id: String)
    case invalidTimestamp(String)

    var errorDescription: String? {
        switch self {
        case let .network(path, baseURL, message):
            return "The local summary service at \(baseURL) could not be reached for /\(path): \(message). Start the web backend and try again."
        case let .invalidResponse(path):
            return "The local summary service returned an invalid response for /\(path)."
        case let .http(path, statusCode, message):
            let detail = message.map { ": \($0)" } ?? ""
            return "The local summary service rejected /\(path) (HTTP \(statusCode))\(detail)."
        case let .invalidPayload(path, message):
            return "The local summary service returned invalid data for /\(path): \(message)."
        case let .invalidCheckpoint(id):
            return "The local summary service returned an invalid checkpoint\(id.isEmpty ? "" : " \(id)")."
        case let .invalidTimestamp(value):
            return "The local summary service returned an invalid checkpoint timestamp: \(value)."
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
