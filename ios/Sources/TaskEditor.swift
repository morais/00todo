import SwiftUI

struct TaskDraft {
    var title = ""
    var notes = ""
    var projectId: String?
    var hasStart = false
    var start = Date()
    var hasStartTime = false
    var startTime = Date()
    var hasDue = false
    var due = Date()
    var someday = false
    var blocked = false

    init(task: TodoTask? = nil, projectId: String? = nil) {
        self.projectId = task?.projectId ?? projectId
        if let task {
            title = task.title
            notes = task.notes
            hasStart = task.startDate != nil
            start = TodoDates.date(from: task.startDate)
            hasStartTime = task.startTime != nil
            startTime = TodoDates.timeDate(from: task.startTime)
            hasDue = task.dueDate != nil
            due = TodoDates.date(from: task.dueDate)
            someday = task.someday == true
            blocked = task.blocked == true
        }
    }

    var payload: [String: Any] {
        ["title": title.trimmingCharacters(in: .whitespacesAndNewlines),
         "notes": notes,
         "projectId": projectId as Any? ?? NSNull(),
         "startDate": hasStart ? TodoDates.string(from: start) : NSNull(),
         "startTime": hasStart && hasStartTime ? TodoDates.timeString(from: startTime) : NSNull(),
         "dueDate": hasDue ? TodoDates.string(from: due) : NSNull(),
         "someday": someday,
         "blocked": blocked]
    }
}

extension TaskDraft {
    /// The payload as stable JSON, so drafts that would store the same task compare equal.
    var savedForm: Data? { try? JSONSerialization.data(withJSONObject: payload, options: .sortedKeys) }
}

/// Edits an existing task. Changes save automatically a moment after typing
/// stops and when the editor goes away; Revert restores the task as it was
/// when the editor opened.
struct TaskEditor: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskDraft
    @State private var original: TaskDraft
    @State private var lastSaved: TaskDraft
    @State private var deleted = false
    @State private var errorText: String?
    @State private var confirmDelete = false
    let task: TodoTask

    init(task: TodoTask) {
        self.task = task
        let draft = TaskDraft(task: task)
        _draft = State(initialValue: draft)
        _original = State(initialValue: draft)
        _lastSaved = State(initialValue: draft)
    }

    /// Everything as edited, keeping the last saved title while the field is
    /// blank or too long, so other edits are not lost.
    private var savableDraft: TaskDraft? {
        var result = draft
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.count > 240 { result.title = lastSaved.title }
        return result.notes.count <= 20_000 ? result : nil
    }

    var body: some View {
        Form {
            Section("Task") {
                TextField("What needs doing?", text: $draft.title)
                    .submitLabel(.done)
                    .onSubmit { save() }
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 90)
                    .accessibilityLabel("Notes")
                NotesLinkButtons(notes: draft.notes)
            }

            Section {
                StartScheduleFields(hasStart: $draft.hasStart, start: $draft.start,
                                    hasStartTime: $draft.hasStartTime, startTime: $draft.startTime)
            } footer: {
                Text("Tasks with a future start date or time stay out of Available until then.")
            }

            Section {
                Toggle("Due date", isOn: $draft.hasDue)
                if draft.hasDue {
                    DatePicker("Due", selection: $draft.due, displayedComponents: .date)
                }
            }

            Section {
                Toggle("Blocked", isOn: $draft.blocked)
                    .onChange(of: draft.blocked) { _, value in if value { draft.someday = false } }
            } footer: {
                Text(store.projects.first(where: { $0.id == draft.projectId })?.blocked == true
                     ? "This task stays Blocked while its project is blocked, even if this switch is off."
                     : "Keep this out of Available until the blocker is cleared.")
            }

            Section {
                Toggle("Someday", isOn: $draft.someday)
                    .onChange(of: draft.someday) { _, value in if value { draft.blocked = false } }
            } footer: {
                Text(store.projects.first(where: { $0.id == draft.projectId })?.someday == true
                     ? "This task stays in Someday while its project is there, even if this switch is off."
                     : "Keep this out of Available and Upcoming until you move it back.")
            }

            Section {
                Picker("Project", selection: $draft.projectId) {
                    Text("No project · top-level task").tag(String?.none)
                    ForEach(store.projects.filter { $0.completedAt == nil || $0.id == draft.projectId }) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                if let project = store.projects.first(where: { $0.id == draft.projectId }) {
                    NavigationLink {
                        ProjectTasksView(project: project)
                    } label: {
                        Label("Open project", systemImage: "folder")
                    }
                }
            }

            Section {
                Button {
                    Task { await store.toggle(store.tasks.first(where: { $0.id == task.id }) ?? task) }
                } label: {
                    let current = store.tasks.first(where: { $0.id == task.id }) ?? task
                    Label(current.completedAt == nil ? "Complete task" : "Reopen task",
                          systemImage: current.completedAt == nil ? "checkmark.circle" : "arrow.uturn.backward.circle")
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete task", systemImage: "trash")
                }
            }
            .confirmationDialog("Delete this task?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    deleted = true
                    Task {
                        do { try await store.deleteTask(task.id); dismiss() }
                        catch { deleted = false; errorText = error.localizedDescription }
                    }
                }
            }
        }
        .navigationTitle("Edit task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Revert") {
                    draft = original
                    save()
                }
                .disabled(draft.savedForm == original.savedForm && lastSaved.savedForm == original.savedForm)
            }
        }
        .task(id: draft.savedForm) {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { save() }
        }
        .onDisappear { save() }
        .alert("Couldn't delete", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
        .onChange(of: draft.title) { _, value in
            let singleLine = value.replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
            if singleLine != value { draft.title = singleLine }
        }
    }

    private func save() {
        guard !deleted, let next = savableDraft, next.savedForm != lastSaved.savedForm else { return }
        lastSaved = next
        let id = task.id
        // Reported through the store: the editor may already be gone.
        Task {
            do { try await store.updateTask(id, draft: next) }
            catch { store.message = error.localizedDescription }
        }
    }
}
