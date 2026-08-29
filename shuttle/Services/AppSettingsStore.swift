import Foundation
import Observation

struct AppSettings: Equatable, Sendable {
    /// A safe placeholder for a public repo, not a working address: Spindle
    /// runs on a Linux host, so a real setup always replaces this.
    static let defaultBaseURLString = "http://127.0.0.1:7487"
    static let defaults = AppSettings(baseURLString: defaultBaseURLString, token: "")

    var baseURLString: String
    var token: String
    var notifications: Set<NotificationKind> = Set(NotificationKind.allCases.filter(\.isOnByDefault))
    var menuBarOnly = false
    var pollInterval: TimeInterval = SpindleMonitor.defaultPollInterval
    /// Where the daemon's library lives as the daemon sees it, e.g. "/mnt/media".
    var libraryRemotePrefix = ""
    /// The same directory mounted on this Mac, e.g. "/Volumes/media".
    var libraryLocalPrefix = ""

    static let pollIntervalChoices: [TimeInterval] = [1, 2, 5, 10]

    func notifies(_ kind: NotificationKind) -> Bool {
        notifications.contains(kind)
    }

    /// True until the user replaces the loopback placeholder. Spindle never
    /// runs on the Mac, so the placeholder can never connect; views use this to
    /// ask for the address instead of reporting a connection failure.
    var isPlaceholderAddress: Bool {
        baseURLString.trimmingCharacters(in: .whitespacesAndNewlines) == Self.defaultBaseURLString
    }

    /// A daemon-side library path translated through the mount mapping, or
    /// nil when the mapping is not set or the path is outside it. Whether the
    /// result exists on this Mac is the caller's question.
    func localLibraryPath(for remotePath: String) -> String? {
        let remote = Self.normalized(libraryRemotePrefix)
        let local = Self.normalized(libraryLocalPrefix)
        guard !remote.isEmpty, !local.isEmpty else { return nil }
        if remotePath == remote { return local }
        guard remotePath.hasPrefix(remote + "/") else { return nil }
        return local + remotePath.dropFirst(remote.count)
    }

    private static func normalized(_ prefix: String) -> String {
        var value = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
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

/// Where the API token lives. The Keychain in the app; memory in tests.
protocol TokenStore: AnyObject {
    func read() -> String?
    func write(_ token: String)
    func delete()
}

final class InMemoryTokenStore: TokenStore {
    private var token: String?
    init(_ token: String? = nil) { self.token = token }
    func read() -> String? { token }
    func write(_ token: String) { self.token = token }
    func delete() { token = nil }
}

@Observable
@MainActor
final class AppSettingsStore {
    private enum Key {
        static let baseURL = "spindleBaseURL"
        /// Pre-Keychain location; read once and cleared on first launch.
        static let legacyToken = "spindleAPIToken"
        static let menuBarOnly = "menuBarOnly"
        static let pollInterval = "pollInterval"
        static let libraryRemotePrefix = "libraryRemotePrefix"
        static let libraryLocalPrefix = "libraryLocalPrefix"
        static func notify(_ kind: NotificationKind) -> String { "notify.\(kind.rawValue)" }
    }

    private(set) var settings: AppSettings
    private let defaults: UserDefaults
    private let tokenStore: TokenStore

    init(defaults: UserDefaults = .standard, tokenStore: TokenStore? = nil) {
        self.defaults = defaults
        let tokenStore = tokenStore ?? (defaults == .standard ? KeychainTokenStore() : InMemoryTokenStore())
        self.tokenStore = tokenStore
        var token = tokenStore.read() ?? ""
        if let legacy = defaults.string(forKey: Key.legacyToken) {
            if token.isEmpty, !legacy.isEmpty {
                token = legacy
                tokenStore.write(legacy)
            }
            defaults.removeObject(forKey: Key.legacyToken)
        }
        var loaded = AppSettings(
            baseURLString: defaults.string(forKey: Key.baseURL) ?? AppSettings.defaultBaseURLString,
            token: token
        )
        loaded.menuBarOnly = defaults.bool(forKey: Key.menuBarOnly)
        loaded.libraryRemotePrefix = defaults.string(forKey: Key.libraryRemotePrefix) ?? ""
        loaded.libraryLocalPrefix = defaults.string(forKey: Key.libraryLocalPrefix) ?? ""
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
        if token.isEmpty { tokenStore.delete() } else { tokenStore.write(token) }
    }

    func updateLibraryMapping(remote: String, local: String) {
        settings.libraryRemotePrefix = remote
        settings.libraryLocalPrefix = local
        defaults.set(remote, forKey: Key.libraryRemotePrefix)
        defaults.set(local, forKey: Key.libraryLocalPrefix)
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
        tokenStore.delete()
        defaults.removeObject(forKey: Key.menuBarOnly)
        defaults.removeObject(forKey: Key.pollInterval)
        defaults.removeObject(forKey: Key.libraryRemotePrefix)
        defaults.removeObject(forKey: Key.libraryLocalPrefix)
        for kind in NotificationKind.allCases {
            defaults.removeObject(forKey: Key.notify(kind))
        }
    }

    /// A client for the current settings, or nil when the address is invalid.
    func makeClient() -> SpindleAPI? {
        settings.baseURL.map { SpindleClient(baseURL: $0, token: settings.token) }
    }
}
