import Foundation

public enum CheckpointTrigger: String, CaseIterable, Codable, Sendable {
    case automatic
    case manual
    case automaticAndManual

    public var title: String {
        switch self {
        case .automatic:
            "Automatic"
        case .manual:
            "Manual only"
        case .automaticAndManual:
            "Automatic + manual"
        }
    }

    public var description: String {
        switch self {
        case .automatic:
            "Create a checkpoint after the away threshold."
        case .manual:
            "Create a checkpoint only after you mark that you are stepping away."
        case .automaticAndManual:
            "Use the away threshold and the manual stepping-away action."
        }
    }

    public var allowsAutomatic: Bool {
        self != .manual
    }

    public var allowsManual: Bool {
        self != .automatic
    }
}

public struct TrackingSchedule: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    public var startHour: Int
    public var endHour: Int

    public init(isEnabled: Bool, startHour: Int, endHour: Int) {
        self.isEnabled = isEnabled
        self.startHour = Self.clampedHour(startHour)
        self.endHour = Self.clampedHour(endHour)
    }

    public static let allDay = TrackingSchedule(
        isEnabled: false,
        startHour: 9,
        endHour: 17
    )

    public var displayRange: String {
        "\(Self.formatHour(startHour))–\(Self.formatHour(endHour))"
    }

    public func contains(hour: Int) -> Bool {
        guard isEnabled else { return true }

        let normalizedHour = Self.clampedHour(hour)
        if startHour == endHour {
            return true
        }
        if startHour < endHour {
            return normalizedHour >= startHour && normalizedHour < endHour
        }
        return normalizedHour >= startHour || normalizedHour < endHour
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case startHour
        case endHour
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false,
            startHour: try container.decodeIfPresent(Int.self, forKey: .startHour) ?? 9,
            endHour: try container.decodeIfPresent(Int.self, forKey: .endHour) ?? 17
        )
    }

    public static func hourLabel(_ hour: Int) -> String {
        formatHour(hour)
    }

    private static func clampedHour(_ hour: Int) -> Int {
        min(max(hour, 0), 23)
    }

    private static func formatHour(_ hour: Int) -> String {
        let normalizedHour = clampedHour(hour)
        let suffix = normalizedHour < 12 ? "AM" : "PM"
        let twelveHour = normalizedHour % 12 == 0 ? 12 : normalizedHour % 12
        return "\(twelveHour) \(suffix)"
    }
}

public struct ActivityTrackingPolicy: Equatable, Codable, Sendable {
    public let captureEnabled: Bool
    public let summariesEnabled: Bool
    public let checkpointTrigger: CheckpointTrigger
    public let idleThresholdMinutes: Int
    public let observationWindowMinutes: Int
    public let schedule: TrackingSchedule
    public let excludedApplications: [String]
    public let checkpointRetentionDays: Int
    public let screenpipeRetentionDays: Int

    public init(
        captureEnabled: Bool,
        summariesEnabled: Bool,
        checkpointTrigger: CheckpointTrigger,
        idleThresholdMinutes: Int,
        observationWindowMinutes: Int,
        schedule: TrackingSchedule,
        excludedApplications: [String],
        checkpointRetentionDays: Int,
        screenpipeRetentionDays: Int
    ) {
        self.captureEnabled = captureEnabled
        self.summariesEnabled = summariesEnabled
        self.checkpointTrigger = checkpointTrigger
        self.idleThresholdMinutes = idleThresholdMinutes
        self.observationWindowMinutes = observationWindowMinutes
        self.schedule = schedule
        self.excludedApplications = excludedApplications
        self.checkpointRetentionDays = checkpointRetentionDays
        self.screenpipeRetentionDays = screenpipeRetentionDays
    }

    public init(preferences: AppPreferences) {
        captureEnabled = preferences.captureEnabled
        summariesEnabled = preferences.interpretationEnabled
        checkpointTrigger = preferences.checkpointTrigger
        idleThresholdMinutes = preferences.idleThresholdMinutes
        observationWindowMinutes = preferences.observationWindowMinutes
        schedule = preferences.trackingSchedule
        excludedApplications = preferences.excludedApplications
        checkpointRetentionDays = preferences.checkpointRetentionDays
        screenpipeRetentionDays = preferences.screenpipeRetentionDays
    }

    private enum CodingKeys: String, CodingKey {
        case captureEnabled
        case summariesEnabled
        case checkpointTrigger
        case idleThresholdMinutes
        case observationWindowMinutes
        case schedule
        case excludedApplications
        case checkpointRetentionDays
        case screenpipeRetentionDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ActivityTrackingPolicy(preferences: .previewDefaults)
        self.init(
            captureEnabled: try container.decodeIfPresent(Bool.self, forKey: .captureEnabled)
                ?? defaults.captureEnabled,
            summariesEnabled: try container.decodeIfPresent(Bool.self, forKey: .summariesEnabled)
                ?? defaults.summariesEnabled,
            checkpointTrigger: try container.decodeIfPresent(CheckpointTrigger.self, forKey: .checkpointTrigger)
                ?? defaults.checkpointTrigger,
            idleThresholdMinutes: try container.decodeIfPresent(Int.self, forKey: .idleThresholdMinutes)
                ?? defaults.idleThresholdMinutes,
            observationWindowMinutes: try container.decodeIfPresent(Int.self, forKey: .observationWindowMinutes)
                ?? defaults.observationWindowMinutes,
            schedule: try container.decodeIfPresent(TrackingSchedule.self, forKey: .schedule)
                ?? defaults.schedule,
            excludedApplications: try container.decodeIfPresent([String].self, forKey: .excludedApplications)
                ?? defaults.excludedApplications,
            checkpointRetentionDays: try container.decodeIfPresent(Int.self, forKey: .checkpointRetentionDays)
                ?? defaults.checkpointRetentionDays,
            screenpipeRetentionDays: try container.decodeIfPresent(Int.self, forKey: .screenpipeRetentionDays)
                ?? defaults.screenpipeRetentionDays
        )
    }
}

