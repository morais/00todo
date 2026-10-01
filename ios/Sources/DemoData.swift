import Foundation

extension TodoStore {
    var hasDemoData: Bool {
        guard let tenantId else { return false }
        return !Self.demoIDs(kind: "projects", tenantId: tenantId).isEmpty
            || !Self.demoIDs(kind: "tasks", tenantId: tenantId).isEmpty
    }

    var demoItemCount: Int {
        guard let tenantId else { return 0 }
        return Self.demoIDs(kind: "projects", tenantId: tenantId).count
            + Self.demoIDs(kind: "tasks", tenantId: tenantId).count
    }

    func createDemoData() async throws {
        guard let tenantId, isConfigured else { throw TodoError.notConfigured }
        guard !hasDemoData else { throw TodoError.server("Remove the current demo data before creating another set.") }
        func day(_ offset: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        }

        var shopping = ProjectDraft()
        shopping.name = "Weekend shopping"
        shopping.notes = "Ingredients for dinner with friends."
        shopping.hasDue = true
        shopping.due = day(2)
        let list = try await createProject(shopping, subtasks: [
            "Buy fresh pasta", "Pick up cherry tomatoes", "Get parmesan"
        ])
        Self.trackDemoIDs([list.id], kind: "projects", tenantId: tenantId)
        Self.trackDemoIDs(list.taskIDs, kind: "tasks", tenantId: tenantId)

        var weekend = ProjectDraft()
        weekend.name = "Plan autumn weekend"
        weekend.notes = "Choose a destination and make a simple itinerary."
        weekend.hasStart = true
        weekend.start = day(7)
        weekend.hasDue = true
        weekend.due = day(14)
        let futureProject = try await createProject(weekend)
        Self.trackDemoIDs([futureProject.id], kind: "projects", tenantId: tenantId)

        var review = TaskDraft()
        review.title = "Send design review notes"
        review.notes = "Summarize the main feedback in a short message."
        review.hasDue = true
        review.due = day(0)
        Self.trackDemoIDs([try await createTask(review)], kind: "tasks", tenantId: tenantId)

        var appointment = TaskDraft()
        appointment.title = "Book annual check-up"
        appointment.hasStart = true
        appointment.start = day(1)
        appointment.hasDue = true
        appointment.due = day(7)
        Self.trackDemoIDs([try await createTask(appointment)], kind: "tasks", tenantId: tenantId)

        var packing = TaskDraft()
        packing.title = "Prepare travel packing list"
        packing.hasStart = true
        packing.start = day(10)
        Self.trackDemoIDs([try await createTask(packing)], kind: "tasks", tenantId: tenantId)

        var coffee = TaskDraft()
        coffee.title = "Confirm coffee catch-up"
        let coffeeID = try await createTask(coffee)
        Self.trackDemoIDs([coffeeID], kind: "tasks", tenantId: tenantId)
        if let task = tasks.first(where: { $0.id == coffeeID }) { await toggle(task) }
    }

    func removeDemoData() async throws {
        guard let tenantId, isConfigured else { throw TodoError.notConfigured }
        for id in Self.demoIDs(kind: "tasks", tenantId: tenantId) {
            if tasks.contains(where: { $0.id == id }) { try await deleteTask(id) }
        }
        for id in Self.demoIDs(kind: "projects", tenantId: tenantId) {
            if projects.contains(where: { $0.id == id }) { try await deleteProject(id) }
        }
        Self.clearDemoData(for: tenantId)
    }

    func clearDemoData(for tenantId: String) {
        Self.clearDemoData(for: tenantId)
    }

    private static func demoIDs(kind: String, tenantId: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: "demo.\(kind).\(tenantId)") ?? []
    }

    private static func trackDemoIDs(_ ids: [String], kind: String, tenantId: String) {
        let key = "demo.\(kind).\(tenantId)"
        UserDefaults.standard.set(Array(Set(demoIDs(kind: kind, tenantId: tenantId) + ids)), forKey: key)
    }

    private static func clearDemoData(for tenantId: String) {
        UserDefaults.standard.removeObject(forKey: "demo.projects.\(tenantId)")
        UserDefaults.standard.removeObject(forKey: "demo.tasks.\(tenantId)")
    }
}
