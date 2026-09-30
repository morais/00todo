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
        }
    }

    var payload: [String: Any] {
        ["title": title.trimmingCharacters(in: .whitespacesAndNewlines),
         "notes": notes,
         "projectId": projectId as Any? ?? NSNull(),
         "startDate": hasStart ? TodoDates.string(from: start) : NSNull(),
         "startTime": hasStart && hasStartTime ? TodoDates.timeString(from: startTime) : NSNull(),
         "dueDate": hasDue ? TodoDates.string(from: due) : NSNull()]
    }
}

struct TaskEditor: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskDraft
    @State private var saving = false
    @State private var errorText: String?
    @State private var confirmDelete = false
    let task: TodoTask?

    init(task: TodoTask? = nil, projectId: String? = nil) {
        self.task = task
        _draft = State(initialValue: TaskDraft(task: task, projectId: projectId))
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
                Picker("Project", selection: $draft.projectId) {
                    Text("No project · top-level task").tag(String?.none)
                    ForEach(store.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                if task != nil, let project = store.projects.first(where: { $0.id == draft.projectId }) {
                    NavigationLink {
                        ProjectTasksView(project: project)
                    } label: {
                        Label("Open project", systemImage: "folder")
                    }
                }
            }

            if let task {
                Section {
                    Button {
                        Task { await store.toggle(store.tasks.first(where: { $0.id == task.id }) ?? task) }
                    } label: {
                        let current = store.tasks.first(where: { $0.id == task.id }) ?? task
                        Label(current.completedAt == nil ? "Complete task" : "Reopen task",
                              systemImage: current.completedAt == nil ? "checkmark.circle" : "arrow.uturn.backward.circle")
                    }
                    .disabled(saving)
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete task", systemImage: "trash")
                    }
                    .disabled(saving)
                }
                .confirmationDialog("Delete this task?", isPresented: $confirmDelete) {
                    Button("Delete", role: .destructive) {
                        Task {
                            do { try await store.deleteTask(task.id); dismiss() }
                            catch { errorText = error.localizedDescription }
                        }
                    }
                }
            }
        }
        .navigationTitle(task == nil ? "New task" : "Edit task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || draft.title.count > 240 || draft.notes.count > 20_000)
            }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
        .onChange(of: draft.title) { _, value in
            let singleLine = value.replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
            if singleLine != value { draft.title = singleLine }
        }
    }

    private func save() {
        guard !saving, !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.title.count <= 240, draft.notes.count <= 20_000 else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                if let task { try await store.updateTask(task.id, draft: draft) }
                else { try await store.createTask(draft) }
                dismiss()
            } catch { errorText = error.localizedDescription }
        }
    }
}
