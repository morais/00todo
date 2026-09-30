import FoundationModels
import SwiftUI

enum NewItemKind: String, CaseIterable, Identifiable {
    case task = "Task"
    case project = "Project"
    case quickAdd = "Quick Add"

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
    @State private var draftKind: NewItemKind = .task
    @State private var prompt = ""
    @State private var promptBeforeDictation = ""
    @State private var voicePromptPending: String?
    @State private var voice = VoiceCapture()
    @State private var silenceTask: Task<Void, Never>?
    @State private var draftTask: Task<Void, Never>?
    @State private var draftRequestID = UUID()
    @State private var draftFailed = false
    @State private var hasPreview = false
    @State private var generating = false
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
    @FocusState private var promptFocused: Bool
    let startWithVoice: Bool

    init(initialProjectId: String? = nil, initialKind: NewItemKind = .task, startWithVoice: Bool = false) {
        _projectId = State(initialValue: initialProjectId)
        _kind = State(initialValue: initialKind)
        self.startWithVoice = startWithVoice
    }

    private var cleanedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanedSubtasks: [String] {
        subtasks.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        let titleLimit = effectiveKind == .project ? 120 : 240
        return (kind != .quickAdd || hasPreview) && !saving && !generating
            && !cleanedTitle.isEmpty && cleanedTitle.count <= titleLimit
            && notes.count <= 20_000
            && (effectiveKind != .project || (cleanedSubtasks.count <= 50
                && cleanedSubtasks.allSatisfy { $0.count <= 240 }))
    }

