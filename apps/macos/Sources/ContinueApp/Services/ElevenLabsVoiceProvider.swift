import AVFoundation
import ContinueCore
import Foundation

enum ElevenLabsVoiceError: LocalizedError, Sendable {
    case invalidResponse
    case requestFailed(String)
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The Continue voice service returned an invalid audio response."
        case let .requestFailed(message):
            "The Continue voice service failed: \(message)"
        case .playbackFailed:
            "The generated recap could not be played."
        }
    }
}

/// Reads a completed checkpoint through the same server-side ElevenLabs TTS
/// endpoint as the web app, keeping the API key out of the application bundle.
final class ElevenLabsVoiceProvider: NSObject, VoiceProviding, AVAudioPlayerDelegate, @unchecked Sendable {
    private let configuration: ContinueIntegrationConfiguration
    private var player: AVAudioPlayer?
    private var currentSnapshot = VoiceSnapshot(
        state: .disconnected,
        levels: Array(repeating: 0.08, count: 16)
    )

    init(
        configuration: ContinueIntegrationConfiguration,
        checkpointProvider _: any CheckpointProviding
    ) {
        self.configuration = configuration
    }

    func snapshot() async -> VoiceSnapshot {
        await MainActor.run { currentSnapshot }
    }

    func start(briefing: String) async throws {
        await setSnapshot(
            VoiceSnapshot(
                state: .connecting,
                levels: Array(repeating: 0.16, count: 16)
            )
        )

        var request = URLRequest(url: configuration.elevenLabsSpeechURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SpeechRequest(text: briefing))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ElevenLabsVoiceError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                throw ElevenLabsVoiceError.requestFailed(
                    payload?.error ?? "HTTP \(httpResponse.statusCode)"
                )
            }

            let audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer.delegate = self
            audioPlayer.prepareToPlay()
            guard audioPlayer.play() else {
                throw ElevenLabsVoiceError.playbackFailed
            }

            await MainActor.run {
                player?.stop()
                player = audioPlayer
                currentSnapshot = VoiceSnapshot(
                    state: .speaking,
                    levels: Array(repeating: 0.62, count: 16)
                )
            }
        } catch let error as ElevenLabsVoiceError {
            await setFailed(error.localizedDescription)
            throw error
        } catch {
            let wrapped = ElevenLabsVoiceError.requestFailed(error.localizedDescription)
            await setFailed(wrapped.localizedDescription)
            throw wrapped
        }
    }

    func stop() async {
        await MainActor.run {
            player?.stop()
            player = nil
            currentSnapshot = VoiceSnapshot(
                state: .disconnected,
                levels: Array(repeating: 0.08, count: 16)
            )
        }
    }

    func setResumeRequestHandler(_: ResumeRequestHandler?) async {}

    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        Task { await stop() }
    }

    func audioPlayerDecodeErrorDidOccur(_: AVAudioPlayer, error: Error?) {
        Task { await setFailed(error?.localizedDescription ?? "Audio decoding failed") }
    }

    private func setSnapshot(_ snapshot: VoiceSnapshot) async {
        await MainActor.run { currentSnapshot = snapshot }
    }

    private func setFailed(_ message: String) async {
        await MainActor.run {
            player = nil
            currentSnapshot = VoiceSnapshot(
                state: .failed(message: message),
                levels: Array(repeating: 0.08, count: 16)
            )
        }
    }
}

private struct SpeechRequest: Encodable {
    let text: String
}

private struct ErrorResponse: Decodable {
    let error: String?
}
