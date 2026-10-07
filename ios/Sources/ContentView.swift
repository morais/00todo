import SwiftUI

enum QuickAddLaunch: String, Identifiable {
    case text
    case voice
    var id: String { rawValue }

    init?(url: URL) {
        guard url.scheme == AppBrand.urlScheme, url.host == "quick-add", url.query == nil, url.fragment == nil else { return nil }
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

private struct DemoNotice: View {
    @Environment(TodoStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            Label("Demo data. Changes aren't saved.", systemImage: "sparkles")
                .font(.footnote.weight(.medium))
            Spacer(minLength: 0)
            Button("Sign in") { store.endDemo() }
                .font(.footnote.bold())
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
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
                // Stacked rather than a safe-area inset: split view navigation
                // bars ignore the inset and would slide under the notice.
                VStack(spacing: 0) {
                    if store.isDemo && !store.hidesDemoNotice { DemoNotice() }
                    TasksView(pendingQuickAdd: $pendingQuickAdd, pendingWidgetDestination: $pendingWidgetDestination)
                }
            } else {
                SignInView()
            }
        }
        .task {
            store.importSharedTasks()
            await store.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.importSharedTasks()
                Task { await store.refresh() }
            }
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
    case blocked = "Blocked"
    case someday = "Someday"
    case completed = "Completed"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .available: "checklist"
        case .upcoming: "calendar"
        case .blocked: "hand.raised"
        case .someday: "tray"
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
    /// Each tab's selected row, shown beside the list when there is room.
    @State private var selections: [TaskFilter: WidgetDestination] = [:]
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
            case .upcoming: item.completedAt == nil && item.someday != true && item.blocked != true && !item.isAvailable(at: now)
            case .blocked: item.completedAt == nil && item.someday != true && item.blocked == true
            case .someday: item.completedAt == nil && item.someday == true
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
                return item.completedAt == nil && item.someday != true && item.blocked != true
                    && parent?.completedAt == nil && parent?.someday != true && parent?.blocked != true
                    && (!item.isAvailable(at: now) || !(parent?.isAvailable(at: now) ?? true))
            case .blocked:
                return item.completedAt == nil && parent?.completedAt == nil
                    && item.someday != true && parent?.someday != true
                    && (item.blocked == true || parent?.blocked == true)
            case .someday:
                return item.completedAt == nil && parent?.completedAt == nil
                    && (item.someday == true || parent?.someday == true)
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

    @ViewBuilder private func itemRow(_ item: ListItem, showsSomedayLabel: Bool = true,
                                      showsBlockedLabel: Bool = true) -> some View {
        switch item {
        case .project(let project):
            NavigationLink(value: WidgetDestination.project(project.id)) {
                ProjectRow(
                    project: project,
                    openCount: store.tasks.filter { $0.projectId == project.id && $0.completedAt == nil }.count,
                    showsSomedayLabel: showsSomedayLabel,
                    showsBlockedLabel: showsBlockedLabel
                ) { Task { await store.toggle(project) } }
            }
        case .task(let task):
            NavigationLink(value: WidgetDestination.task(task.id)) {
                TaskRow(task: task, project: store.projects.first { $0.id == task.projectId },
                        showsSomedayLabel: showsSomedayLabel,
                        showsBlockedLabel: showsBlockedLabel) { Task { await store.toggle(task) } }
            }
        }
    }

    private func list(for filter: TaskFilter) -> some View {
        let items = visibleItems(for: filter)
        let blockedItems = filter == .upcoming ? visibleItems(for: .blocked) : []
        let somedayItems = filter == .upcoming ? visibleItems(for: .someday) : []
        return List(selection: Binding(get: { selections[filter] }, set: { selections[filter] = $0 })) {
            if items.isEmpty && blockedItems.isEmpty && somedayItems.isEmpty {
                ContentUnavailableView(filter == .available ? "All clear" : filter == .someday ? "Nothing in Someday" : "No items",
                                       systemImage: filter == .someday ? "tray" : "checkmark.circle")
            } else if filter == .upcoming {
                ForEach(upcomingSections(for: items), id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in itemRow(item) }
                    }
                }
                if !blockedItems.isEmpty {
                    Section("Blocked") {
                        ForEach(blockedItems) { item in itemRow(item, showsSomedayLabel: false, showsBlockedLabel: false) }
                    }
                }
                if !somedayItems.isEmpty {
                    Section("Someday") {
                        ForEach(somedayItems) { item in itemRow(item, showsSomedayLabel: false, showsBlockedLabel: false) }
                    }
                }
            } else if filter == .completed {
                Section {
                    ForEach(items) { item in itemRow(item) }
                } footer: {
                    Text("Shows items completed in the last 90 days.")
                }
            } else {
                ForEach(items) { item in itemRow(item) }
            }
        }
            .contentMargins(.top, verticalSizeClass == .compact ? 0 : nil, for: .scrollContent)
            .refreshable { await store.refresh() }
            .modifier(PullUpToAddTask(enabled: filter == .available || filter == .upcoming) {
                guard !showNewItem, store.isConfigured else { return }
                showNewItem = true
            })
    }

    private func listColumn(for filter: TaskFilter) -> some View {
        list(for: filter)
            .navigationTitle("\(AppBrand.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(AppBrand.name)")
                        .font(.title2.bold())
                        // The navigation bar caps its text size; long-press
                        // shows the title enlarged at accessibility sizes.
                        .accessibilityShowsLargeContentViewer()
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
                    .accessibilityAddTraits(.isToggle)
                    .help(showProjectTasks ? "Show projects as folders" : "Show tasks within projects")
                    Button { showNewItem = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add task, project, or Quick Add")
                        .disabled(!store.isConfigured)
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 520)
    }

    private func exists(_ selection: WidgetDestination) -> Bool {
        switch selection {
        case .task(let id): store.tasks.contains { $0.id == id }
        case .project(let id): store.projects.contains { $0.id == id }
        }
    }

    private var completedSelections: Set<WidgetDestination> {
        Set(store.tasks.filter { $0.completedAt != nil }.map { .task($0.id) })
            .union(store.projects.filter { $0.completedAt != nil }.map { .project($0.id) })
    }

    @ViewBuilder private func detail(for selection: WidgetDestination?) -> some View {
        switch selection {
        case .task(let id):
            if let task = store.tasks.first(where: { $0.id == id }) {
                TaskEditor(task: task).id(id)
            } else {
                ContentUnavailableView("Task unavailable", systemImage: "checklist")
            }
        case .project(let id):
            if let project = store.projects.first(where: { $0.id == id }) {
                ProjectTasksView(project: project).id(id)
            } else {
                ContentUnavailableView("Project unavailable", systemImage: "folder")
            }
        case nil:
            ContentUnavailableView("Nothing selected", systemImage: "checklist",
                                   description: Text("Choose a task or project to see it here."))
        }
    }

    var body: some View {
        // On compact widths each split view collapses into a stack, so a row
        // tap still navigates into the task as before.
        TabView(selection: $filter) {
            ForEach(TaskFilter.allCases.filter { $0 != .blocked && $0 != .someday }) { choice in
                NavigationSplitView {
                    listColumn(for: choice)
                } detail: {
                    NavigationStack { detail(for: selections[choice]) }
                        .id(selections[choice])
                }
                .navigationSplitViewStyle(.balanced)
                .tabItem { Label(choice.rawValue, systemImage: choice.symbol) }
                .tag(choice)
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) {
            now = $0
            store.importSharedTasks()
            Task { await store.updateCurrentBadge(at: now) }
            if store.hasPendingChanges { Task { await store.pushPendingChanges() } }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
        .onChange(of: showProjectTasks) { _, _ in Task { await store.syncBadge() } }
        .onChange(of: store.tasks.map(\.id) + store.projects.map(\.id)) { _, _ in
            // A deleted task or project leaves nothing to show beside the list.
            selections = selections.filter { exists($0.value) }
        }
        .onChange(of: completedSelections) { _, completed in
            // Available and Upcoming no longer contain completed items, so
            // their detail panes should not keep showing the departed row.
            for choice in [TaskFilter.available, .upcoming] {
                if let selection = selections[choice], completed.contains(selection) {
                    selections[choice] = nil
                }
            }
        }
        .onChange(of: pendingWidgetDestination, initial: true) { _, destination in
            guard let destination else { return }
            showNewItem = false
            showSettings = false
            selections[filter] = destination
            pendingWidgetDestination = nil
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

struct TaskRow: View {
    let task: TodoTask
    let project: TodoProject?
    var showsSomedayLabel = true
    var showsBlockedLabel = true
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

    private var hasVisibleDetails: Bool {
        project != nil
            || (showsSomedayLabel && (task.someday == true || project?.someday == true))
            || (showsBlockedLabel && (task.blocked == true || project?.blocked == true))
            || effectiveStart.map { !TodoDates.hasStarted(startDate: $0.date, startTime: $0.time, at: Date()) } == true
            || task.dueDate != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(task.completedAt == nil ? Color.secondary : Color.green)
            }
            .buttonStyle(.borderless)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .foregroundStyle(task.completedAt == nil ? .primary : .secondary)
                    .strikethrough(task.completedAt != nil)
                if hasVisibleDetails {
                    RowDetails {
                        if let project {
                            Label(project.name, systemImage: "folder")
                        }
                        if showsSomedayLabel && (task.someday == true || project?.someday == true) {
                            Label("Someday", systemImage: "tray")
                        }
                        if showsBlockedLabel && (task.blocked == true || project?.blocked == true) {
                            Label("Blocked", systemImage: "hand.raised")
                        }
                        if let start = effectiveStart,
                           !TodoDates.hasStarted(startDate: start.date, startTime: start.time, at: Date()) {
                            Text(TodoDates.startLabel(date: start.date, time: start.time))
                        }
                        if let dueDate = task.dueDate {
                            DueLabel(dueDate: dueDate, isOpen: task.completedAt == nil)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
        .modifier(CompletableRow(isCompleted: task.completedAt != nil, onToggle: onToggle))
    }
}
