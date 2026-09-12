import ContinueCore
import ElevenLabs
import Foundation

enum ElevenLabsVoiceError: LocalizedError, Sendable {
    case missingAgentConfiguration
    case invalidTokenResponse
    case tokenRequestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAgentConfiguration:
            "ElevenLabs is not configured with a public agent or token endpoint."
        case .invalidTokenResponse:
            "The ElevenLabs token service returned no conversation token."
        case let .tokenRequestFailed(message):
            "The ElevenLabs token service failed: \(message)"
        }
    }
}

final class ElevenLabsVoiceProvider: VoiceProviding, @unchecked Sendable {
    private let configuration: ContinueIntegrationConfiguration
    private let checkpointProvider: any CheckpointProviding
    private var conversation: Conversation?
    private var currentSnapshot = VoiceSnapshot(
        state: .disconnected,
        levels: Array(repeating: 0.08, count: 16)
    )
    private var resumeRequestHandler: ResumeRequestHandler?

    init(
        configuration: ContinueIntegrationConfiguration,
        checkpointProvider: any CheckpointProviding
    ) {
        self.configuration = configuration
        self.checkpointProvider = checkpointProvider
    }

    func snapshot() async -> VoiceSnapshot {
        await MainActor.run { currentSnapshot }
    }

    func start(briefing: String) async throws {
        await setSnapshot(
            VoiceSnapshot(
                state: .connecting,
                levels: Array(repeating: 0.12, count: 16)
            )
        )

        let checkpoint = try? await checkpointProvider.latest()
        let config = ConversationConfig(
            dynamicVariables: dynamicVariables(for: checkpoint),
            userId: configuration.elevenLabsUserID,
            onDisconnect: { [weak self] _ in
                Task { await self?.setDisconnected() }
            },
            onError: { [weak self] error in
                Task { await self?.setFailed(error.localizedDescription) }
            },
            onVadScore: { [weak self] score in
                Task { await self?.setVadScore(score) }
            },
            onUnhandledClientToolCall: { [weak self] toolCall in
                Task { await self?.handleClientToolCall(toolCall) }
            },
            onAgentStateChange: { [weak self] state in
                Task { @MainActor in
                    self?.setAgentState(state)
                }
            }
        )

        let activeConversation = try await startConversation(with: config)
        await MainActor.run {
            conversation = activeConversation
            setAgentState(activeConversation.agentState)
        }

        try await activeConversation.sendMessage(briefing)
    }

    func stop() async {
        let activeConversation = await MainActor.run { () -> Conversation? in
            let activeConversation = conversation
            conversation = nil
            currentSnapshot = VoiceSnapshot(
                state: .disconnected,
                levels: Array(repeating: 0.08, count: 16)
            )
            return activeConversation
        }
        await activeConversation?.endConversation()
    }

    func setResumeRequestHandler(_ handler: ResumeRequestHandler?) async {
        await MainActor.run {
            resumeRequestHandler = handler
        }
    }

    private func startConversation(with config: ConversationConfig) async throws -> Conversation {
        if let tokenURL = configuration.elevenLabsTokenURL {
            let token = try await fetchConversationToken(from: tokenURL)
            return try await ElevenLabs.startConversation(
                conversationToken: token,
                config: config
            )
        }

        guard let agentID = configuration.elevenLabsAgentID else {
            throw ElevenLabsVoiceError.missingAgentConfiguration
        }

        return try await ElevenLabs.startConversation(
            agentId: agentID,
            config: config
        )
    }

    private func fetchConversationToken(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw ElevenLabsVoiceError.tokenRequestFailed("HTTP \(statusCode)")
            }

