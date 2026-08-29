import Foundation
import Observation

struct AppSettings: Equatable, Sendable {
    static let defaultBaseURLString = "http://127.0.0.1:7487"
    static let defaults = AppSettings(baseURLString: defaultBaseURLString, token: "")

    var baseURLString: String
    var token: String

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
    }

    private(set) var settings: AppSettings
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = AppSettings(
            baseURLString: defaults.string(forKey: Key.baseURL) ?? AppSettings.defaultBaseURLString,
            token: defaults.string(forKey: Key.token) ?? ""
        )
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

    func resetToDefaults() {
        settings = .defaults
        defaults.removeObject(forKey: Key.baseURL)
        defaults.removeObject(forKey: Key.token)
    }

    /// A client for the current settings, or nil when the address is invalid.
    func makeClient() -> SpindleAPI? {
        settings.baseURL.map { SpindleClient(baseURL: $0, token: settings.token) }
    }
}
