import Foundation

enum DemoDataCatalog {
    static let shoppingName = "Weekend shopping"
    static let shoppingNotes = "Ingredients for dinner with friends."
    static let shoppingTasks = ["Buy fresh pasta", "Pick up cherry tomatoes", "Get parmesan"]
    static let weekendName = "Plan autumn weekend"
    static let weekendNotes = "Choose a destination and make a simple itinerary."
    static let reviewTitle = "Send design review notes"
    static let reviewNotes = "Summarize the main feedback in a short message."
    static let appointmentTitle = "Book annual check-up"
    static let landlordTitle = "Email the landlord"
    static let flowersTitle = "Order birthday flowers"
    static let packingTitle = "Prepare travel packing list"
    static let coffeeTitle = "Confirm coffee catch-up"

    #if TODO_SCREENSHOTS
    static func screenshotSnapshot(at now: Date = Date()) -> TodoSnapshot {
        func day(_ offset: Int) -> String {
            TodoDates.string(from: Calendar.current.date(byAdding: .day, value: offset, to: now) ?? now)
        }
        let created = "2026-10-01T09:41:00Z"
        func project(_ id: String, _ name: String, _ notes: String, _ start: String?, _ due: String?) -> TodoProject {
            TodoProject(id: id, name: name, notes: notes, startDate: start, startTime: nil,
                        dueDate: due, completedAt: nil, sortOrder: 0, createdAt: created, updatedAt: created)
        }
        func task(_ id: String, _ title: String, _ notes: String = "", projectId: String? = nil,
                  start: String? = nil, due: String? = nil, completed: Bool = false,
                  order: Int = 0) -> TodoTask {
            TodoTask(id: id, title: title, notes: notes, projectId: projectId,
                     startDate: start, startTime: nil, dueDate: due,
                     completedAt: completed ? created : nil, sortOrder: order,
                     createdAt: created, updatedAt: created)
        }
        let shoppingID = "00000000-0000-4000-8000-000000000001"
        return TodoSnapshot(projects: [
            project(shoppingID, shoppingName, shoppingNotes, nil, day(2)),
            project("00000000-0000-4000-8000-000000000002", weekendName, weekendNotes, day(7), day(14))
        ], tasks: [
            task("00000000-0000-4000-8000-000000000011", shoppingTasks[0], projectId: shoppingID, order: 1),
            task("00000000-0000-4000-8000-000000000012", shoppingTasks[1], projectId: shoppingID, order: 2),
            task("00000000-0000-4000-8000-000000000013", shoppingTasks[2], projectId: shoppingID, order: 3),
            task("00000000-0000-4000-8000-000000000014", reviewTitle, reviewNotes, due: day(0)),
            task("00000000-0000-4000-8000-000000000015", landlordTitle, due: day(1)),
            task("00000000-0000-4000-8000-000000000016", appointmentTitle, start: day(1), due: day(7)),
            task("00000000-0000-4000-8000-000000000017", flowersTitle, start: day(2)),
            task("00000000-0000-4000-8000-000000000018", packingTitle, start: day(10)),
            task("00000000-0000-4000-8000-000000000019", coffeeTitle, completed: true)
        ], serverTime: created)
    }
    #endif
}

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
        shopping.name = DemoDataCatalog.shoppingName
        shopping.notes = DemoDataCatalog.shoppingNotes
        shopping.hasDue = true
        shopping.due = day(2)
        let list = try await createProject(shopping, subtasks: DemoDataCatalog.shoppingTasks)
        Self.trackDemoIDs([list.id], kind: "projects", tenantId: tenantId)
        Self.trackDemoIDs(list.taskIDs, kind: "tasks", tenantId: tenantId)

        var weekend = ProjectDraft()
        weekend.name = DemoDataCatalog.weekendName
        weekend.notes = DemoDataCatalog.weekendNotes
        weekend.hasStart = true
        weekend.start = day(7)
        weekend.hasDue = true
        weekend.due = day(14)
        let futureProject = try await createProject(weekend)
        Self.trackDemoIDs([futureProject.id], kind: "projects", tenantId: tenantId)

        var review = TaskDraft()
        review.title = DemoDataCatalog.reviewTitle
        review.notes = DemoDataCatalog.reviewNotes
        review.hasDue = true
        review.due = day(0)
        Self.trackDemoIDs([try await createTask(review)], kind: "tasks", tenantId: tenantId)

        var landlord = TaskDraft()
        landlord.title = DemoDataCatalog.landlordTitle
        landlord.hasDue = true
        landlord.due = day(1)
        Self.trackDemoIDs([try await createTask(landlord)], kind: "tasks", tenantId: tenantId)

        var appointment = TaskDraft()
        appointment.title = DemoDataCatalog.appointmentTitle
        appointment.hasStart = true
        appointment.start = day(1)
        appointment.hasDue = true
        appointment.due = day(7)
        Self.trackDemoIDs([try await createTask(appointment)], kind: "tasks", tenantId: tenantId)

        var flowers = TaskDraft()
        flowers.title = DemoDataCatalog.flowersTitle
        flowers.hasStart = true
        flowers.start = day(2)
        Self.trackDemoIDs([try await createTask(flowers)], kind: "tasks", tenantId: tenantId)

        var packing = TaskDraft()
        packing.title = DemoDataCatalog.packingTitle
        packing.hasStart = true
        packing.start = day(10)
        Self.trackDemoIDs([try await createTask(packing)], kind: "tasks", tenantId: tenantId)

        var coffee = TaskDraft()
        coffee.title = DemoDataCatalog.coffeeTitle
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
