import Foundation

@main struct WidgetSnapshotTests {
    static func main() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 12))!
        let project = WidgetProject(id: "p", name: "Shopping", startDate: nil, startTime: nil,
                                    dueDate: nil, completedAt: nil, sortOrder: 1, createdAt: "1")
        let futureProject = WidgetProject(id: "future", name: "Later", startDate: "2026-10-01", startTime: nil,
                                          dueDate: nil, completedAt: nil, sortOrder: 2, createdAt: "2")
        let upcomingChildProject = WidgetProject(id: "upcoming-child", name: "Upcoming list", startDate: nil,
                                                 startTime: nil, dueDate: nil, completedAt: nil, sortOrder: 3, createdAt: "3")
        let finishedChildrenProject = WidgetProject(id: "finished-children", name: "Finished list", startDate: nil,
                                                    startTime: nil, dueDate: nil, completedAt: nil, sortOrder: 4, createdAt: "4")
        let emptyProject = WidgetProject(id: "empty", name: "Empty list", startDate: nil,
                                         startTime: nil, dueDate: nil, completedAt: nil, sortOrder: 5, createdAt: "5")
        let tasks = [
            WidgetTask(id: "milk", title: "Milk", projectId: "p", startDate: nil, startTime: nil,
                       dueDate: nil, completedAt: nil, sortOrder: 0, createdAt: "1"),
            WidgetTask(id: "hidden", title: "Hidden", projectId: "future", startDate: nil, startTime: nil,
                       dueDate: nil, completedAt: nil, sortOrder: 0, createdAt: "2"),
            WidgetTask(id: "timed", title: "Timed", projectId: nil, startDate: "2026-09-29", startTime: "14:00",
                       dueDate: nil, completedAt: nil, sortOrder: 0, createdAt: "3"),
            WidgetTask(id: "top", title: "Top level", projectId: nil, startDate: nil, startTime: nil,
                       dueDate: nil, completedAt: nil, sortOrder: 0, createdAt: "4"),
            WidgetTask(id: "upcoming", title: "Next week", projectId: "upcoming-child",
                       startDate: "2026-10-06", startTime: nil,
                       dueDate: nil, completedAt: nil, sortOrder: 0, createdAt: "5"),
            WidgetTask(id: "finished", title: "Bought", projectId: "finished-children",
                       startDate: nil, startTime: nil, dueDate: nil,
                       completedAt: "2026-09-28T12:00:00Z", sortOrder: 0, createdAt: "6"),
            WidgetTask(id: "done", title: "Done", projectId: nil, startDate: nil, startTime: nil,
                       dueDate: nil, completedAt: "2026-09-28T12:00:00Z", sortOrder: 0, createdAt: "5")
        ]
        let snapshot = WidgetSnapshot(projects: [project, futureProject, upcomingChildProject,
                                                 finishedChildrenProject, emptyProject], tasks: tasks)
        let collapsed = snapshot.availableItems(at: now, expandProjects: false)
        precondition(Set(collapsed.map(\.title)) == ["Shopping", "Upcoming list", "Finished list", "Empty list", "Top level"])
        let expanded = snapshot.availableItems(at: now, expandProjects: true)
        precondition(Set(expanded.map(\.title)) == ["Milk", "Finished list", "Empty list", "Top level"])
        precondition(expanded.first { $0.title == "Milk" }?.projectName == "Shopping")
        let taskDestination = WidgetDestination(item: expanded.first { $0.title == "Milk" }!)!
        precondition(taskDestination == .task("milk"))
        precondition(WidgetDestination(url: taskDestination.url) == taskDestination)
        let projectDestination = WidgetDestination(item: collapsed.first { $0.title == "Shopping" }!)!
        precondition(projectDestination == .project("p"))
        precondition(WidgetDestination(url: projectDestination.url) == projectDestination)
        precondition(WidgetDestination(url: URL(string: "zerozerotodo://quick-add/text")!) == nil)
        precondition(WidgetDestination(url: URL(string: "zerozerotodo://open/task?id=milk&extra=1")!) == nil)
        let afterTime = now.addingTimeInterval(2 * 60 * 60)
        precondition(Set(snapshot.availableItems(at: afterTime, expandProjects: true).map(\.title)) ==
                     ["Milk", "Timed", "Finished list", "Empty list", "Top level"])
        var completedUpcoming = snapshot
        completedUpcoming.tasks[completedUpcoming.tasks.firstIndex { $0.id == "upcoming" }!].completedAt =
            "2026-09-29T12:00:00Z"
        precondition(completedUpcoming.availableItems(at: now, expandProjects: true)
            .contains { $0.title == "Upcoming list" })
        precondition(snapshot.upcomingStartDates(after: now).contains(afterTime))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let twoDays = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        precondition(TodoDates.startLabel(date: TodoDates.string(from: tomorrow), time: nil) == "Starts tomorrow")
        precondition(TodoDates.startLabel(date: TodoDates.string(from: twoDays), time: "09:30") == "Starts \(twoDays.formatted(.dateTime.weekday(.wide))) at \(TodoDates.displayTime("09:30"))")
        let today = Calendar.current.startOfDay(for: now)
        func startDate(_ days: Int) -> String {
            TodoDates.string(from: Calendar.current.date(byAdding: .day, value: days, to: today)!)
        }
        precondition(TodoDates.upcomingGroup(for: startDate(0), at: now) == .laterToday)
        precondition(TodoDates.upcomingGroup(for: startDate(1), at: now) == .tomorrow)
        precondition(TodoDates.upcomingGroup(for: startDate(2), at: now) == .sevenDays)
        precondition(TodoDates.upcomingGroup(for: startDate(7), at: now) == .sevenDays)
        precondition(TodoDates.upcomingGroup(for: startDate(8), at: now) == .fourteenDays)
        precondition(TodoDates.upcomingGroup(for: startDate(15), at: now) == .thirtyDays)
        precondition(TodoDates.upcomingGroup(for: startDate(31), at: now) == .future)
        print("Widget snapshot tests passed")
    }
}
