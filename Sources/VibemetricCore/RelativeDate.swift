import Foundation

/// Friendly run dates: "Today 2:30pm", "Yesterday 1:15pm", "2 days ago 1:30pm",
/// "3 days ago" … "6 days ago", then the date ("Sep 21", or "Sep 21, 2025" in another year).
/// Days are calendar days, so 11pm yesterday is "Yesterday", not "Today".
public enum RelativeDate {
    /// Up to this many days back, the time is shown too.
    static let daysWithTime = 2
    /// Up to this many days back, "N days ago"; older runs show the date.
    static let daysAsRelative = 6

    public static func format(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        let time = timeString(date, calendar: calendar, locale: locale)
        switch days {
        case ..<0: return dateString(date, now: now, calendar: calendar, locale: locale) // clock skew: never say "-1 days ago"
        case 0: return "Today \(time)"
        case 1: return "Yesterday \(time)"
        case 2...daysWithTime: return "\(days) days ago \(time)"
        case ...daysAsRelative: return "\(days) days ago"
        default: return dateString(date, now: now, calendar: calendar, locale: locale)
        }
    }

    /// "2:30pm": lowercase, no space, no leading zero.
    static func timeString(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: date)
    }

    static func dateString(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        f.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
        return f.string(from: date)
    }
}
