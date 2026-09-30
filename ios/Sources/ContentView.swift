import SwiftUI

enum QuickAddLaunch: String, Identifiable {
    case text
    case voice
    var id: String { rawValue }

    init?(url: URL) {
        guard url.scheme == "zerozerotodo", url.host == "quick-add", url.query == nil, url.fragment == nil else { return nil }
        switch url.path {
        case "/text": self = .text
        case "/voice": self = .voice
        default: return nil
        }
    }
}

@main struct ZeroZeroTodoApp: App {
    @UIApplicationDelegateAdaptor(TodoAppDelegate.self) private var appDelegate
    @State private var store = TodoStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}

struct ContentView: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var shortcuts = QuickAddShortcuts.shared
    @State private var pendingQuickAdd: QuickAddLaunch?
    @State private var pendingWidgetDestination: WidgetDestination?

    var body: some View {
        Group {
            if store.isConfigured {
                TasksView(pendingQuickAdd: $pendingQuickAdd, pendingWidgetDestination: $pendingWidgetDestination)
            } else {
                SignInView()
            }
        }
        .task { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
        .onOpenURL { url in
            if let launch = QuickAddLaunch(url: url) {
                pendingWidgetDestination = nil
                pendingQuickAdd = launch
            } else if let destination = WidgetDestination(url: url) {
                pendingQuickAdd = nil
                pendingWidgetDestination = destination
                Task { await store.refresh() }
            }
        }
        .onAppear { openPendingShortcut() }
        .onChange(of: shortcuts.pendingLaunch) { _, _ in openPendingShortcut() }
    }

    private func openPendingShortcut() {
        guard let launch = shortcuts.pendingLaunch else { return }
        shortcuts.pendingLaunch = nil
        pendingQuickAdd = launch
    }
}

private enum TaskFilter: String, CaseIterable, Identifiable {
    case available = "Available"
    case upcoming = "Upcoming"
    case completed = "Completed"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .available: "checklist"
        case .upcoming: "calendar"
        case .completed: "checkmark.circle"
        }
    }
}

private enum ListItem: Identifiable {
    case project(TodoProject)
    case task(TodoTask)

    var id: String {
        switch self {
        case .project(let item): "project-\(item.id)"
        case .task(let item): "task-\(item.id)"
        }
    }
    var dueDate: String? {
        switch self {
        case .project(let item): item.dueDate
        case .task(let item): item.dueDate
        }
    }
    var completedAt: String? {
        switch self {
        case .project(let item): item.completedAt
        case .task(let item): item.completedAt
        }
    }
    var sortOrder: Int {
        switch self {
        case .project(let item): item.sortOrder
        case .task(let item): item.sortOrder
        }
    }
    var createdAt: String {
        switch self {
        case .project(let item): item.createdAt
        case .task(let item): item.createdAt
        }
    }
}