public struct AppPreferences: Equatable, Codable, Sendable {
    public var captureEnabled: Bool
    public var interpretationEnabled: Bool
    public var voiceBriefingsEnabled: Bool
    public var idleThresholdMinutes: Int
    public var observationWindowMinutes: Int
    public var checkpointTrigger: CheckpointTrigger
    public var trackingSchedule: TrackingSchedule
    public var excludedApplications: [String]
    public var checkpointRetentionDays: Int
    public var screenpipeRetentionDays: Int

    public init(
        captureEnabled: Bool = true,
        interpretationEnabled: Bool,
        voiceBriefingsEnabled: Bool,
        idleThresholdMinutes: Int,
        checkpointRetentionDays: Int,
        observationWindowMinutes: Int = 30,
        checkpointTrigger: CheckpointTrigger = .automaticAndManual,
        trackingSchedule: TrackingSchedule = .allDay,
        excludedApplications: [String] = [],
        screenpipeRetentionDays: Int = 0
    ) {
        self.captureEnabled = captureEnabled
        self.interpretationEnabled = interpretationEnabled
        self.voiceBriefingsEnabled = voiceBriefingsEnabled
        self.idleThresholdMinutes = Self.clampedIdleThreshold(idleThresholdMinutes)
        self.observationWindowMinutes = Self.validObservationWindow(observationWindowMinutes)
        self.checkpointTrigger = checkpointTrigger
        self.trackingSchedule = trackingSchedule
        self.excludedApplications = Self.normalizedApplications(excludedApplications)
        self.checkpointRetentionDays = Self.validCheckpointRetention(checkpointRetentionDays)
        self.screenpipeRetentionDays = Self.validScreenpipeRetention(screenpipeRetentionDays)
    }

    public static let previewDefaults = AppPreferences(
        captureEnabled: true,
        interpretationEnabled: true,
        voiceBriefingsEnabled: true,
        idleThresholdMinutes: 4,
        checkpointRetentionDays: 7,
        observationWindowMinutes: 30,
        checkpointTrigger: .automaticAndManual,
        trackingSchedule: .allDay,
        excludedApplications: [],
        screenpipeRetentionDays: 0
    )

    public static let observationWindowOptions = [5, 15, 30, 60]
    public static let checkpointRetentionOptions = [1, 7, 30]
    public static let screenpipeRetentionOptions = [0, 1, 7, 30]

    public static func normalizedApplications(_ applications: [String]) -> [String] {
        var seen = Set<String>()
        return applications.compactMap { application in
            let normalized = application.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }

            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
    }

    private static func clampedIdleThreshold(_ minutes: Int) -> Int {
        min(max(minutes, 1), 60)
    }

    private static func validObservationWindow(_ minutes: Int) -> Int {
        observationWindowOptions.min {
            abs($0 - minutes) < abs($1 - minutes)
        } ?? 30
    }

    private static func validCheckpointRetention(_ days: Int) -> Int {
        checkpointRetentionOptions.contains(days) ? days : 7
    }

    private static func validScreenpipeRetention(_ days: Int) -> Int {
        screenpipeRetentionOptions.contains(days) ? days : 0
    }

    private enum CodingKeys: String, CodingKey {
        case captureEnabled
        case interpretationEnabled
        case voiceBriefingsEnabled
        case idleThresholdMinutes
        case observationWindowMinutes
        case checkpointTrigger
        case trackingSchedule
        case excludedApplications
        case checkpointRetentionDays
        case screenpipeRetentionDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            captureEnabled: try container.decodeIfPresent(Bool.self, forKey: .captureEnabled) ?? true,
            interpretationEnabled: try container.decodeIfPresent(Bool.self, forKey: .interpretationEnabled) ?? true,
            voiceBriefingsEnabled: try container.decodeIfPresent(Bool.self, forKey: .voiceBriefingsEnabled) ?? true,
            idleThresholdMinutes: try container.decodeIfPresent(Int.self, forKey: .idleThresholdMinutes) ?? 4,
            checkpointRetentionDays: try container.decodeIfPresent(Int.self, forKey: .checkpointRetentionDays) ?? 7,
            observationWindowMinutes: try container.decodeIfPresent(Int.self, forKey: .observationWindowMinutes) ?? 30,
            checkpointTrigger: try container.decodeIfPresent(CheckpointTrigger.self, forKey: .checkpointTrigger) ?? .automaticAndManual,
            trackingSchedule: try container.decodeIfPresent(TrackingSchedule.self, forKey: .trackingSchedule) ?? .allDay,
            excludedApplications: try container.decodeIfPresent([String].self, forKey: .excludedApplications) ?? [],
            screenpipeRetentionDays: try container.decodeIfPresent(Int.self, forKey: .screenpipeRetentionDays) ?? 0
        )
    }
}
