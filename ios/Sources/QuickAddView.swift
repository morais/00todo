import FoundationModels
import SwiftUI

@Generable
private enum GeneratedItemKind {
    case task
    case project
}

@Generable
private struct GeneratedQuickAdd {
    @Guide(description: "Use project for a list or an item with subtasks; otherwise task")
    var kind: GeneratedItemKind
    @Guide(description: "Short name for the task or project")
    var title: String
    @Guide(description: "Extra details explicitly supplied by the user, or empty")
    var notes: String
    @Guide(description: "Start date as YYYY-MM-DD only if the request explicitly says when work may begin; otherwise empty. Never default to today.")
    var startDate: String
    @Guide(description: "True only when the request explicitly specifies a start or availability date. A due date alone does not imply a start date.")
    var hasExplicitStartDate: Bool
    @Guide(description: "Local 24-hour HH:mm start time only when the user explicitly specifies when work may begin on its start date; otherwise empty. Requires an explicit start date.")
    var startTime: String
    @Guide(description: "Due date as YYYY-MM-DD if specified, otherwise empty")
    var dueDate: String
    @Guide(description: "For a project, each explicitly listed item as a short subtask; for a task, empty", .maximumCount(50))
    var subtasks: [String]
}

private enum QuickAddKind: String, CaseIterable, Identifiable {
    case task = "Task"
    case project = "Project"
    var id: Self { self }
}

private struct QuickAddSubtask: Identifiable {
    let id = UUID()
    var title: String
}