struct TasksView: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Binding var pendingQuickAdd: QuickAddLaunch?
    @Binding var pendingWidgetDestination: WidgetDestination?
    @State private var filter: TaskFilter = .available
    @AppStorage("showProjectTasksInLists") private var showProjectTasks = true
    @State private var showNewItem = false
    @State private var showSettings = false
    @State private var now = Date()

    private func effectiveStartKey(for item: ListItem, parents: [String: TodoProject]) -> String? {
        func key(_ date: String?, _ time: String?) -> String? {
            date.map { "\($0)T\(time ?? "00:00")" }
        }
        return switch item {
        case .project(let project): key(project.startDate, project.startTime)
        case .task(let task):
            [key(task.startDate, task.startTime),
             task.projectId.flatMap { id in parents[id].flatMap { key($0.startDate, $0.startTime) } }]
                .compactMap { $0 }.max()
        }
    }

    private func visibleItems(for filter: TaskFilter) -> [ListItem] {
        let parents = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id, $0) })
        let projects = store.projects.filter { item in
            switch filter {
            case .available: item.isAvailable(at: now)
            case .upcoming: item.completedAt == nil && !item.isAvailable(at: now)
            case .completed: item.completedAt != nil
            }
        }
        let tasks = store.tasks.filter { item in
            guard showProjectTasks || item.projectId == nil else { return false }
            let parent = item.projectId.flatMap { parents[$0] }
            switch filter {
            case .available:
                return item.isAvailable(at: now) && (parent?.isAvailable(at: now) ?? true)
            case .upcoming:
                return item.completedAt == nil && parent?.completedAt == nil
                    && (!item.isAvailable(at: now) || !(parent?.isAvailable(at: now) ?? true))
            case .completed: return item.completedAt != nil
            }
        }
        let projectsWithUncompletedTasks = Set(store.tasks.filter { $0.completedAt == nil }.compactMap(\.projectId))
        let projectItems = projects
            .filter { !showProjectTasks || !projectsWithUncompletedTasks.contains($0.id) }
            .map(ListItem.project)
        let taskItems = tasks.map(ListItem.task)
        return (projectItems + taskItems).sorted { first, second in
            if filter == .completed && first.completedAt != second.completedAt {
                return (first.completedAt ?? "") > (second.completedAt ?? "")
            }
            if filter == .upcoming {
                let firstStart = effectiveStartKey(for: first, parents: parents)
                let secondStart = effectiveStartKey(for: second, parents: parents)
                if firstStart != secondStart {
                    return (firstStart ?? "9999-12-31") < (secondStart ?? "9999-12-31")
                }
            } else if filter == .available && first.dueDate != second.dueDate {
                return (first.dueDate ?? "9999-12-31") < (second.dueDate ?? "9999-12-31")
            }
            if first.sortOrder != second.sortOrder { return first.sortOrder < second.sortOrder }
            if first.createdAt != second.createdAt { return first.createdAt < second.createdAt }
            return first.id < second.id
        }
    }

    private func upcomingSections(for items: [ListItem]) -> [(title: String, items: [ListItem])] {
        let parents = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id, $0) })
        var groups = [[ListItem]](repeating: [], count: UpcomingGroup.allCases.count)
        for item in items {
            let start = String((effectiveStartKey(for: item, parents: parents) ?? "9999-12-31").prefix(10))
            groups[TodoDates.upcomingGroup(for: start, at: now).rawValue].append(item)
        }
        return zip(UpcomingGroup.allCases.map(\.title), groups)
            .filter { !$0.1.isEmpty }
            .map { (title: $0.0, items: $0.1) }
    }

    @ViewBuilder private func itemRow(_ item: ListItem) -> some View {
        switch item {
        case .project(let project):
            NavigationLink {
                ProjectTasksView(project: project)
            } label: {
                ProjectRow(
                    project: project,
                    openCount: store.tasks.filter { $0.projectId == project.id && $0.completedAt == nil }.count
                ) { Task { await store.toggle(project) } }
            }
        case .task(let task):
            NavigationLink {
                TaskEditor(task: task)
            } label: {
                TaskRow(task: task, project: store.projects.first { $0.id == task.projectId }) { Task { await store.toggle(task) } }
            }
        }
    }

    private func list(for filter: TaskFilter) -> some View {
        let items = visibleItems(for: filter)
        return List {
            if items.isEmpty {
                ContentUnavailableView(filter == .available ? "All clear" : "No items", systemImage: "checkmark.circle")
            } else if filter == .upcoming {
                ForEach(upcomingSections(for: items), id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in itemRow(item) }
                    }
                }
            } else {
                ForEach(items) { item in itemRow(item) }
            }
        }
            .contentMargins(.top, verticalSizeClass == .compact ? 0 : nil, for: .scrollContent)
            .refreshable { await store.refresh() }
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $filter) {
                ForEach(TaskFilter.allCases) { choice in
                    list(for: choice)
                        .tabItem { Label(choice.rawValue, systemImage: choice.symbol) }
                        .tag(choice)
                }
            }
            .navigationTitle("00Todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("00Todo")
                        .font(.system(size: 22, weight: .bold))
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                    Button { showProjectTasks.toggle() } label: {
                        Image(systemName: "list.bullet.indent")
                    }
                    .tint(showProjectTasks ? .accentColor : .secondary)
                    .accessibilityLabel("Expand projects")
                    .accessibilityValue(showProjectTasks ? "On" : "Off")
                    .help(showProjectTasks ? "Show projects as folders" : "Show tasks within projects")
                    Button { showNewItem = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add task, project, or Quick Add")
                        .disabled(!store.isConfigured)
                }
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) {
                now = $0
                Task { await store.updateCurrentBadge(at: now) }
                if store.hasPendingChanges { Task { await store.refresh() } }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
            .onChange(of: showProjectTasks) { _, _ in Task { await store.syncBadge() } }
            .onChange(of: pendingWidgetDestination) { _, destination in
                if destination != nil {
                    showNewItem = false
                    showSettings = false
                }
            }
            .navigationDestination(item: $pendingWidgetDestination) { destination in
                switch destination {
                case .task(let id):
                    if let task = store.tasks.first(where: { $0.id == id }) {
                        TaskEditor(task: task)
                    } else {
                        ContentUnavailableView("Task unavailable", systemImage: "checklist")
                    }
                case .project(let id):
                    if let project = store.projects.first(where: { $0.id == id }) {
                        ProjectTasksView(project: project)
                    } else {
                        ContentUnavailableView("Project unavailable", systemImage: "folder")
                    }
                }
            }
            .sheet(isPresented: $showNewItem) { NavigationStack { NewItemView() } }
            .sheet(item: $pendingQuickAdd) { launch in
                NavigationStack { NewItemView(initialKind: .quickAdd, startWithVoice: launch == .voice) }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .overlay(alignment: .bottom) {
                if let message = store.message {
                    Text(message).font(.caption).padding(10).background(.regularMaterial, in: Capsule()).padding()
                }
            }
        }
    }
}

struct TaskRow: View {
    let task: TodoTask
    let project: TodoProject?
    let onToggle: () -> Void

    private var effectiveStart: (date: String, time: String?)? {
        let own = task.startDate.map { (date: $0, time: task.startTime) }
        let parent = project?.startDate.map { (date: $0, time: project?.startTime) }
        switch (own, parent) {
        case (nil, nil): return nil
        case (let own?, nil): return own
        case (nil, let parent?): return parent
        case (let own?, let parent?):
            return "\(own.date)T\(own.time ?? "00:00")" >= "\(parent.date)T\(parent.time ?? "00:00")" ? own : parent
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(task.completedAt == nil ? Color.secondary : Color.green)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(task.completedAt == nil ? "Complete \(task.title)" : "Reopen \(task.title)")
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .foregroundStyle(task.completedAt == nil ? .primary : .secondary)
                    .strikethrough(task.completedAt != nil)
                HStack(spacing: 8) {
                    if let project {
                        Label(project.name, systemImage: "folder")
                            .lineLimit(1)
                    }
                    if let start = effectiveStart,
                       !TodoDates.hasStarted(startDate: start.date, startTime: start.time, at: Date()) {
                        Text(TodoDates.startLabel(date: start.date, time: start.time))
                    }
                    if let dueDate = task.dueDate {
                        Text("Due \(dueDate)")
                            .foregroundStyle(dueDate < TodoDates.string(from: Date()) && task.completedAt == nil ? Color.red : Color.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
