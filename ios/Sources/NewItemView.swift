import SwiftUI

private enum NewItemKind: String, CaseIterable, Identifiable {
    case task = "Task"
    case project = "Project"

    var id: Self { self }
}

private struct NewSubtask: Identifiable {
    let id = UUID()
    var title: String
}

struct NewItemView: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kind: NewItemKind = .task
    @State private var title = ""
    @State private var notes = ""
    @State private var hasStart = false
    @State private var start = Date()
    @State private var hasStartTime = false
    @State private var startTime = Date()
    @State private var hasDue = false
    @State private var due = Date()
    @State private var projectId: String?
    @State private var subtasks: [NewSubtask] = []
    @State private var saving = false
    @State private var errorText: String?
    @FocusState private var titleFocused: Bool

    init(initialProjectId: String? = nil) {
        _projectId = State(initialValue: initialProjectId)
    }

    private var cleanedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanedSubtasks: [String] {
        subtasks.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        let titleLimit = kind == .project ? 120 : 240
        return !saving && !cleanedTitle.isEmpty && cleanedTitle.count <= titleLimit
            && notes.count <= 20_000
            && cleanedSubtasks.count <= 50
            && cleanedSubtasks.allSatisfy { $0.count <= 240 }
    }

    var body: some View {
        Form {
            Section {
                TextField("What needs doing?", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($titleFocused)
                TextEditor(text: $notes)
                    .frame(minHeight: 90)
                    .accessibilityLabel("Notes")
            }

            Section {
                StartScheduleFields(hasStart: $hasStart, start: $start,
                                    hasStartTime: $hasStartTime, startTime: $startTime)
            } footer: {
                Text(kind == .task
                    ? "Tasks with a future start date or time stay out of Available until then."
                    : "A future start date or time keeps the project and its tasks out of Available until then.")
            }

            Section {
                Toggle("Due date", isOn: $hasDue)
                if hasDue {
                    DatePicker("Due", selection: $due, displayedComponents: .date)
                }
            }

            if kind == .task {
                Section {
                    Picker("Project", selection: $projectId) {
                        Text("No project · top-level task").tag(String?.none)
                        ForEach(store.projects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                }
            } else {
                Section("Tasks") {
                    ForEach($subtasks) { $subtask in
                        HStack {
                            TextField("Task", text: $subtask.title)
                            Button(role: .destructive) {
                                subtasks.removeAll { $0.id == subtask.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove task")
                        }
                    }
                    if subtasks.count < 50 {
                        Button { subtasks.append(NewSubtask(title: "")) } label: {
                            Label("Add task", systemImage: "plus")
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 4) {
                    Text("New")
                    Menu {
                        ForEach(NewItemKind.allCases) { option in
                            Button {
                                kind = option
                            } label: {
                                if kind == option {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(kind.rawValue.lowercased())
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.tint)
                    }
                    .accessibilityLabel("Create as \(kind.rawValue). Choose task or project")
                }
                .font(.headline)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { save() }
                    .disabled(!canSave)
            }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            titleFocused = true
        }
    }

    private func save() {
        guard canSave else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                switch kind {
                case .task:
                    var draft = TaskDraft()
                    draft.title = cleanedTitle
                    draft.notes = notes
                    draft.projectId = projectId
                    draft.hasStart = hasStart
                    draft.start = start
                    draft.hasStartTime = hasStartTime
                    draft.startTime = startTime
                    draft.hasDue = hasDue
                    draft.due = due
                    try await store.createTask(draft)
                case .project:
                    var draft = ProjectDraft()
                    draft.name = cleanedTitle
                    draft.notes = notes
                    draft.hasStart = hasStart
                    draft.start = start
                    draft.hasStartTime = hasStartTime
                    draft.startTime = startTime
                    draft.hasDue = hasDue
                    draft.due = due
                    if cleanedSubtasks.isEmpty {
                        try await store.createProject(draft)
                    } else {
                        try await store.createProject(draft, subtasks: cleanedSubtasks)
                    }
                }
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