struct QuickAddView: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let startWithVoice: Bool
    @State private var prompt = ""
    @State private var promptBeforeDictation = ""
    @State private var voicePromptPending: String?
    @State private var voice = VoiceCapture()
    @State private var silenceTask: Task<Void, Never>?
    @State private var draftTask: Task<Void, Never>?
    @State private var draftRequestID = UUID()
    @State private var draftFailed = false
    @State private var kind: QuickAddKind = .task
    @State private var title = ""
    @State private var notes = ""
    @State private var hasStart = false
    @State private var start = Date()
    @State private var hasStartTime = false
    @State private var startTime = Date()
    @State private var hasDue = false
    @State private var due = Date()
    @State private var subtasks: [QuickAddSubtask] = []
    @State private var hasPreview = false
    @State private var generating = false
    @State private var saving = false
    @State private var errorText: String?

    init(startWithVoice: Bool = false) {
        self.startWithVoice = startWithVoice
    }

    private var model: SystemLanguageModel { .default }

    private var unavailableReason: String? {
        switch model.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This device doesn't support Apple Intelligence. You can still add tasks and projects from the + menu."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings to use Quick Add. Manual creation is still available from the + menu."
        case .unavailable(.modelNotReady): "The on-device model isn't ready yet. Try again after it finishes downloading, or use the + menu."
        case .unavailable: "Apple Intelligence is unavailable right now. You can use the + menu to add items manually."
        }
    }

    private var cleanedSubtasks: [String] {
        subtasks.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxTitle = kind == .project ? 120 : 240
        return hasPreview && !saving && !generating && !cleanedTitle.isEmpty
            && cleanedTitle.count <= maxTitle && notes.count <= 20_000
            && cleanedSubtasks.count <= 50 && cleanedSubtasks.allSatisfy { $0.count <= 240 }
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 8) {
                    TextField("What would you like to add?", text: $prompt, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityLabel("Describe a task or project")
                        .disabled(voice.isRecording || voice.isPreparing || saving)
                    Button {
                        if voice.isRecording {
                            voice.stop()
                        } else {
                            beginVoice()
                        }
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
                if voice.isRecording {
                    Label("Listening on this device…", systemImage: "waveform")
                        .foregroundStyle(.tint)
                }
                if generating {
                    ProgressView("Making draft…")
                } else if draftFailed {
                    Button("Try again", systemImage: "arrow.clockwise") {
                        scheduleDraft(immediate: true)
                    }
                }
            } header: {
                Text("Quick Add")
            } footer: {
                Text("Try “Shopping list: milk, eggs, bread” or “Pay rent next Friday.” A draft appears after you pause typing or finish speaking. Speech and drafting stay on this device; nothing is saved until you confirm.")
            }

            if let unavailableReason {
                Section {
                    Label(unavailableReason, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            if hasPreview {
                Section("Review before adding") {
                    Picker("Type", selection: $kind) {
                        ForEach(QuickAddKind.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    TextField(kind == .project ? "Project name" : "Task title", text: $title)
                    TextEditor(text: $notes)
                        .frame(minHeight: 70)
                        .accessibilityLabel("Notes")
                }
                Section {
                    StartScheduleFields(hasStart: $hasStart, start: $start,
                                        hasStartTime: $hasStartTime, startTime: $startTime)
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
                }
                if kind == .project {
                    Section("Subtasks") {
                        ForEach($subtasks) { $item in
                            HStack {
                                TextField("Item", text: $item.title)
                                Button(role: .destructive) { subtasks.removeAll { $0.id == item.id } } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove subtask")
                            }
                        }
                        if subtasks.count < 50 {
                            Button { subtasks.append(QuickAddSubtask(title: "")) } label: { Label("Add subtask", systemImage: "plus") }
                        }
                    }
                }
            }
        }
        .navigationTitle("Quick Add")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            if hasPreview {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled(!canSave)
                }
            }
        }
        .alert("Couldn't complete Quick Add", isPresented: Binding(
            get: { errorText != nil }, set: { if !$0 { errorText = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
        .task {
            if startWithVoice { beginVoice() }
        }
        .onChange(of: prompt) { _, updatedPrompt in
            let cameFromVoice = updatedPrompt == voicePromptPending
            voicePromptPending = nil
            guard !cameFromVoice else { return }
            guard !voice.isRecording && !voice.isPreparing && !voice.isFinishing else { return }
            scheduleDraft()
        }
        .onChange(of: voice.transcript) { _, transcript in
            guard !transcript.isEmpty else { return }
            let updatedPrompt = promptBeforeDictation.isEmpty ? transcript : "\(promptBeforeDictation) \(transcript)"
            voicePromptPending = updatedPrompt
            prompt = updatedPrompt
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
            let updatedPrompt = promptBeforeDictation.isEmpty ? transcript : "\(promptBeforeDictation) \(transcript)"
            voicePromptPending = updatedPrompt
            prompt = updatedPrompt
            if let unavailableReason {
                errorText = unavailableReason
            } else {
                scheduleDraft(immediate: true)
            }
        }
        .onChange(of: voice.errorText) { _, message in
            if let message { errorText = message }
        }
        .onDisappear {
            silenceTask?.cancel()
            draftTask?.cancel()
            voice.cancel()
        }
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
            if !immediate {
                try? await Task.sleep(for: .milliseconds(900))
            }
            guard !Task.isCancelled, draftRequestID == requestID else { return }
            await generate(requestText, requestID: requestID)
        }
    }

    private func generate(_ requestText: String, requestID: UUID) async {
        generating = true
        defer { if draftRequestID == requestID { generating = false } }
        do {
            let session = LanguageModelSession(model: model)
            let today = TodoDates.string(from: Date())
            let response = try await session.respond(
                to: "Today is \(today), for resolving relative dates only. Convert this request to one task or one project with subtasks. A shopping list is a project; every named item becomes a subtask. Do not invent items, dates, or times. The start date is absent by default, even if a due date is given; never fill it with today unless the user explicitly asks to start today. Only include a start time if the request explicitly says when work can begin on its start date. If no due date is specified, leave it empty. Request: \(requestText)",
                generating: GeneratedQuickAdd.self
            )
            guard !Task.isCancelled, draftRequestID == requestID else { return }
            let result = response.content
            let newTitle = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newTitle.isEmpty else { throw TodoError.server("The model didn't suggest a title. Try a more specific request.") }
            switch result.kind {
            case .task: kind = .task
            case .project: kind = .project
            }
            title = newTitle
            notes = result.notes
            let generatedStart = result.hasExplicitStartDate ? Self.validDate(result.startDate) : nil
            hasStart = generatedStart != nil
            if let generatedStart { start = generatedStart }
            let generatedTime = generatedStart != nil ? Self.validTime(result.startTime) : nil
            hasStartTime = generatedTime != nil
            if let generatedTime { startTime = generatedTime }
            hasDue = Self.validDate(result.dueDate) != nil
            if let date = Self.validDate(result.dueDate) { due = date }
            subtasks = Array(result.subtasks.prefix(50))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map(QuickAddSubtask.init(title:))
            hasPreview = true
        } catch {
            guard !Task.isCancelled, draftRequestID == requestID else { return }
            draftFailed = true
            errorText = error.localizedDescription
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                if kind == .task {
                    var draft = TaskDraft()
                    draft.title = title
                    draft.notes = notes
                    draft.hasStart = hasStart
                    draft.start = start
                    draft.hasStartTime = hasStartTime
                    draft.startTime = startTime
                    draft.hasDue = hasDue
                    draft.due = due
                    try await store.createTask(draft)
                } else {
                    var draft = ProjectDraft()
                    draft.name = title
                    draft.notes = notes
                    draft.hasStart = hasStart
                    draft.start = start
                    draft.hasStartTime = hasStartTime
                    draft.startTime = startTime
                    draft.hasDue = hasDue
                    draft.due = due
                    try await store.createProject(draft, subtasks: cleanedSubtasks)
                }
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
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
}
