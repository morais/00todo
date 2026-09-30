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

struct OfflineState: Codable {
    let tenantId: String
    let serverAddress: String
    var snapshot: TodoSnapshot
    var pending: [PendingMutation]
}
