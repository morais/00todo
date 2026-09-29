import Foundation

// A deliberately small, token-free copy of the data needed to render widgets.
struct WidgetSnapshot: Codable {
    var projects: [WidgetProject]
    var tasks: [WidgetTask]

    func availableItems(at now: Date, expandProjects: Bool) -> [WidgetItem] {
        let parents = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let availableProjects = projects.filter { $0.completedAt == nil && Self.hasStarted($0.startDate, $0.startTime, at: now) }
        let availableTasks = tasks.filter { task in
            guard task.completedAt == nil, Self.hasStarted(task.startDate, task.startTime, at: now) else { return false }
            guard let projectId = task.projectId else { return true }
            guard let parent = parents[projectId] else { return false }
            return parent.completedAt == nil && Self.hasStarted(parent.startDate, parent.startTime, at: now)
        }
        let shownTasks = expandProjects ? availableTasks : availableTasks.filter { $0.projectId == nil }
        let projectsWithUncompletedTasks = Set(tasks.filter { $0.completedAt == nil }.compactMap(\.projectId))
        let shownProjects = availableProjects.filter { !expandProjects || !projectsWithUncompletedTasks.contains($0.id) }
        return (shownProjects.map { WidgetItem(id: "project-\($0.id)", title: $0.name, projectName: nil,
                                               isProject: true, dueDate: $0.dueDate, sortOrder: $0.sortOrder, createdAt: $0.createdAt) }
                + shownTasks.map { WidgetItem(id: "task-\($0.id)", title: $0.title,
                                               projectName: $0.projectId.flatMap { parents[$0]?.name },
                                               isProject: false, dueDate: $0.dueDate, sortOrder: $0.sortOrder, createdAt: $0.createdAt) })
            .sorted { first, second in
                if first.dueDate != second.dueDate { return (first.dueDate ?? "9999-12-31") < (second.dueDate ?? "9999-12-31") }
                if first.sortOrder != second.sortOrder { return first.sortOrder < second.sortOrder }
                if first.createdAt != second.createdAt { return first.createdAt < second.createdAt }
                return first.id < second.id
            }
    }

    func upcomingStartDates(after now: Date) -> [Date] {
        let dates = projects.compactMap { Self.startInstant($0.startDate, $0.startTime) }
            + tasks.compactMap { Self.startInstant($0.startDate, $0.startTime) }
        return Array(Set(dates.filter { $0 > now }.map { $0.timeIntervalSince1970 }))
            .sorted().prefix(40).map(Date.init(timeIntervalSince1970:))
    }

    private static func hasStarted(_ date: String?, _ time: String?, at now: Date) -> Bool {
        guard let date else { return true }
        guard let instant = startInstant(date, time) else { return false }
        return instant <= now
    }

    private static func startInstant(_ date: String?, _ time: String?) -> Date? {
        guard let date else { return nil }
        let dateParts = date.split(separator: "-").compactMap { Int($0) }
        guard dateParts.count == 3 else { return nil }
        let timeParts = (time ?? "00:00").split(separator: ":").compactMap { Int($0) }
        guard timeParts.count == 2 else { return nil }
        return Calendar.current.date(from: DateComponents(year: dateParts[0], month: dateParts[1], day: dateParts[2],
                                                          hour: timeParts[0], minute: timeParts[1]))
    }
}

struct WidgetProject: Codable {
    var id: String
    var name: String
    var startDate: String?
    var startTime: String?
    var dueDate: String?
    var completedAt: String?
    var sortOrder: Int
    var createdAt: String
}

struct WidgetTask: Codable {
    var id: String
    var title: String
    var projectId: String?
    var startDate: String?
    var startTime: String?
    var dueDate: String?
    var completedAt: String?
    var sortOrder: Int
    var createdAt: String
}

struct WidgetItem: Identifiable {
    var id: String
    var title: String
    var projectName: String?
    var isProject: Bool
    var dueDate: String?
    var sortOrder: Int
    var createdAt: String
}

enum WidgetDestination: Hashable, Identifiable {
    case task(String)
    case project(String)

    var id: String {
        switch self {
        case .task(let id): "task-\(id)"
        case .project(let id): "project-\(id)"
        }
    }

    init?(item: WidgetItem) {
        let prefix = item.isProject ? "project-" : "task-"
        guard item.id.hasPrefix(prefix), item.id.count > prefix.count else { return nil }
        let recordID = String(item.id.dropFirst(prefix.count))
        self = item.isProject ? .project(recordID) : .task(recordID)
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "zerozerotodo", components.host == "open",
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil, let query = components.queryItems, query.count == 1,
              query[0].name == "id", let recordID = query[0].value, !recordID.isEmpty else { return nil }
        switch components.path {
        case "/task": self = .task(recordID)
        case "/project": self = .project(recordID)
        default: return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "zerozerotodo"
        components.host = "open"
        switch self {
        case .task(let id):
            components.path = "/task"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
        case .project(let id):
            components.path = "/project"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
        }
        return components.url!
    }
}

enum WidgetSnapshotStore {
    static let widgetKind = "AvailableTodoWidget"

    private static var url: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "TodoAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return container.appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return false }
        if (try? Data(contentsOf: url)) == data { return false }
        do { try data.write(to: url, options: .atomic); return true }
        catch { return false }
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
