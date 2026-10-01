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

    /// Sample tasks and projects for demo mode and the screenshot fixture.
    /// They live only in memory and are never sent to the server.
    static func snapshot(at now: Date = Date()) -> TodoSnapshot {
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
}
