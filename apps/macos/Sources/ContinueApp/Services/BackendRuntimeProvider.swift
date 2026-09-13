import ContinueCore
import Foundation

actor BackendRuntimeProvider: RuntimeProviding, RuntimeControlling, CaptureControlling {
    private let baseURL: URL
    private var lastSnapshot = RuntimeSnapshot(
        phase: .booting,
        captureStatus: .checking,
        statusMessage: "Checking local capture…",
        lastActivityAt: nil
    )

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? Self.configuredBaseURL()
    }

    func snapshot() async -> RuntimeSnapshot {
        do {
            let status: RecordingStatus = try await request(
                path: "api/record/status",
                method: "GET"
            )
            let snapshot = makeSnapshot(status)
            lastSnapshot = snapshot
            return snapshot
        } catch {
            let message = "Continue could not read recording status: \(error.localizedDescription)"
            let snapshot = RuntimeSnapshot(
                phase: .observing,
                captureStatus: .unavailable(reason: message),
                statusMessage: message,
                lastActivityAt: lastSnapshot.lastActivityAt
            )
            lastSnapshot = snapshot
            return snapshot
        }
    }

    func markSteppingAway() async {}

    func setSummariesEnabled(_ isEnabled: Bool) async {}

    func setCaptureEnabled(_ isEnabled: Bool) async throws {
        let operation = isEnabled ? "start" : "stop"
        let status: RecordingStatus = try await request(
            path: "api/record/\(operation)",
            method: "POST"
        )

        guard status.recording == isEnabled else {
            throw BackendRuntimeError.stateMismatch(
                operation: operation,
                actualRecording: status.recording,
                backendError: status.lastError
            )
        }

        let settledStatus = try await waitForSettledStatus(
            expectedRecording: isEnabled,
            initial: status
        )
        lastSnapshot = makeSnapshot(settledStatus)
    }

    private func makeSnapshot(_ status: RecordingStatus) -> RuntimeSnapshot {
        let captureStatus: CaptureStatus = status.recording ? .recording : .paused
        let detail: String

        if let lastError = status.lastError, !lastError.isEmpty {
            detail = lastError
        } else if !status.recording, status.pendingCaptures > 0 {
            detail = "Finishing \(status.pendingCaptures) activity batch\(status.pendingCaptures == 1 ? "" : "es")…"
        } else if status.recording {
            detail = "Recording activity · \(status.capturesProcessed) captures"
        } else {
            detail = "Activity recording is off"
        }

        return RuntimeSnapshot(
            phase: .observing,
            captureStatus: captureStatus,
            statusMessage: detail,
            lastActivityAt: status.latestCapture.flatMap { Self.parseTimestamp($0.timestamp) }
        )
    }

    private func waitForSettledStatus(
        expectedRecording: Bool,
        initial: RecordingStatus
    ) async throws -> RecordingStatus {
        var status = initial
        guard !expectedRecording, status.pendingCaptures > 0 else { return status }

        for _ in 0..<240 {
            try await Task.sleep(for: .milliseconds(250))
            status = try await request(path: "api/record/status", method: "GET")
            guard !status.recording, status.pendingCaptures == 0 else { continue }
            return status
        }

        throw BackendRuntimeError.flushTimedOut
    }

    private func request<Response: Decodable>(
        path: String,
        method: String
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = method == "POST" ? 60 : 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BackendRuntimeError.network(
                path: path,
                baseURL: baseURL.absoluteString,
                message: error.localizedDescription
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendRuntimeError.invalidResponse(path: path)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BackendRuntimeError.http(
                path: path,
                statusCode: httpResponse.statusCode,
                message: Self.serverMessage(from: data)
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw BackendRuntimeError.invalidPayload(
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

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func serverMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        for key in ["error", "message", "lastError"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

private struct RecordingStatus: Decodable, Sendable {
    struct LatestCapture: Decodable, Sendable {
        let timestamp: String
    }

    let recording: Bool
    let capturesProcessed: Int
    let pendingCaptures: Int
    let latestCapture: LatestCapture?
    let lastError: String?

    private enum CodingKeys: String, CodingKey {
        case recording
        case capturesProcessed
        case pendingCaptures
        case latestCapture
        case lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recording = try container.decode(Bool.self, forKey: .recording)
        capturesProcessed = try container.decodeIfPresent(Int.self, forKey: .capturesProcessed) ?? 0
        pendingCaptures = try container.decodeIfPresent(Int.self, forKey: .pendingCaptures) ?? 0
        latestCapture = try container.decodeIfPresent(LatestCapture.self, forKey: .latestCapture)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}

private enum BackendRuntimeError: LocalizedError {
    case network(path: String, baseURL: String, message: String)
    case invalidResponse(path: String)
    case http(path: String, statusCode: Int, message: String?)
    case invalidPayload(path: String, message: String)
    case stateMismatch(operation: String, actualRecording: Bool, backendError: String?)
    case flushTimedOut

    var errorDescription: String? {
        switch self {
        case let .network(path, baseURL, message):
            return "The local recording service at \(baseURL) could not be reached for /\(path): \(message). Start the web backend and try again."
        case let .invalidResponse(path):
            return "The local recording service returned an invalid response for /\(path)."
        case let .http(path, statusCode, message):
            let detail = message.map { ": \($0)" } ?? ""
            return "The local recording service rejected /\(path) (HTTP \(statusCode))\(detail)."
        case let .invalidPayload(path, message):
            return "The local recording service returned invalid data for /\(path): \(message)."
        case let .stateMismatch(operation, actualRecording, backendError):
            let state = actualRecording ? "still recording" : "not recording"
            let detail = backendError.map { " \($0)" } ?? ""
            return "The local recording service could not \(operation) recording; it reported that it is \(state).\(detail)"
        case .flushTimedOut:
            return "The local recording service did not finish flushing the last activity batch."
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
