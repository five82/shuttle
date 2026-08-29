import Foundation
import Observation

struct AppSettings: Equatable, Sendable {
    static let defaultBaseURLString = "http://127.0.0.1:7487"
    static let defaults = AppSettings(baseURLString: defaultBaseURLString, token: "")

    var baseURLString: String
    var token: String
    var notifications: Set<NotificationKind> = Set(NotificationKind.allCases.filter(\.isOnByDefault))
    var menuBarOnly = false
    var pollInterval: TimeInterval = SpindleMonitor.defaultPollInterval

    static let pollIntervalChoices: [TimeInterval] = [1, 2, 5, 10]

    func notifies(_ kind: NotificationKind) -> Bool {
        notifications.contains(kind)
    }

    /// The daemon URL, or nil when the string is not an http(s) URL with a host.
    var baseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}

@Observable
@MainActor
final class AppSettingsStore {
    private enum Key {
        static let baseURL = "spindleBaseURL"
        static let token = "spindleAPIToken"
        static let menuBarOnly = "menuBarOnly"
        static let pollInterval = "pollInterval"
        static func notify(_ kind: NotificationKind) -> String { "notify.\(kind.rawValue)" }
    }

    private(set) var settings: AppSettings
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded = AppSettings(
            baseURLString: defaults.string(forKey: Key.baseURL) ?? AppSettings.defaultBaseURLString,
            token: defaults.string(forKey: Key.token) ?? ""
        )
        loaded.menuBarOnly = defaults.bool(forKey: Key.menuBarOnly)
        if let interval = defaults.object(forKey: Key.pollInterval) as? Double, interval >= 1 {
            loaded.pollInterval = interval
        }
        for kind in NotificationKind.allCases {
            if let enabled = defaults.object(forKey: Key.notify(kind)) as? Bool {
                if enabled { loaded.notifications.insert(kind) } else { loaded.notifications.remove(kind) }
            }
        }
        settings = loaded
    }

    var baseURLIsValid: Bool { settings.baseURL != nil }

    func updateBaseURLString(_ string: String) {
        settings.baseURLString = string
        defaults.set(string, forKey: Key.baseURL)
    }

    func updateToken(_ token: String) {
        settings.token = token
        defaults.set(token, forKey: Key.token)
    }

    func setNotification(_ kind: NotificationKind, enabled: Bool) {
        if enabled {
            settings.notifications.insert(kind)
        } else {
            settings.notifications.remove(kind)
        }
        defaults.set(enabled, forKey: Key.notify(kind))
    }

    func setMenuBarOnly(_ enabled: Bool) {
        settings.menuBarOnly = enabled
        defaults.set(enabled, forKey: Key.menuBarOnly)
    }

    func setPollInterval(_ interval: TimeInterval) {
        settings.pollInterval = interval
        defaults.set(interval, forKey: Key.pollInterval)
    }

    func resetToDefaults() {
        settings = .defaults
        defaults.removeObject(forKey: Key.baseURL)
        defaults.removeObject(forKey: Key.token)
        defaults.removeObject(forKey: Key.menuBarOnly)
        defaults.removeObject(forKey: Key.pollInterval)
        for kind in NotificationKind.allCases {
            defaults.removeObject(forKey: Key.notify(kind))
        }
    }

    /// A client for the current settings, or nil when the address is invalid.
    func makeClient() -> SpindleAPI? {
        settings.baseURL.map { SpindleClient(baseURL: $0, token: settings.token) }
    }
}
