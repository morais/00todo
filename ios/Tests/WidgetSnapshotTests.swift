import Foundation

@main struct WidgetSnapshotTests {
    static func main() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 12))!
        let project = WidgetProject(id: "p", name: "Shopping", startDate: nil, startTime: nil,
                                    dueDate: nil, completedAt: nil, sortOrder: 1, createdAt: "1")
        let futureProject = WidgetProject(id: "future", name: "Later", startDate: "2026-10-01", startTime: nil,
                                          dueDate: nil, completedAt: nil, sortOrder: 2, createdAt: "2")
        let tasks = [
            WidgetTask(id: "milk", title: "Milk", projectId: "p", startDate: nil, startTime: nil,
                       dueDate: nil, completedAt: nil, sortOrder: 0, createdAt: "1"),
            WidgetTask(id: "hidden", title: "Hidden", projectId: "future", startDate: nil, startTime: nil,
                       dueDate: nil, completedAt: nil, sortOrder: 0, createdAt: "2"),
            WidgetTask(id: "timed", title: "Timed", projectId: nil, startDate: "2026-09-29", startTime: "14:00",
                       dueDate: nil, completedAt: nil, sortOrder: 0, createdAt: "3"),
            WidgetTask(id: "top", title: "Top level", projectId: nil, startDate: nil, startTime: nil,
                       dueDate: nil, completedAt: nil, sortOrder: 0, createdAt: "4"),
            WidgetTask(id: "done", title: "Done", projectId: nil, startDate: nil, startTime: nil,
                       dueDate: nil, completedAt: "2026-09-28T12:00:00Z", sortOrder: 0, createdAt: "5")
        ]
        let snapshot = WidgetSnapshot(projects: [project, futureProject], tasks: tasks)
        let collapsed = snapshot.availableItems(at: now, expandProjects: false)
        precondition(Set(collapsed.map(\.title)) == ["Shopping", "Top level"])
        let expanded = snapshot.availableItems(at: now, expandProjects: true)
        precondition(Set(expanded.map(\.title)) == ["Milk", "Top level"])
        precondition(expanded.first { $0.title == "Milk" }?.projectName == "Shopping")
        let afterTime = now.addingTimeInterval(2 * 60 * 60)
        precondition(Set(snapshot.availableItems(at: afterTime, expandProjects: true).map(\.title)) == ["Milk", "Timed", "Top level"])
        precondition(snapshot.upcomingStartDates(after: now).contains(afterTime))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let twoDays = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        precondition(TodoDates.startLabel(date: TodoDates.string(from: tomorrow), time: nil) == "Starts tomorrow")
        precondition(TodoDates.startLabel(date: TodoDates.string(from: twoDays), time: "09:30") == "Starts in 2 days at 09:30")
        print("Widget snapshot tests passed")
    }
}
