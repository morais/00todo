import Foundation

@main struct OfflineChangesTests {
    static func main() throws {
        let mutation = try PendingMutation(method: "POST", path: "/v1/tasks", body: [
            "id": "18f3887c-3ed8-4b40-82bb-0bb22f881af9", "title": "Buy milk"
        ])
        let task = TodoTask(id: "18f3887c-3ed8-4b40-82bb-0bb22f881af9", title: "Buy milk", notes: "",
                            projectId: nil, startDate: nil, startTime: nil, dueDate: nil, completedAt: nil,
                            sortOrder: 0, createdAt: "2026-09-30T11:00:00Z", updatedAt: "2026-09-30T11:00:00Z")
        let state = OfflineState(tenantId: "tenant", serverAddress: "https://api.00todo.com",
                                 snapshot: TodoSnapshot(projects: [], tasks: [task], serverTime: "2026-09-30T11:00:00Z"),
                                 pending: [mutation])
        let restored = try JSONDecoder().decode(OfflineState.self, from: JSONEncoder().encode(state))
        precondition(restored.snapshot.tasks == [task])
        precondition(restored.pending == [mutation])
        let body = try JSONSerialization.jsonObject(with: restored.pending[0].body!) as! [String: String]
        precondition(body["title"] == "Buy milk")
        precondition(restored.etag == nil)

        // State written before the ETag field existed still decodes.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        legacy.removeValue(forKey: "etag")
        let legacyState = try JSONDecoder().decode(OfflineState.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(legacyState.etag == nil && legacyState.pending == [mutation])

        let edit = try PendingMutation(method: "PATCH", path: "/v1/tasks/x", body: ["title": "Milk"])
        let delete = try PendingMutation(method: "DELETE", path: "/v1/tasks/x")
        precondition(delete.actionAfterFailure(status: 404) == .alreadyApplied)
        precondition(edit.actionAfterFailure(status: 404) == .discard)
        precondition(edit.actionAfterFailure(status: 400) == .discard)
        precondition(edit.actionAfterFailure(status: 409) == .discard)
        for status in [401, 408, 429, 500, 503] {
            precondition(edit.actionAfterFailure(status: status) == .retryLater)
        }
        print("Offline change encoding tests passed")
    }
}
