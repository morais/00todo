import Foundation
import Observation
import Security
import WidgetKit

enum TodoError: LocalizedError {
    case invalidServer
    case notConfigured
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidServer: "Use an HTTPS server address, or HTTP for localhost."
        case .notConfigured: "Sign in with Apple to continue."
        case .server(let message): message
        }
    }
}

private struct APIError: Decodable { var error: String }
private struct HTTPFailure: LocalizedError {
    let status: Int
    let detail: String
    var errorDescription: String? { detail }
}
private struct MCPConnectionsResponse: Decodable { var connections: [MCPConnection] }
private struct AppleLoginResponse: Decodable {
    var token: String
    var expiresAt: String
    var tenant: Account
    struct Account: Decodable { var id: String; var email: String? }
}

struct CreatedProject {
    let id: String
    let taskIDs: [String]
}

@MainActor @Observable final class TodoStore {
    var projects: [TodoProject] = []
    var tasks: [TodoTask] = []
    var serverAddress: String
    var message: String?
    var refreshing = false
    private(set) var token: String
    private(set) var accountEmail: String?
    private(set) var tenantId: String?
    private(set) var pendingChanges: [PendingMutation] = []
    private var syncing = false
    private var refreshAfterCurrent = false
    private(set) var isScreenshotDemo = false

    private static let tokenService = "00todo.api-token"

    /// Release builds only talk to the server in Info.plist. A user-entered
    /// server would receive the Apple identity token and one-time code at
    /// sign-in, which it could replay against the real server, so the override
    /// exists for development builds only.
    static var allowsCustomServer: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    init() {
        let configuredServer = Bundle.main.object(forInfoDictionaryKey: "TodoServerBaseURL") as? String ?? ""
        let savedServer = UserDefaults.standard.string(forKey: "serverAddress")
        serverAddress = Self.allowsCustomServer ? (savedServer ?? configuredServer) : configuredServer
        if !Self.allowsCustomServer, let savedServer, savedServer != configuredServer {
            // A session made against another server must not follow the user
            // to this one.
            UserDefaults.standard.removeObject(forKey: "serverAddress")
            UserDefaults.standard.removeObject(forKey: "accountEmail")
            UserDefaults.standard.removeObject(forKey: "tenantId")
            Self.deleteToken()
        }
        token = Self.readToken()
        accountEmail = UserDefaults.standard.string(forKey: "accountEmail")
        tenantId = UserDefaults.standard.string(forKey: "tenantId")
        #if TODO_SCREENSHOTS
        if ProcessInfo.processInfo.arguments.contains("--screenshot-demo") {
            UserDefaults.standard.set(true, forKey: "showProjectTasksInLists")
            let snapshot = DemoDataCatalog.screenshotSnapshot()
            serverAddress = "https://screenshot-demo.invalid"
            token = "screenshot-only"
            accountEmail = "Screenshot demo"
            tenantId = "screenshot-demo"
            projects = snapshot.projects
            tasks = snapshot.tasks
            isScreenshotDemo = true
            return
        }
        #endif
        if !token.isEmpty, tenantId != nil {
            loadCachedState()
            if let tenantId { try? SharedSession.publish(tenantId: tenantId, serverAddress: serverAddress, token: token) }
        } else if token.isEmpty || tenantId == nil {
            WidgetSnapshotStore.clear()
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
            Task { await AvailableBadge.clear() }
        }
    }

    var isConfigured: Bool { !serverAddress.isEmpty && !token.isEmpty }
    var hasPendingChanges: Bool { !pendingChanges.isEmpty }

