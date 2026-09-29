import Foundation
import Observation
import Security

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
private struct TaskResponse: Decodable { var task: TodoTask }
private struct ProjectResponse: Decodable { var project: TodoProject }
private struct ProjectWithTasksResponse: Decodable { var project: TodoProject; var tasks: [TodoTask] }
private struct MCPConnectionsResponse: Decodable { var connections: [MCPConnection] }
private struct AppleLoginResponse: Decodable {
    var token: String
    var expiresAt: String
    var tenant: Account
    struct Account: Decodable { var id: String; var email: String? }
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

    private static let tokenService = "00todo.api-token"

    init() {
        serverAddress = UserDefaults.standard.string(forKey: "serverAddress")
            ?? (Bundle.main.object(forInfoDictionaryKey: "TodoServerBaseURL") as? String ?? "")
        token = Self.readToken()
        accountEmail = UserDefaults.standard.string(forKey: "accountEmail")
        tenantId = UserDefaults.standard.string(forKey: "tenantId")
        if !token.isEmpty, tenantId != nil,
           let cached = try? Data(contentsOf: Self.cacheURL),
           let snapshot = try? JSONDecoder().decode(TodoSnapshot.self, from: cached) {
            projects = snapshot.projects
            tasks = snapshot.tasks
        }
    }

    var isConfigured: Bool { !serverAddress.isEmpty && !token.isEmpty }

    func configureServer(address: String) throws {
        let cleaned = address.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: cleaned), let host = url.host,
              (url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host))),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw TodoError.invalidServer
        }
        if cleaned != serverAddress { clearLocalSession() }
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
            try? FileManager.default.removeItem(at: Self.cacheURL)
        }
        token = login.token
        accountEmail = login.tenant.email
        tenantId = login.tenant.id
        UserDefaults.standard.set(login.tenant.email, forKey: "accountEmail")
        UserDefaults.standard.set(login.tenant.id, forKey: "tenantId")
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
        clearLocalSession()
    }

    private func clearLocalSession() {
        token = ""
        accountEmail = nil
        tenantId = nil
        projects = []
        tasks = []
        message = nil
        Self.deleteToken()
        UserDefaults.standard.removeObject(forKey: "accountEmail")
        UserDefaults.standard.removeObject(forKey: "tenantId")
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    func refresh() async {
        guard isConfigured else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let snapshot: TodoSnapshot = try await request("/v1/snapshot")
            projects = snapshot.projects
            tasks = snapshot.tasks
            if let data = try? JSONEncoder().encode(snapshot) {
                try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: Self.cacheURL, options: .atomic)
            }
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func createTask(_ draft: TaskDraft) async throws {
        let response: TaskResponse = try await request("/v1/tasks", method: "POST", body: draft.payload)
        tasks.append(response.task)
        await refresh()
    }

    func updateTask(_ id: String, draft: TaskDraft) async throws {
        let response: TaskResponse = try await request("/v1/tasks/\(id)", method: "PATCH", body: draft.payload)
        if let index = tasks.firstIndex(where: { $0.id == id }) { tasks[index] = response.task }
        await refresh()
    }

    func toggle(_ item: TodoTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        let previous = tasks[index]
        tasks[index].completedAt = previous.completedAt == nil ? ISO8601DateFormatter().string(from: Date()) : nil
        do {
            let response: TaskResponse = try await request("/v1/tasks/\(item.id)", method: "PATCH", body: ["completed": previous.completedAt == nil])
            if let current = tasks.firstIndex(where: { $0.id == item.id }) { tasks[current] = response.task }
            await refresh()
        } catch {
            if let current = tasks.firstIndex(where: { $0.id == item.id }) { tasks[current] = previous }
            message = error.localizedDescription
        }
    }

    func deleteTask(_ id: String) async throws {
        let _: [String: Bool] = try await request("/v1/tasks/\(id)", method: "DELETE")
        tasks.removeAll { $0.id == id }
        await refresh()
    }

    func createProject(_ draft: ProjectDraft) async throws {
        let response: ProjectResponse = try await request("/v1/projects", method: "POST", body: draft.payload)
        projects.append(response.project)
        await refresh()
    }

    func createProject(_ draft: ProjectDraft, subtasks: [String]) async throws {
        let response: ProjectWithTasksResponse = try await request(
            "/v1/projects-with-tasks", method: "POST", body: [
                "project": draft.payload,
                "tasks": subtasks.enumerated().map { index, title in
                    ["title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                     "notes": "", "startDate": NSNull(), "startTime": NSNull(), "dueDate": NSNull(), "sortOrder": index] as [String: Any]
                }
            ]
        )
        projects.append(response.project)
        tasks.append(contentsOf: response.tasks)
        await refresh()
    }

    func updateProject(_ id: String, draft: ProjectDraft) async throws {
        let response: ProjectResponse = try await request("/v1/projects/\(id)", method: "PATCH", body: draft.payload)
        if let index = projects.firstIndex(where: { $0.id == id }) { projects[index] = response.project }
        await refresh()
    }

    func toggle(_ item: TodoProject) async {
        guard let index = projects.firstIndex(where: { $0.id == item.id }) else { return }
        let previous = projects[index]
        projects[index].completedAt = previous.completedAt == nil ? ISO8601DateFormatter().string(from: Date()) : nil
        do {
            let response: ProjectResponse = try await request("/v1/projects/\(item.id)", method: "PATCH", body: ["completed": previous.completedAt == nil])
            if let current = projects.firstIndex(where: { $0.id == item.id }) { projects[current] = response.project }
            await refresh()
        } catch {
            if let current = projects.firstIndex(where: { $0.id == item.id }) { projects[current] = previous }
            message = error.localizedDescription
        }
    }

    func deleteProject(_ id: String) async throws {
        let _: [String: Bool] = try await request("/v1/projects/\(id)", method: "DELETE")
        await refresh()
    }

    func fetchMCPConnections() async throws -> [MCPConnection] {
        let response: MCPConnectionsResponse = try await request("/v1/account/mcp-connections")
        return response.connections
    }

    func disconnectMCPConnection(_ id: String) async throws {
        let _: [String: Bool] = try await request("/v1/account/mcp-connections/\(id)", method: "DELETE")
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard isConfigured else { throw TodoError.notConfigured }
        guard let base = URL(string: serverAddress), let url = URL(string: path, relativeTo: base)?.absoluteURL else { throw TodoError.invalidServer }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TodoError.server("No server response") }
        if response.statusCode == 401 {
            clearLocalSession()
            throw TodoError.server("Your session expired. Sign in with Apple again.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw TodoError.server((try? JSONDecoder().decode(APIError.self, from: data).error) ?? "Server error \(response.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
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
