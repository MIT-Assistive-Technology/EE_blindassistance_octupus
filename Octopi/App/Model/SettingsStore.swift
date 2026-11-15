import Foundation
import OctopiCore

/// UserDefaults-backed persistence for settings and small flags.
struct SettingsStore {
    private let defaults: UserDefaults
    private let settingsKey = "octopi.settings"
    private let setupKey = "octopi.setupComplete"
    private let bandKey = "octopi.bandIdentifier"
    private let beaconsKey = "octopi.pairedBeacons"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func loadSettings() -> OctopiSettings {
        guard let data = defaults.data(forKey: settingsKey), let settings = try? JSONDecoder().decode(OctopiSettings.self, from: data) else { return OctopiSettings() }
        return settings
    }

    func save(_ settings: OctopiSettings) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: settingsKey)
    }

    var setupComplete: Bool {
        get { defaults.bool(forKey: setupKey) }
        nonmutating set { defaults.set(newValue, forKey: setupKey) }
    }

    var bandIdentifier: String? {
        get { defaults.string(forKey: bandKey) }
        nonmutating set { defaults.set(newValue, forKey: bandKey) }
    }

    func loadBeacons() -> [PairedBeacon] {
        guard let data = defaults.data(forKey: beaconsKey) else { return [] }
        return (try? JSONDecoder().decode([PairedBeacon].self, from: data)) ?? []
    }

    func save(beacons: [PairedBeacon]) {
        defaults.set(try? JSONEncoder().encode(beacons), forKey: beaconsKey)
    }
}