    func configureServer(address: String) throws {
        let cleaned = address.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: cleaned), let host = url.host,
              (url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host))),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw TodoError.invalidServer
        }
        if cleaned != serverAddress {
            guard pendingChanges.isEmpty else {
                throw TodoError.server("Sync pending changes before changing servers.")
            }
            clearLocalSession()
        }
        serverAddress = cleaned
        UserDefaults.standard.set(cleaned, forKey: "serverAddress")
    }

    func signInWithApple(identityToken: String, authorizationCode: String, rawNonce: String) async throws {
        guard let url = URL(string: serverAddress + "/v1/auth/apple") else { throw TodoError.invalidServer }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "identityToken": identityToken, "authorizationCode": authorizationCode, "nonce": rawNonce
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TodoError.server("No server response") }
        guard (200..<300).contains(response.statusCode) else {
            throw TodoError.server((try? JSONDecoder().decode(APIError.self, from: data).error) ?? "Sign-in failed (\(response.statusCode))")
        }
        let login = try JSONDecoder().decode(AppleLoginResponse.self, from: data)
        try Self.saveToken(login.token)
        if tenantId != login.tenant.id {
            projects = []
            tasks = []
            pendingChanges = []
            try? FileManager.default.removeItem(at: Self.cacheURL)
            WidgetSnapshotStore.clear()
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
            await AvailableBadge.clear()
        }
        SharedSession.clear()
        token = login.token
        accountEmail = login.tenant.email
        tenantId = login.tenant.id
        UserDefaults.standard.set(login.tenant.email, forKey: "accountEmail")
        UserDefaults.standard.set(login.tenant.id, forKey: "tenantId")
        try? SharedSession.publish(tenantId: login.tenant.id, serverAddress: serverAddress, token: login.token)
        loadCachedState()
        await refresh()
    }

    func signOut() async {
        if isConfigured {
            let _: [String: Bool]? = try? await request("/v1/auth/logout", method: "POST")
        }
        clearLocalSession()
    }

    func deleteAccount(identityToken: String, authorizationCode: String, rawNonce: String) async throws {
        let _: [String: Bool] = try await request("/v1/auth/delete-account", method: "POST", body: [
            "identityToken": identityToken, "authorizationCode": authorizationCode, "nonce": rawNonce
        ])
        let deletedTenant = tenantId
        clearLocalSession()
        if let deletedTenant {
            try? FileManager.default.removeItem(at: Self.stateURL(for: deletedTenant))
            clearDemoData(for: deletedTenant)
        }
    }

    private func clearLocalSession() {
        token = ""
        accountEmail = nil
        tenantId = nil
        projects = []
        tasks = []
        pendingChanges = []
        message = nil
        Self.deleteToken()
        SharedSession.clear()
        UserDefaults.standard.removeObject(forKey: "accountEmail")
        UserDefaults.standard.removeObject(forKey: "tenantId")
        try? FileManager.default.removeItem(at: Self.cacheURL)
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
        Task { await AvailableBadge.clear() }
    }

    private var widgetSnapshot: WidgetSnapshot {
        WidgetSnapshot(
            projects: projects.map { WidgetProject(id: $0.id, name: $0.name, startDate: $0.startDate,
                                                  startTime: $0.startTime, dueDate: $0.dueDate,
                                                  completedAt: $0.completedAt, sortOrder: $0.sortOrder, createdAt: $0.createdAt) },
            tasks: tasks.map { WidgetTask(id: $0.id, title: $0.title, projectId: $0.projectId,
                                          startDate: $0.startDate, startTime: $0.startTime,
                                          dueDate: $0.dueDate, completedAt: $0.completedAt,
                                          sortOrder: $0.sortOrder, createdAt: $0.createdAt) }
        )
    }

    private var expandProjects: Bool {
        UserDefaults.standard.object(forKey: "showProjectTasksInLists") as? Bool ?? true
    }

    func syncBadge() async {
        guard isConfigured, !isScreenshotDemo else { return }
        await AvailableBadge.sync(snapshot: widgetSnapshot, expandProjects: expandProjects)
    }

    func updateCurrentBadge(at now: Date = Date()) async {
        guard isConfigured, !isScreenshotDemo else { return }
        await AvailableBadge.updateCurrent(snapshot: widgetSnapshot, expandProjects: expandProjects, at: now)
    }

    func refresh() async {
        guard isConfigured, !isScreenshotDemo else { return }
        guard !refreshing else {
            refreshAfterCurrent = true
            return
        }
        let currentTenant = tenantId
        let currentToken = token
        refreshing = true
        defer {
            refreshing = false
            if refreshAfterCurrent {
                refreshAfterCurrent = false
                Task { await refresh() }
            }
        }
        if !pendingChanges.isEmpty {
            guard await flushPendingChanges() else { return }
        }
        do {
            let snapshot: TodoSnapshot = try await request("/v1/snapshot")
            guard tenantId == currentTenant, token == currentToken, pendingChanges.isEmpty else { return }
            projects = snapshot.projects
            tasks = snapshot.tasks
            try saveLocalState()
            if WidgetSnapshotStore.save(widgetSnapshot) {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
            }
            await syncBadge()
            message = nil
        } catch {
            if tenantId == currentTenant, token == currentToken { message = error.localizedDescription }
        }
    }

    func importSharedTasks() {
        guard isConfigured, !isScreenshotDemo, let tenantId else { return }
        for item in SharedTaskInbox.pending(tenantId: tenantId, serverAddress: serverAddress) {
            if tasks.contains(where: { $0.id == item.id }) {
                SharedTaskInbox.remove(item.id)
                continue
            }
            do {
                let mutation = try PendingMutation(method: "POST", path: "/v1/tasks", body: [
                    "id": item.id, "title": item.title, "notes": item.notes
                ])
                try record(mutation) {
                    tasks.append(TodoTask(id: item.id, title: item.title, notes: item.notes,
                                          projectId: nil, startDate: nil, startTime: nil, dueDate: nil,
                                          completedAt: nil, sortOrder: 0, createdAt: item.createdAt,
                                          updatedAt: item.createdAt))
                }
                SharedTaskInbox.remove(item.id)
            } catch { message = "Couldn't import a shared task: \(error.localizedDescription)" }
        }
    }

    @discardableResult func createTask(_ draft: TaskDraft) async throws -> String {
        let id = UUID().uuidString.lowercased()
        let now = Self.timestamp()
        var body = draft.payload
        body["id"] = id
        let change = try PendingMutation(method: "POST", path: "/v1/tasks", body: body)
        try record(change) {
            tasks.append(TodoTask(id: id, title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                  notes: draft.notes, projectId: draft.projectId,
                                  startDate: draft.hasStart ? TodoDates.string(from: draft.start) : nil,
                                  startTime: draft.hasStart && draft.hasStartTime ? TodoDates.timeString(from: draft.startTime) : nil,
                                  dueDate: draft.hasDue ? TodoDates.string(from: draft.due) : nil,
                                  completedAt: nil, sortOrder: 0, createdAt: now, updatedAt: now))
        }
        return id
    }

    func updateTask(_ id: String, draft: TaskDraft) async throws {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { throw TodoError.server("Task not found") }
        let change = try PendingMutation(method: "PATCH", path: "/v1/tasks/\(id)", body: draft.payload)
        try record(change) {
            tasks[index].title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            tasks[index].notes = draft.notes
            tasks[index].projectId = draft.projectId
            tasks[index].startDate = draft.hasStart ? TodoDates.string(from: draft.start) : nil
            tasks[index].startTime = draft.hasStart && draft.hasStartTime ? TodoDates.timeString(from: draft.startTime) : nil
            tasks[index].dueDate = draft.hasDue ? TodoDates.string(from: draft.due) : nil
            tasks[index].updatedAt = Self.timestamp()
        }
    }

    func toggle(_ item: TodoTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        let completed = tasks[index].completedAt == nil
        do {
            let change = try PendingMutation(method: "PATCH", path: "/v1/tasks/\(item.id)", body: ["completed": completed])
            try record(change) { tasks[index].completedAt = completed ? Self.timestamp() : nil }
        } catch {
            message = error.localizedDescription
        }
    }

    func deleteTask(_ id: String) async throws {
        let change = try PendingMutation(method: "DELETE", path: "/v1/tasks/\(id)")
        try record(change) { tasks.removeAll { $0.id == id } }
    }

    @discardableResult func createProject(_ draft: ProjectDraft) async throws -> CreatedProject {
        try await createProject(draft, subtasks: [])
    }

    @discardableResult func createProject(_ draft: ProjectDraft, subtasks: [String]) async throws -> CreatedProject {
        let projectId = UUID().uuidString.lowercased()
        let now = Self.timestamp()
        var projectBody = draft.payload
        projectBody["id"] = projectId
        let childIDs = subtasks.map { _ in UUID().uuidString.lowercased() }
        let taskBodies: [[String: Any]] = subtasks.enumerated().map { index, title in
            ["id": childIDs[index], "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
             "notes": "", "startDate": NSNull(), "startTime": NSNull(), "dueDate": NSNull(), "sortOrder": index]
        }
        let change = try PendingMutation(method: "POST", path: "/v1/projects-with-tasks",
                                         body: ["project": projectBody, "tasks": taskBodies])
        try record(change) {
            projects.append(TodoProject(id: projectId, name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                        notes: draft.notes, startDate: draft.hasStart ? TodoDates.string(from: draft.start) : nil,
                                        startTime: draft.hasStart && draft.hasStartTime ? TodoDates.timeString(from: draft.startTime) : nil,
                                        dueDate: draft.hasDue ? TodoDates.string(from: draft.due) : nil,
                                        completedAt: nil, sortOrder: 0, createdAt: now, updatedAt: now))
            for (index, title) in subtasks.enumerated() {
                tasks.append(TodoTask(id: childIDs[index], title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                      notes: "", projectId: projectId, startDate: nil, startTime: nil, dueDate: nil,
                                      completedAt: nil, sortOrder: index, createdAt: now, updatedAt: now))
            }
        }
        return CreatedProject(id: projectId, taskIDs: childIDs)
    }

    func updateProject(_ id: String, draft: ProjectDraft) async throws {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { throw TodoError.server("Project not found") }
        let change = try PendingMutation(method: "PATCH", path: "/v1/projects/\(id)", body: draft.payload)
        try record(change) {
            projects[index].name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            projects[index].notes = draft.notes
            projects[index].startDate = draft.hasStart ? TodoDates.string(from: draft.start) : nil
            projects[index].startTime = draft.hasStart && draft.hasStartTime ? TodoDates.timeString(from: draft.startTime) : nil
            projects[index].dueDate = draft.hasDue ? TodoDates.string(from: draft.due) : nil
            projects[index].updatedAt = Self.timestamp()
        }
    }

    func toggle(_ item: TodoProject) async {
        guard let index = projects.firstIndex(where: { $0.id == item.id }) else { return }
        let completed = projects[index].completedAt == nil
        do {
            let change = try PendingMutation(method: "PATCH", path: "/v1/projects/\(item.id)", body: ["completed": completed])
            try record(change) { projects[index].completedAt = completed ? Self.timestamp() : nil }
        } catch {
            message = error.localizedDescription
        }
    }

    func deleteProject(_ id: String) async throws {
        let change = try PendingMutation(method: "DELETE", path: "/v1/projects/\(id)")
        try record(change) {
            projects.removeAll { $0.id == id }
            for index in tasks.indices where tasks[index].projectId == id { tasks[index].projectId = nil }
        }
    }

    private static func timestamp() -> String { ISO8601DateFormatter().string(from: Date()) }

    private func record(_ mutation: PendingMutation, apply: () -> Void) throws {
        guard isConfigured, tenantId != nil else { throw TodoError.notConfigured }
        let oldProjects = projects
        let oldTasks = tasks
        apply()
        pendingChanges.append(mutation)
        do { try saveLocalState() }
        catch {
            projects = oldProjects
            tasks = oldTasks
            pendingChanges.removeLast()
            throw TodoError.server("Couldn't save this change on the device: \(error.localizedDescription)")
        }
        if WidgetSnapshotStore.save(widgetSnapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.widgetKind)
        }
        Task { await refresh() }
        Task { await syncBadge() }
    }

    private func flushPendingChanges() async -> Bool {
        guard !syncing else { return false }
        let currentTenant = tenantId
        let currentToken = token
        syncing = true
        defer { syncing = false }
        while let mutation = pendingChanges.first {
            do {
                _ = try await send(mutation.path, method: mutation.method, rawBody: mutation.body)
            } catch let error as HTTPFailure where mutation.method == "DELETE" && error.status == 404 {
                // A retried delete already took effect before the previous response was lost.
            } catch {
                if tenantId == currentTenant, token == currentToken {
                    message = "Saved on this device; waiting to sync. \(error.localizedDescription)"
                }
                return false
            }
            guard tenantId == currentTenant, token == currentToken,
                  pendingChanges.first?.id == mutation.id else { return false }
            pendingChanges.removeFirst()
            do { try saveLocalState() }
            catch {
                pendingChanges.insert(mutation, at: 0)
                message = "Couldn't update the local sync queue: \(error.localizedDescription)"
                return false
            }
        }
        message = nil
        return true
    }

    private func loadCachedState() {
        guard let tenantId else { return }
        if let data = try? Data(contentsOf: Self.stateURL(for: tenantId)),
           let state = try? JSONDecoder().decode(OfflineState.self, from: data),
           state.tenantId == tenantId, state.serverAddress == serverAddress {
            projects = state.snapshot.projects
            tasks = state.snapshot.tasks
            pendingChanges = state.pending
        } else if let data = try? Data(contentsOf: Self.cacheURL),
                  let snapshot = try? JSONDecoder().decode(TodoSnapshot.self, from: data) {
            projects = snapshot.projects
            tasks = snapshot.tasks
            pendingChanges = []
        }
    }

    private func saveLocalState() throws {
        guard let tenantId else { throw TodoError.notConfigured }
        let state = OfflineState(tenantId: tenantId, serverAddress: serverAddress,
                                 snapshot: TodoSnapshot(projects: projects, tasks: tasks, serverTime: Self.timestamp()),
                                 pending: pendingChanges)
        let data = try JSONEncoder().encode(state)
        let url = Self.stateURL(for: tenantId)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private static func stateURL(for tenantId: String) -> URL {
        cacheURL.deletingLastPathComponent().appendingPathComponent("state-\(tenantId).json")
    }

    func fetchMCPConnections() async throws -> [MCPConnection] {
        let response: MCPConnectionsResponse = try await request("/v1/account/mcp-connections")
        return response.connections
    }

    func disconnectMCPConnection(_ id: String) async throws {
        let _: [String: Bool] = try await request("/v1/account/mcp-connections/\(id)", method: "DELETE")
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        let rawBody = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let data = try await send(path, method: method, rawBody: rawBody)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(_ path: String, method: String, rawBody: Data?) async throws -> Data {
        guard isConfigured else { throw TodoError.notConfigured }
        let requestToken = token
        guard let base = URL(string: serverAddress), let url = URL(string: path, relativeTo: base)?.absoluteURL else { throw TodoError.invalidServer }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let rawBody {
            request.httpBody = rawBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TodoError.server("No server response") }
        if response.statusCode == 401 {
            if pendingChanges.isEmpty, token == requestToken { clearLocalSession() }
            throw HTTPFailure(status: 401, detail: "Your session expired. Sign in with Apple again.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw HTTPFailure(status: response.statusCode,
                              detail: (try? JSONDecoder().decode(APIError.self, from: data).error) ?? "Server error \(response.statusCode)")
        }
        return data
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("00todo", isDirectory: true)
            .appendingPathComponent("snapshot.json")
    }

    private static func readToken() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: tokenService,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func saveToken(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: tokenService]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var input = query
            input.merge(attributes) { _, new in new }
            status = SecItemAdd(input as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw TodoError.server("Couldn't save the session in Keychain (\(status)).") }
    }

    private static func deleteToken() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: tokenService]
        SecItemDelete(query as CFDictionary)
    }
}
