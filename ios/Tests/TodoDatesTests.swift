import Foundation

@main struct TodoDatesTests {
    static func main() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
        func day(_ offset: Int) -> String { TodoDates.string(from: calendar.date(byAdding: .day, value: offset, to: now)!) }

        precondition(TodoDates.relativeDay(day(0), now: now) == "today")
        precondition(TodoDates.relativeDay(day(1), now: now) == "tomorrow")
        precondition(TodoDates.relativeDay(day(-1), now: now) == "yesterday")
        precondition(TodoDates.relativeDay(day(3), now: now) == "in 3 days")
        precondition(TodoDates.dueLabel(day(0), now: now) == "Due today")

        // Further away, a localized date replaces the raw YYYY-MM-DD value.
        for value in [day(10), day(-5), "2027-03-04"] {
            precondition(!TodoDates.relativeDay(value, now: now).contains(value))
        }
        precondition(TodoDates.relativeDay("2027-03-04", now: now).contains("2027"))
        precondition(!TodoDates.relativeDay(day(10), now: now).contains("2026"))

        precondition(TodoDates.startLabel(date: day(1), time: nil, now: now) == "Starts tomorrow")
        precondition(TodoDates.startLabel(date: day(9), time: nil, now: now) == "Starts in 9 days")
        precondition(TodoDates.startLabel(date: day(0), time: "14:30", now: now).hasPrefix("Starts today at "))
        precondition(TodoDates.isOverdue(day(-1), at: now) && !TodoDates.isOverdue(day(0), at: now))

        // A 1.0 cached item lacks the new field and must still decode as active.
        let oldTask = TodoTask(id: "legacy", title: "Old task", notes: "", projectId: nil,
                               startDate: nil, startTime: nil, dueDate: nil, completedAt: nil,
                               sortOrder: 0, createdAt: "2026-10-01", updatedAt: "2026-10-01")
        let legacyData = try! JSONEncoder().encode(oldTask)
        let decoded = try! JSONDecoder().decode(TodoTask.self, from: legacyData)
        precondition(decoded.someday == nil && decoded.isAvailable(at: now))
        var held = decoded
        held.someday = true
        precondition(!held.isAvailable(at: now))
        print("Date label tests passed")
    }
}
