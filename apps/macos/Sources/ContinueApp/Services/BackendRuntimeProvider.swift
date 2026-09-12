import ContinueCore
import Foundation

actor BackendRuntimeProvider: RuntimeProviding, RuntimeControlling {
    private let baseURL: URL
    private var summariesEnabled = true
    private var lastCommandError: String?
    private var lastCommandTarget: Bool?
    private var lastSnapshot = RuntimeSnapshot(
        phase: .booting,
        captureStatus: .checking,
        statusMessage: "Checking local capture…",
        lastActivityAt: nil
    )

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func snapshot() async -> RuntimeSnapshot {
        do {
            let status: RecordingStatus = try await request(path: "api/record/status", method: "GET")
            let snapshot = makeSnapshot(status)

            if let commandError = lastCommandError,
               let commandTarget = lastCommandTarget,
               status.recording != commandTarget {
                lastCommandError = nil
                lastCommandTarget = nil
                let actualState = status.recording ? "on" : "off"
                let failedSnapshot = RuntimeSnapshot(
                    phase: snapshot.phase,
                    captureStatus: snapshot.captureStatus,
                    statusMessage: "\(commandError) The backend reports recording is \(actualState).",
                    lastActivityAt: snapshot.lastActivityAt
                )
                lastSnapshot = failedSnapshot
                return failedSnapshot
            }

            lastCommandError = nil
            lastCommandTarget = nil
            lastSnapshot = snapshot
            return snapshot
        } catch {
            let reason = lastCommandError ?? "Continue could not read recording status: \(error.localizedDescription)"
            let snapshot = RuntimeSnapshot(
                phase: .observing,
                captureStatus: .unavailable(reason: reason),
                statusMessage: reason,
                lastActivityAt: lastSnapshot.lastActivityAt
            )
            lastSnapshot = snapshot
            return snapshot
        }
    }

    func markSteppingAway() async {}

    func setCaptureEnabled(_ isEnabled: Bool) async {
        let current = await snapshot()
        let isRecording = current.captureStatus == .recording
        guard isRecording != isEnabled else { return }

        do {
            let path = isEnabled ? "api/record/start" : "api/record/stop"
            let status: RecordingStatus = try await request(path: path, method: "POST")
            guard status.recording == isEnabled else {
                throw BackendRuntimeError.stateMismatch(
                    operation: isEnabled ? "start" : "stop",
                    actualRecording: status.recording,
                    backendError: status.lastError
                )
            }

            let settledStatus = try await waitForSettledStatus(
                expectedRecording: isEnabled,
                initial: status
            )
            lastCommandError = nil
            lastCommandTarget = nil
            lastSnapshot = makeSnapshot(settledStatus)
        } catch {
            let operation = isEnabled ? "start" : "stop"
            let message = "Continue could not \(operation) recording: \(error.localizedDescription)"
            lastCommandError = message
            lastCommandTarget = isEnabled
            lastSnapshot = RuntimeSnapshot(
                phase: .observing,
                captureStatus: .unavailable(reason: message),
                statusMessage: message,
                lastActivityAt: current.lastActivityAt
            )
        }
    }

    func setSummariesEnabled(_ isEnabled: Bool) async {
        summariesEnabled = isEnabled
    }

    func updateTrackingPolicy(_ policy: ActivityTrackingPolicy) async {
        summariesEnabled = policy.summariesEnabled
        await setCaptureEnabled(policy.captureEnabled)
    }

    private func makeSnapshot(_ status: RecordingStatus) -> RuntimeSnapshot {
        let capture: CaptureStatus = status.recording ? .recording : .paused
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
            captureStatus: capture,
            statusMessage: detail,
            lastActivityAt: status.latestCapture?.timestamp
        )
    }

    private func waitForSettledStatus(
        expectedRecording: Bool,
        initial: RecordingStatus
    ) async throws -> RecordingStatus {
        var status = initial
        guard !expectedRecording, status.pendingCaptures > 0 else { return status }

        // Stopping the capture iterator flushes a partial batch in the local
        // service. Do not let the UI reload SQLite until that flush is done.
        for _ in 0..<240 {
            try await Task.sleep(for: .milliseconds(250))
            status = try await request(path: "api/record/status", method: "GET")
            guard !status.recording, status.pendingCaptures == 0 else { continue }
            return status
        }

        throw BackendRuntimeError.flushTimedOut
    }

    private func request<Response: Decodable>(path: String, method: String) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
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
                message: error.localizedDescription
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw BackendRuntimeError.invalidResponse(path: path)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendRuntimeError.http(
                path: path,
                statusCode: http.statusCode,
                message: Self.serverMessage(from: data)
            )
        }

        do {
            return try JSONDecoder.continueDecoder.decode(Response.self, from: data)
        } catch {
            throw BackendRuntimeError.invalidPayload(
                path: path,
                message: error.localizedDescription
            )
        }
    }

    private static func serverMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
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

private struct RecordingStatus: Decodable {
    struct LatestCapture: Decodable {
        let timestamp: Date
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
    case network(path: String, message: String)
    case invalidResponse(path: String)
    case http(path: String, statusCode: Int, message: String?)
    case invalidPayload(path: String, message: String)
    case stateMismatch(operation: String, actualRecording: Bool, backendError: String?)
    case flushTimedOut

    var errorDescription: String? {
        switch self {
        case let .network(path, message):
            return "The local capture service could not be reached for /\(path): \(message). Start Continue's local service and try again."
        case let .invalidResponse(path):
            return "The local capture service returned an invalid response for /\(path)."
        case let .http(path, statusCode, message):
            let detail = message.map { ": \($0)" } ?? ""
            if statusCode == 404 {
                return "The local capture service does not expose /\(path) (HTTP 404). Restart the Continue local service and try again."
            }
            return "The local capture service rejected /\(path) (HTTP \(statusCode))\(detail)."
        case let .invalidPayload(path, message):
            return "The local capture service returned invalid data for /\(path): \(message)."
        case let .stateMismatch(operation, actualRecording, backendError):
            let state = actualRecording ? "still recording" : "not recording"
            let detail = backendError.map { " \($0)" } ?? ""
            return "The local capture service could not \(operation) recording; it reported that it is \(state).\(detail)"
        case .flushTimedOut:
            return "The local capture service did not finish flushing the last activity batch."
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension JSONDecoder {
    static var continueDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
