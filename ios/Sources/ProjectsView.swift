import SwiftUI

struct ProjectDraft {
    var name = ""
    var notes = ""
    var hasStart = false
    var start = Date()
    var hasStartTime = false
    var startTime = Date()
    var hasDue = false
    var due = Date()

    init(project: TodoProject? = nil) {
        if let project {
            name = project.name
            notes = project.notes
            hasStart = project.startDate != nil
            start = TodoDates.date(from: project.startDate)
            hasStartTime = project.startTime != nil
            startTime = TodoDates.timeDate(from: project.startTime)
            hasDue = project.dueDate != nil
            due = TodoDates.date(from: project.dueDate)
        }
    }

    var payload: [String: Any] {
        ["name": name.trimmingCharacters(in: .whitespacesAndNewlines),
         "notes": notes,
         "startDate": hasStart ? TodoDates.string(from: start) : NSNull(),
         "startTime": hasStart && hasStartTime ? TodoDates.timeString(from: startTime) : NSNull(),
         "dueDate": hasDue ? TodoDates.string(from: due) : NSNull()]
    }
}

struct ProjectRow: View {
    let project: TodoProject
    let openCount: Int
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: project.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(project.completedAt == nil ? Color.secondary : Color.green)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(project.completedAt == nil ? "Complete \(project.name)" : "Reopen \(project.name)")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Text(project.name)
                        .strikethrough(project.completedAt != nil)
                        .foregroundStyle(project.completedAt == nil ? .primary : .secondary)
                }
                HStack(spacing: 8) {
                    Text("\(openCount) \(openCount == 1 ? "subtask" : "subtasks")")
                    if let startDate = project.startDate,
                       !TodoDates.hasStarted(startDate: startDate, startTime: project.startTime, at: Date()) {
                        Text(TodoDates.startLabel(date: startDate, time: project.startTime))
                    }
                    if let dueDate = project.dueDate {
                        Text("Due \(dueDate)")
                            .foregroundStyle(dueDate < TodoDates.string(from: Date()) && project.completedAt == nil ? Color.red : Color.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct ProjectEditor: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProjectDraft
    @State private var saving = false
    @State private var errorText: String?
    let project: TodoProject?

    init(project: TodoProject? = nil) {
        self.project = project
        _draft = State(initialValue: ProjectDraft(project: project))
    }

    var body: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $draft.name)
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 90)
                    .accessibilityLabel("Notes")
            }
            Section {
                StartScheduleFields(hasStart: $draft.hasStart, start: $draft.start,
                                    hasStartTime: $draft.hasStartTime, startTime: $draft.startTime)
            } footer: {
                Text("Projects with a future start date or time stay out of Available, along with their tasks.")
            }
            Section {
                Toggle("Due date", isOn: $draft.hasDue)
                if draft.hasDue {
                    DatePicker("Due", selection: $draft.due, displayedComponents: .date)
                }
            }
        }
        .navigationTitle(project == nil ? "New project" : "Edit project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(saving || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { errorText != nil }, set: { if !$0 { errorText = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                if let project { try await store.updateProject(project.id, draft: draft) }
                else { try await store.createProject(draft) }
                dismiss()
            } catch { errorText = error.localizedDescription }
        }
    }
}

struct ProjectTasksView: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let project: TodoProject
    @State private var showNewTask = false
    @State private var showEdit = false
    @State private var showDelete = false
    @State private var showUpcoming = false
    @State private var errorText: String?
    @State private var now = Date()

    private var items: [TodoTask] {
        let parent = store.projects.first(where: { $0.id == project.id }) ?? project
        let parentIsAvailable = parent.isAvailable(at: now)
        return store.tasks.filter {
            $0.projectId == project.id && $0.isAvailable(at: now) && parentIsAvailable
        }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
    }

    private var upcomingItems: [TodoTask] {
        let parent = store.projects.first(where: { $0.id == project.id }) ?? project
        let parentIsUpcoming = !parent.isAvailable(at: now) && parent.completedAt == nil
        return store.tasks.filter {
            $0.projectId == project.id && $0.completedAt == nil && parent.completedAt == nil
                && (!$0.isAvailable(at: now) || parentIsUpcoming)
        }
            .sorted { "\($0.startDate ?? "9999-12-31")T\($0.startTime ?? "00:00")" < "\($1.startDate ?? "9999-12-31")T\($1.startTime ?? "00:00")" }
    }

    private var completedItems: [TodoTask] {
        store.tasks.filter { $0.projectId == project.id && $0.completedAt != nil }
            .sorted { ($0.completedAt ?? "") > ($1.completedAt ?? "") }
    }

    var body: some View {
        List {
            let current = store.projects.first(where: { $0.id == project.id }) ?? project
            if !current.notes.isEmpty {
                Section { Text(current.notes) }
            }
            if items.isEmpty && upcomingItems.isEmpty && completedItems.isEmpty {
                ContentUnavailableView("No tasks", systemImage: "checklist")
            } else {
                if !items.isEmpty {
                    Section("To do") {
                        ForEach(items) { task in
                            NavigationLink {
                                TaskEditor(task: task)
                            } label: {
                                TaskRow(task: task, project: nil) { Task { await store.toggle(task) } }
                            }
                        }
                    }
                }
                if !upcomingItems.isEmpty {
                    Section {
                        DisclosureGroup("Upcoming (\(upcomingItems.count))", isExpanded: $showUpcoming) {
                            ForEach(upcomingItems) { task in
                                NavigationLink {
                                    TaskEditor(task: task)
                                } label: {
                                    TaskRow(task: task, project: nil) { Task { await store.toggle(task) } }
                                }
                            }
                        }
                    }
                }
                if !completedItems.isEmpty {
                    Section("Completed") {
                        ForEach(completedItems) { task in
                            NavigationLink {
                                TaskEditor(task: task)
                            } label: {
                                TaskRow(task: task, project: nil) { Task { await store.toggle(task) } }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(store.projects.first(where: { $0.id == project.id })?.name ?? project.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewTask = true } label: { Label("New task", systemImage: "plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("Edit project") { showEdit = true }
                    Button((store.projects.first(where: { $0.id == project.id }) ?? project).completedAt == nil ? "Complete project" : "Reopen project") {
                        Task { await store.toggle(store.projects.first(where: { $0.id == project.id }) ?? project) }
                    }
                    Button("Delete project", role: .destructive) { showDelete = true }
                } label: { Label("Project actions", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showNewTask) {
            NavigationStack { NewItemView(initialProjectId: project.id) }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                ProjectEditor(project: store.projects.first(where: { $0.id == project.id }) ?? project)
            }
        }
        .confirmationDialog("Delete project? Its subtasks will become standalone tasks.", isPresented: $showDelete) {
            Button("Delete project", role: .destructive) {
                Task {
                    do { try await store.deleteProject(project.id); dismiss() }
                    catch { errorText = error.localizedDescription }
                }
            }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { errorText != nil }, set: { if !$0 { errorText = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
        .refreshable { await store.refresh() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
    }
}
