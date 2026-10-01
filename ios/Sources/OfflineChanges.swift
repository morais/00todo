import Foundation

struct PendingMutation: Codable, Equatable, Identifiable {
    let id: String
    let method: String
    let path: String
    let body: Data?

    init(method: String, path: String, body: [String: Any]? = nil) throws {
        id = UUID().uuidString
        self.method = method
        self.path = path
        self.body = try body.map { try JSONSerialization.data(withJSONObject: $0) }
    }
}

/// What to do with a queued change the server answered with an error.
enum SyncFailureAction: Equatable {
    /// The change already took effect (a retried delete).
    case alreadyApplied
    /// The server will never accept it; keeping it would block every later
    /// change and retry forever.
    case discard
    /// Temporary: network, server error, rate limit, or expired session.
    case retryLater
}

extension PendingMutation {
    func actionAfterFailure(status: Int) -> SyncFailureAction {
        if method == "DELETE" && status == 404 { return .alreadyApplied }
        if (400..<500).contains(status) && ![401, 408, 429].contains(status) { return .discard }
        return .retryLater
    }
}

struct OfflineState: Codable {
    let tenantId: String
    let serverAddress: String
    var snapshot: TodoSnapshot
    var pending: [PendingMutation]
    /// The server snapshot's ETag, kept only while the local snapshot is an
    /// unmodified copy of it. Absent in state written by older versions.
    var etag: String? = nil
}
