import Foundation
import FoundationModels
import SwiftUI

@Generable
private struct SuggestedShareTitle {
    @Guide(description: "One short, actionable task title using only the shared text, source title, and link. Do not invent facts. No URL or newline.")
    var title: String
}

@MainActor final class ShareComposerModel: ObservableObject {
    @Published var title = ""
    @Published var notes = ""
    @Published var loading = true
    @Published var suggesting = false
    @Published var saving = false
    @Published var errorText: String?

    private weak var context: NSExtensionContext?
    private var suggestionTask: Task<Void, Never>?

    init(context: NSExtensionContext?) { self.context = context }

    var canSave: Bool {
        !loading && !saving && SharedSession.tenantId != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.count <= 240 && notes.count <= 20_000
    }

    func load() async {
        defer { loading = false }
        guard let content = await ShareInputLoader.load(context?.inputItems ?? []) else {
            errorText = "This share doesn't contain a web link or text."
            return
        }
        title = content.title
        notes = content.notes
        if SharedSession.tenantId == nil { errorText = "Open \(AppBrand.name) and sign in with Apple first." }
        let model = SystemLanguageModel.default
        guard case .available = model.availability, model.supportsLocale() else { return }
        suggesting = true
        let fallbackTitle = title
        suggestionTask = Task {
            defer { suggesting = false }
            do {
                let session = LanguageModelSession(
                    model: model,
                    instructions: "Suggest a concise title for a to-do task created from shared content. Use only what the user shared. Prefer the source title when it identifies the content. For a link with no descriptive title, suggest reviewing the linked page. Return only the task title."
                )
                let response = try await session.respond(to: content.modelPrompt, generating: SuggestedShareTitle.self)
                guard !Task.isCancelled, title == fallbackTitle else { return }
                let suggested = ShareTaskContent.cleanTitle(response.content.title)
                if !suggested.isEmpty { title = String(suggested.prefix(240)) }
            } catch {
                // Keep the immediately available deterministic title.
            }
        }
    }

    func save() async {
        guard canSave, let tenantId = SharedSession.tenantId,
              let serverAddress = SharedSession.serverAddress else { return }
        saving = true
        suggestionTask?.cancel()
        let item = SharedTask(id: UUID().uuidString.lowercased(), tenantId: tenantId,
                              serverAddress: serverAddress,
                              title: ShareTaskContent.cleanTitle(title), notes: notes,
                              createdAt: ISO8601DateFormatter().string(from: Date()))
        do { try SharedTaskInbox.save(item) }
        catch {
            errorText = "Couldn't save the shared task on this device: \(error.localizedDescription)"
            saving = false
            return
        }
        if await upload(item) { SharedTaskInbox.remove(item.id) }
        context?.completeRequest(returningItems: [], completionHandler: nil)
    }

    func cancel() {
        suggestionTask?.cancel()
        context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    private func upload(_ item: SharedTask) async -> Bool {
        guard let token = SharedSession.readToken(),
              let url = URL(string: item.serverAddress + "/v1/tasks") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "id": item.id, "title": item.title, "notes": item.notes
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        do {
            let (_, response) = try await URLSession(configuration: configuration).data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch { return false }
    }
}
