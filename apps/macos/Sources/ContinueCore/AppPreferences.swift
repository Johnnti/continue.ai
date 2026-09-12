public struct AppPreferences: Equatable, Sendable {
    public var interpretationEnabled: Bool
    public var voiceBriefingsEnabled: Bool
    public var idleThresholdMinutes: Int
    public var checkpointRetentionDays: Int

    public init(
        interpretationEnabled: Bool,
        voiceBriefingsEnabled: Bool,
        idleThresholdMinutes: Int,
        checkpointRetentionDays: Int
    ) {
        self.interpretationEnabled = interpretationEnabled
        self.voiceBriefingsEnabled = voiceBriefingsEnabled
        self.idleThresholdMinutes = idleThresholdMinutes
        self.checkpointRetentionDays = checkpointRetentionDays
    }

    public static let previewDefaults = AppPreferences(
        interpretationEnabled: true,
        voiceBriefingsEnabled: true,
        idleThresholdMinutes: 4,
        checkpointRetentionDays: 7
    )
}
