import Foundation

public enum AppPreferencesStore {
    public static let userDefaultsKey = "continue.app-preferences.v1"

    public static func load(from defaults: UserDefaults = .standard) -> AppPreferences {
        guard
            let data = defaults.data(forKey: userDefaultsKey),
            let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else {
            return .previewDefaults
        }

        return preferences
    }

    public static func save(
        _ preferences: AppPreferences,
        to defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: userDefaultsKey)
    }

    public static func remove(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}
