import Foundation

public struct ContinueIntegrationConfiguration: Sendable {
    public let memoryDatabaseURL: URL
    public let elevenLabsSpeechURL: URL
    public let chatURL: URL
    public let backendURL: URL

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        memoryDatabaseURL = Self.resolveMemoryDatabaseURL(environment: environment)
        elevenLabsSpeechURL = Self.value(
            forKeys: ["CONTINUE_ELEVENLABS_SPEECH_URL"],
            in: environment
        )
        .flatMap(URL.init(string:))
            ?? Self.bundleValue(forKey: "ContinueElevenLabsSpeechURL")
                .flatMap(URL.init(string:))
            ?? URL(string: "http://localhost:3000/api/voice/speak")!
        chatURL = Self.value(forKeys: ["CONTINUE_CHAT_URL"], in: environment)
            .flatMap(URL.init(string:))
            ?? Self.bundleValue(forKey: "ContinueChatURL").flatMap(URL.init(string:))
            ?? URL(string: "http://localhost:3000/api/chat")!
        backendURL = Self.value(forKeys: ["CONTINUE_BACKEND_URL"], in: environment)
            .flatMap(URL.init(string:))
            ?? Self.bundleValue(forKey: "ContinueBackendURL").flatMap(URL.init(string:))
            ?? URL(string: "http://localhost:3000")!
    }

    private static func value(
        forKeys keys: [String],
        in environment: [String: String]
    ) -> String? {
        keys
            .compactMap { environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func resolveMemoryDatabaseURL(environment: [String: String]) -> URL {
        if let configuredPath = value(
            forKeys: ["CONTINUE_MEMORY_DATABASE_PATH"],
            in: environment
        ) {
            return URL(fileURLWithPath: configuredPath)
        }

        if let bundledPath = bundleValue(forKey: "ContinueMemoryDatabasePath") {
            return URL(fileURLWithPath: bundledPath)
        }

        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        if let workspaceRoot = findWorkspaceRoot(startingAt: currentDirectory) {
            return workspaceRoot
                .appendingPathComponent("data", isDirectory: true)
                .appendingPathComponent("memory.sqlite")
        }

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? currentDirectory
        return applicationSupport
            .appendingPathComponent("Continue", isDirectory: true)
            .appendingPathComponent("memory.sqlite")
    }

    private static func bundleValue(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func findWorkspaceRoot(startingAt startURL: URL) -> URL? {
        var currentURL = startURL.standardizedFileURL

        while true {
            if FileManager.default.fileExists(
                atPath: currentURL.appendingPathComponent("pnpm-workspace.yaml").path
            ) {
                return currentURL
            }

            let parentURL = currentURL.deletingLastPathComponent()
            guard parentURL.path != currentURL.path else { return nil }
            currentURL = parentURL
        }
    }
}
