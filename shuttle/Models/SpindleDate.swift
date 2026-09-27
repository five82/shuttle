import Foundation

/// Parses the timestamp formats Spindle emits: RFC 3339 with or without
/// fractional seconds, and SQLite's `YYYY-MM-DD HH:MM:SS` in UTC.
enum SpindleDate {
    static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Formatters are mutable reference types; keep them local so parsing
        // remains safe when multiple responses are decoded concurrently.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        let sqlite = DateFormatter()
        sqlite.locale = Locale(identifier: "en_US_POSIX")
        sqlite.timeZone = TimeZone(identifier: "UTC")
        sqlite.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return sqlite.date(from: trimmed)
    }
}
