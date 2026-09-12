import Foundation

public struct ContinueIntegrationConfiguration: Sendable {
    public static let defaultPublicAgentID = "agent_6701m2aempkqeh7a0922tc0b0krr"

    public let memoryDatabaseURL: URL
    public let elevenLabsAgentID: String?
    public let elevenLabsTokenURL: URL?
    public let elevenLabsUserID: String?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        memoryDatabaseURL = Self.resolveMemoryDatabaseURL(environment: environment)
        elevenLabsAgentID = Self.value(
            forKeys: ["CONTINUE_ELEVENLABS_AGENT_ID", "ELEVENLABS_AGENT_ID"],
            in: environment
        ) ?? Self.bundleValue(forKey: "ContinueElevenLabsAgentID") ?? Self.defaultPublicAgentID
        elevenLabsTokenURL = Self.value(
            forKeys: ["CONTINUE_ELEVENLABS_TOKEN_URL"],
            in: environment
        )
        .flatMap(URL.init(string:))
            ?? Self.bundleValue(forKey: "ContinueElevenLabsTokenURL")
                .flatMap(URL.init(string:))
        elevenLabsUserID = Self.value(
            forKeys: ["CONTINUE_ELEVENLABS_USER_ID", "ELEVENLABS_USER_ID"],
            in: environment
        )
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
