import Foundation

/// When the daily automatic score should run. Pure date logic, so the app can call it every
/// minute and after wake without caring about timers, sleep, or time-zone changes.
public struct AutoSchedule: Sendable, Equatable {
    public var enabled: Bool
    /// Minutes after midnight, local time. 14 * 60 = 2:00pm.
    public var minuteOfDay: Int

    public static let defaultMinuteOfDay = 14 * 60

    public init(enabled: Bool = true, minuteOfDay: Int = AutoSchedule.defaultMinuteOfDay) {
        self.enabled = enabled
        self.minuteOfDay = min(max(minuteOfDay, 0), 24 * 60 - 1)
    }

    /// Today's scheduled time.
    public func time(on day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minuteOfDay, to: start) ?? start
    }

    /// The next scheduled time at or after `now`, or nil when disabled.
    public func next(after now: Date, calendar: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        let today = time(on: now, calendar: calendar)
        if today > now { return today }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return time(on: tomorrow, calendar: calendar)
    }

    /// True when today's slot has passed and hasn't been handled yet. A slot is handled when a
    /// score was produced after it (manual or automatic) or an automatic attempt already ran for it.
    /// Missed slots from earlier days are not replayed; only today's counts (catch-up after sleep).
    public func isDue(now: Date, lastResultAt: Date?, lastAttemptAt: Date?, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let slot = time(on: now, calendar: calendar)
        guard now >= slot else { return false }
        if let lastResultAt, lastResultAt >= slot { return false }
        if let lastAttemptAt, lastAttemptAt >= slot { return false }
        return true
    }
}
