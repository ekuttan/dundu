import Foundation

/// Shared date presentation. All relative wording flows through here so the
/// notch and the iOS lists agree on what "in 5m" means.
enum Formatters {
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// "in 5m", "2h ago"
    static func relativeTime(to date: Date, from now: Date = Date()) -> String {
        relative.localizedString(for: date, relativeTo: now)
    }

    /// "09:30" in the given zone — events keep their own time zones.
    static func clockTime(_ date: Date, timeZoneID: String? = nil) -> String {
        if let id = timeZoneID, let zone = TimeZone(identifier: id) {
            time.timeZone = zone
        } else {
            time.timeZone = .current
        }
        return time.string(from: date)
    }
}
