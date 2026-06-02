import Foundation

struct RelativeTimestampFormatter {
    /// Format a date as relative time using the largest applicable unit
    /// e.g., "3 seconds ago", "2 minutes ago", "1 hour ago", "5 days ago"
    func format(_ date: Date, relativeTo now: Date = Date()) -> String {
        let interval = Int(now.timeIntervalSince(date))

        if interval >= 86400 {
            let days = interval / 86400
            return "\(days) \(days == 1 ? "day" : "days") ago"
        } else if interval >= 3600 {
            let hours = interval / 3600
            return "\(hours) \(hours == 1 ? "hour" : "hours") ago"
        } else if interval >= 60 {
            let minutes = interval / 60
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes") ago"
        } else {
            let seconds = max(interval, 0)
            return "\(seconds) \(seconds == 1 ? "second" : "seconds") ago"
        }
    }
}
