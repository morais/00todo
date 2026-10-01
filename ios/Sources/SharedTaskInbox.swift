import Foundation

struct SharedTask: Codable, Identifiable, Equatable {
    let id: String
    let tenantId: String
    let serverAddress: String
    let title: String
    let notes: String
    let createdAt: String
}

/// One atomic file per share avoids read/modify/write races between the app and
/// extension. A stable UUID makes an uncertain network retry safe.
enum SharedTaskInbox {
    private static var directory: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "TodoAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return container.appendingPathComponent("shared-tasks", isDirectory: true)
    }

    static func save(_ task: SharedTask) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(task).write(to: directory.appendingPathComponent("\(task.id).json"),
                                             options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func pending(tenantId: String, serverAddress: String) -> [SharedTask] {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(SharedTask.self, from: Data(contentsOf: $0)) }
            .filter { $0.tenantId == tenantId && $0.serverAddress == serverAddress }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func remove(_ id: String) {
        guard let directory, UUID(uuidString: id) != nil else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).json"))
    }
}