            let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
            guard let token = payload.token ?? payload.conversationToken,
                  !token.isEmpty
            else {
                throw ElevenLabsVoiceError.invalidTokenResponse
            }
            return token
        } catch let error as ElevenLabsVoiceError {
            throw error
        } catch {
            throw ElevenLabsVoiceError.tokenRequestFailed(error.localizedDescription)
        }
    }

    private func dynamicVariables(for checkpoint: Checkpoint?) -> [String: String] {
        [
            "checkpoint_id": checkpoint?.id ?? "",
            "project": checkpoint?.project ?? "Continue",
            "task": checkpoint?.headline ?? "your previous task",
            "last_action": checkpoint?.completed.last ?? "working on your computer",
            "next_action": checkpoint?.nextSteps.first ?? "continue where you left off"
        ]
    }

    private func handleClientToolCall(_ toolCall: ClientToolCallEvent) async {
        let checkpoint = try? await checkpointProvider.latest()
        let result: [String: String]

        switch toolCall.toolName {
        case "get_last_session", "get_session_context":
            result = checkpointPayload(checkpoint, includeEvidence: toolCall.toolName == "get_session_context")
        case "request_resume_workspace":
            result = [
                "status": "confirmation_required",
                "message": "The local approval sheet will be shown before anything is opened."
            ]
            let handler = await MainActor.run { resumeRequestHandler }
            await MainActor.run { handler?() }
        default:
            result = [
                "status": "error",
                "message": "Unknown Continue client tool."
            ]
        }

        let activeConversation = await MainActor.run { conversation }
        guard let activeConversation else { return }
        try? await activeConversation.sendToolResult(
            for: toolCall.toolCallId,
            result: result,
            isError: result["status"] == "error"
        )
    }

    private func checkpointPayload(
        _ checkpoint: Checkpoint?,
        includeEvidence: Bool
    ) -> [String: String] {
        guard let checkpoint else {
            return [
                "status": "empty",
                "message": "No committed checkpoint is available yet."
            ]
        }

        var payload = [
            "status": "ok",
            "checkpoint_id": checkpoint.id,
            "project": checkpoint.project ?? "Continue",
            "summary": checkpoint.summary,
            "last_action": checkpoint.completed.last ?? "",
            "next_action": checkpoint.nextSteps.first ?? "",
            "confidence": checkpoint.confidence.rawValue,
            "created_at": checkpoint.createdAt.ISO8601Format()
        ]
        if includeEvidence {
            payload["evidence"] = checkpoint.evidence
                .map(\.sourceLabel)
                .joined(separator: ", ")
        }
        return payload
    }

    private func setSnapshot(_ snapshot: VoiceSnapshot) async {
        await MainActor.run { currentSnapshot = snapshot }
    }

    private func setDisconnected() async {
        await setSnapshot(
            VoiceSnapshot(
                state: .disconnected,
                levels: Array(repeating: 0.08, count: 16)
            )
        )
    }

    private func setFailed(_ message: String) async {
        await setSnapshot(
            VoiceSnapshot(
                state: .failed(message: message),
                levels: Array(repeating: 0.08, count: 16)
            )
        )
    }

    private func setVadScore(_ score: Double) async {
        let level = min(max(score, 0.08), 1)
        await MainActor.run {
            currentSnapshot = VoiceSnapshot(
                state: currentSnapshot.state,
                levels: Array(repeating: level, count: 16)
            )
        }
    }

    @MainActor
    private func setAgentState(_ state: ElevenLabs.AgentState) {
        let voiceState: VoiceState
        let level: Double
        switch state {
        case .listening:
            voiceState = .listening
            level = 0.14
        case .speaking:
            voiceState = .speaking
            level = 0.62
        case .thinking:
            voiceState = .thinking
            level = 0.28
        }
        currentSnapshot = VoiceSnapshot(
            state: voiceState,
            levels: Array(repeating: level, count: 16)
        )
    }
}

private struct TokenResponse: Decodable {
    let token: String?
    let conversationToken: String?

    private enum CodingKeys: String, CodingKey {
        case token
        case conversationToken = "conversation_token"
    }
}