    var body: some View {
        Form {
            if kind == .quickAdd {
                Section {
                    HStack(spacing: 8) {
                        TextField("What would you like to add?", text: $prompt, axis: .vertical)
                            .lineLimit(2...5)
                            .focused($promptFocused)
                            .disabled(voice.isRecording || voice.isPreparing || saving)
                        Button {
                            if voice.isRecording { voice.stop() } else { beginVoice() }
                        } label: {
                            Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                                .font(.title3)
                                .foregroundStyle(voice.isRecording ? Color.red : Color.accentColor)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(voice.isRecording ? "Finish speaking" : "Speak your request")
                        .disabled(saving || voice.isPreparing)
                    }
                    if voice.isRecording { Label("Listening on this device…", systemImage: "waveform") }
                    if generating { ProgressView("Making draft…") }
                    else if draftFailed {
                        Button("Try again", systemImage: "arrow.clockwise") { scheduleDraft(immediate: true) }
                    }
                } footer: {
                    Text("Try “Shopping list: milk, eggs, bread.” A draft appears after you pause typing or finish speaking. Nothing is saved until you confirm.")
                }
                if let unavailableReason {
                    Section { Label(unavailableReason, systemImage: "info.circle").foregroundStyle(.secondary) }
                }
            }

            if kind != .quickAdd || hasPreview {
            if kind == .quickAdd {
                Section {
                    Picker("Create as", selection: $draftKind) {
                        Text("Task").tag(NewItemKind.task)
                        Text("Project").tag(NewItemKind.project)
                    }
                    .pickerStyle(.segmented)
                } header: { Text("Review before adding") }
            }
            Section {
                TextField("What needs doing?", text: $title)
                    .submitLabel(.done)
                    .onSubmit { if canSave { save() } }
                    .focused($titleFocused)
                TextEditor(text: $notes)
                    .frame(minHeight: 90)
                    .accessibilityLabel("Notes")
                NotesLinkButtons(notes: notes)
            }

            Section {
                StartScheduleFields(hasStart: $hasStart, start: $start,
                                    hasStartTime: $hasStartTime, startTime: $startTime)
            } footer: {
                Text(effectiveKind == .task
                    ? "Tasks with a future start date or time stay out of Available until then."
                    : "A future start date or time keeps the project and its tasks out of Available until then.")
            }

            Section {
                Toggle("Due date", isOn: $hasDue)
                if hasDue {
                    DatePicker("Due", selection: $due, displayedComponents: .date)
                }
            }

            if effectiveKind == .task {
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
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 4) {
                    Text("New")
                    Menu {
                        ForEach(NewItemKind.allCases) { option in
                            Button {
                                changeKind(to: option)
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
                    .accessibilityLabel("New \(kind.rawValue). Choose task, project, or Quick Add")
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
            if startWithVoice && kind == .quickAdd { beginVoice() }
            else if kind == .quickAdd { promptFocused = true }
            else { titleFocused = true }
        }
        .onChange(of: prompt) { _, updatedPrompt in
            let cameFromVoice = updatedPrompt == voicePromptPending
            voicePromptPending = nil
            guard !cameFromVoice, kind == .quickAdd,
                  !voice.isRecording && !voice.isPreparing && !voice.isFinishing else { return }
            scheduleDraft()
        }
        .onChange(of: title) { _, value in
            let singleLine = value.replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
            if singleLine != value { title = singleLine }
        }
        .onChange(of: voice.transcript) { _, transcript in
            guard !transcript.isEmpty else { return }
            let updated = promptBeforeDictation.isEmpty ? transcript : "\(promptBeforeDictation) \(transcript)"
            voicePromptPending = updated
            prompt = updated
            if voice.isRecording {
                silenceTask?.cancel()
                silenceTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.5))
                    guard !Task.isCancelled, voice.isRecording else { return }
                    voice.stop()
                }
            }
        }
        .onChange(of: voice.completionCount) { _, _ in
            silenceTask?.cancel()
            let transcript = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { return }
            let updated = promptBeforeDictation.isEmpty ? transcript : "\(promptBeforeDictation) \(transcript)"
            voicePromptPending = updated
            prompt = updated
            if let unavailableReason { errorText = unavailableReason }
            else { scheduleDraft(immediate: true) }
        }
        .onChange(of: voice.errorText) { _, message in if let message { errorText = message } }
        .onDisappear {
            silenceTask?.cancel()
            draftTask?.cancel()
            voice.cancel()
        }
    }

    private var effectiveKind: NewItemKind { kind == .quickAdd ? draftKind : kind }
    private var model: SystemLanguageModel { .default }

    private var unavailableReason: String? {
        switch model.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This device doesn't support Apple Intelligence. You can still add tasks and projects manually."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings to use Quick Add."
        case .unavailable(.modelNotReady): "The on-device model isn't ready yet. Try again after it finishes downloading."
        case .unavailable: "Apple Intelligence is unavailable right now. You can add items manually."
        }
    }

    private func changeKind(to option: NewItemKind) {
        guard kind != option else { return }
        if kind == .quickAdd {
            draftTask?.cancel()
            silenceTask?.cancel()
            voice.cancel()
        }
        kind = option
        if option == .quickAdd { promptFocused = true }
        else { titleFocused = true }
    }

    private func beginVoice() {
        draftTask?.cancel()
        draftRequestID = UUID()
        generating = false
        hasPreview = false
        draftFailed = false
        promptBeforeDictation = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await voice.start() }
    }

    private func scheduleDraft(immediate: Bool = false) {
        draftTask?.cancel()
        let requestID = UUID()
        draftRequestID = requestID
        generating = false
        hasPreview = false
        draftFailed = false
        let requestText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestText.isEmpty, !saving, unavailableReason == nil,
              !voice.isRecording, !voice.isPreparing, !voice.isFinishing else { return }
        draftTask = Task { @MainActor in
            if !immediate { try? await Task.sleep(for: .milliseconds(900)) }
            guard !Task.isCancelled, draftRequestID == requestID else { return }
            await generate(requestText, requestID: requestID)
        }
    }

    private func generate(_ requestText: String, requestID: UUID) async {
        generating = true
        defer { if draftRequestID == requestID { generating = false } }
        do {
            let session = LanguageModelSession(
                model: model,
                instructions: "Convert the user's request to a task by default. Use a project only when the user explicitly asks for a project or list, or names two or more distinct related subtasks. A single action is a task, not a project with one copy of that action as its subtask. For a shopping list, include only the items the user named. Do not invent items, dates, or times. The start date is absent by default, even if a due date is given; never fill it with today unless the user explicitly asks to start today. Only include a start time if the request explicitly says when work can begin on its start date. If no due date is specified, leave it empty. Notes may contain only extra details supplied by the user, never these instructions."
            )
            let today = TodoDates.string(from: Date())
            let response = try await session.respond(
                to: "Today is \(today), for resolving relative dates only. User request: \(requestText)",
                generating: GeneratedQuickAdd.self
            )
            guard !Task.isCancelled, draftRequestID == requestID else { return }
            let result = response.content
            let newTitle = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newTitle.isEmpty else { throw TodoError.server("The model didn't suggest a title. Try a more specific request.") }
            let modelSuggestedProject = switch result.kind {
            case .task: false
            case .project: true
            }
            let shape = QuickAddDraftShape.resolve(
                request: requestText,
                modelSuggestedProject: modelSuggestedProject,
                title: newTitle,
                subtasks: Array(result.subtasks.prefix(50))
            )
            draftKind = shape.isProject ? .project : .task
            title = shape.title
            notes = QuickAddNotes.cleaned(result.notes)
            let generatedStart = result.hasExplicitStartDate ? Self.validDate(result.startDate) : nil
            hasStart = generatedStart != nil
            if let generatedStart { start = generatedStart }
            let generatedTime = generatedStart != nil ? Self.validTime(result.startTime) : nil
            hasStartTime = generatedTime != nil
            if let generatedTime { startTime = generatedTime }
            hasDue = Self.validDate(result.dueDate) != nil
            if let date = Self.validDate(result.dueDate) { due = date }
            subtasks = shape.subtasks.map(NewSubtask.init(title:))
            hasPreview = true
        } catch {
            guard !Task.isCancelled, draftRequestID == requestID else { return }
            draftFailed = true
            errorText = error.localizedDescription
        }
    }

    private static func validDate(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 10, TodoDates.string(from: TodoDates.date(from: value)) == value else { return nil }
        return TodoDates.date(from: value)
    }

    private static func validTime(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil else { return nil }
        return TodoDates.timeDate(from: value)
    }

    private func save() {
        guard canSave else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                switch effectiveKind {
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
                case .quickAdd:
                    break
                }
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
