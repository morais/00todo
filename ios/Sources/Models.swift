import Foundation

struct TodoProject: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var notes: String
    var startDate: String?
    var startTime: String?
    var dueDate: String?
    // Optional so cached 1.0 snapshots decode as active items.
    var someday: Bool? = nil
    // Optional so cached snapshots from before Blocked decode as active items.
    var blocked: Bool? = nil
    var completedAt: String?
    var sortOrder: Int
    var createdAt: String
    var updatedAt: String

    func isAvailable(at now: Date = Date()) -> Bool {
        completedAt == nil && someday != true && blocked != true
            && TodoDates.hasStarted(startDate: startDate, startTime: startTime, at: now)
    }
}

struct TodoTask: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var notes: String
    var projectId: String?
    var startDate: String?
    var startTime: String?
    var dueDate: String?
    // Optional so cached 1.0 snapshots decode as active items.
    var someday: Bool? = nil
    // Optional so cached snapshots from before Blocked decode as active items.
    var blocked: Bool? = nil
    var completedAt: String?
    var sortOrder: Int
    var createdAt: String
    var updatedAt: String

    func isAvailable(at now: Date = Date()) -> Bool {
        completedAt == nil && someday != true && blocked != true
            && TodoDates.hasStarted(startDate: startDate, startTime: startTime, at: now)
    }
}

struct TodoSnapshot: Codable {
    var projects: [TodoProject]
    var tasks: [TodoTask]
    var serverTime: String
}

struct MCPConnection: Codable, Identifiable, Equatable {
    var id: String
    var clientName: String
    var scopes: [String]
    var connectedAt: String
    var lastUsedAt: String?
    var expiresAt: String
}

enum UpcomingGroup: Int, CaseIterable {
    case laterToday, tomorrow, sevenDays, fourteenDays, thirtyDays, future

    var title: String {
        switch self {
        case .laterToday: "Later today"
        case .tomorrow: "Tomorrow"
        case .sevenDays: "Next 7 days"
        case .fourteenDays: "Next 2 weeks"
        case .thirtyDays: "Next 30 days"
        case .future: "Future"
        }
    }
}

enum TodoDates {
    static func string(from date: Date) -> String {
        let pieces = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", pieces.year ?? 0, pieces.month ?? 0, pieces.day ?? 0)
    }

    static func date(from value: String?) -> Date {
        guard let value else { return Date() }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Date()
    }

    static func timeString(from date: Date) -> String {
        let pieces = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", pieces.hour ?? 0, pieces.minute ?? 0)
    }

    static func timeDate(from value: String?) -> Date {
        guard let value else { return Date() }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return Date() }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) ?? Date()
    }

    static func hasStarted(startDate: String?, startTime: String?, at now: Date) -> Bool {
        guard let startDate else { return true }
        let today = string(from: now)
        if startDate != today { return startDate < today }
        return startTime.map { $0 <= timeString(from: now) } ?? true
    }

    static func isOverdue(_ dueDate: String, at now: Date) -> Bool {
        dueDate < string(from: now)
    }

    static func upcomingGroup(for startDate: String?, at now: Date) -> UpcomingGroup {
        guard let startDate else { return .future }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> String {
            string(from: calendar.date(byAdding: .day, value: offset, to: today) ?? today)
        }
        // Only a start time keeps today's items out of Available.
        if startDate <= day(0) { return .laterToday }
        if startDate == day(1) { return .tomorrow }
        if startDate <= day(7) { return .sevenDays }
        if startDate <= day(14) { return .fourteenDays }
        if startDate <= day(30) { return .thirtyDays }
        return .future
    }

    /// Quick picks for a start date. Picks that land on the same day as an
    /// earlier one (Friday's weekend is tomorrow) are left out.
    static func startShortcuts(now: Date = Date()) -> [(title: String, date: Date)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func next(weekday: Int) -> Date? {
            calendar.nextDate(after: today, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime)
        }
        let candidates: [(String, Date?)] = [
            ("Tomorrow", calendar.date(byAdding: .day, value: 1, to: today)),
            (calendar.isDateInWeekend(today) ? "Next weekend" : "This weekend",
             next(weekday: 7)),
            // Monday, even where calendars start the week on Sunday.
            ("Next week", next(weekday: 2)),
            ("Next month", calendar.date(byAdding: .month, value: 1, to: today)
                .flatMap { calendar.dateInterval(of: .month, for: $0)?.start })
        ]
        var seen = Set<String>()
        return candidates.compactMap { title, date in
            guard let date, seen.insert(string(from: date)).inserted else { return nil }
            return (title, date)
        }
    }

    static func startLabel(date: String, time: String?, now: Date = Date()) -> String {
        let days = daysFromToday(date, now: now)
        let relative = days >= 7 ? "in \(days) days" : relativeDay(date, now: now)
        return "Starts \(relative)\(time.map { " at \(displayTime($0))" } ?? "")"
    }

    static func dueLabel(_ date: String, now: Date = Date()) -> String {
        "Due \(relativeDay(date, now: now))"
    }

    /// "today", "tomorrow", "yesterday", a weekday such as "Friday" within the
    /// coming week, or a localized short
    /// date such as "5 Oct" (with the year when it differs), never the raw
    /// YYYY-MM-DD value.
    static func relativeDay(_ value: String, now: Date = Date()) -> String {
        let days = daysFromToday(value, now: now)
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2...6: return date(from: value).formatted(.dateTime.weekday(.wide))
        default:
            let day = date(from: value)
            let sameYear = Calendar.current.component(.year, from: day) == Calendar.current.component(.year, from: now)
            return sameYear
                ? day.formatted(.dateTime.day().month(.abbreviated))
                : day.formatted(.dateTime.day().month(.abbreviated).year())
        }
    }

    /// A stored HH:mm time in the user's 12- or 24-hour style.
    static func displayTime(_ value: String) -> String {
        timeDate(from: value).formatted(date: .omitted, time: .shortened)
    }

    private static func daysFromToday(_ value: String, now: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: date(from: value))).day ?? 0
    }
}
