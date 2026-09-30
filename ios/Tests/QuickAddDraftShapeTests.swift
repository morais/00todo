import Foundation

@main struct QuickAddDraftShapeTests {
    static func main() {
        let duplicate = QuickAddDraftShape.resolve(
            request: "Pay the electricity bill", modelSuggestedProject: true,
            title: "Pay the electricity bill", subtasks: ["Pay the Electricity Bill"]
        )
        precondition(duplicate == .init(isProject: false, title: "Pay the electricity bill", subtasks: []))

        let singleAction = QuickAddDraftShape.resolve(
            request: "Buy milk", modelSuggestedProject: true,
            title: "Shopping", subtasks: ["Buy milk"]
        )
        precondition(singleAction == .init(isProject: false, title: "Buy milk", subtasks: []))

        let specificChild = QuickAddDraftShape.resolve(
            request: "Book flights", modelSuggestedProject: true,
            title: "Plan trip", subtasks: ["Book flights"]
        )
        precondition(specificChild == .init(isProject: false, title: "Book flights", subtasks: []))

        let shoppingList = QuickAddDraftShape.resolve(
            request: "Shopping list: milk, eggs, bread", modelSuggestedProject: true,
            title: "Shopping list", subtasks: ["milk", "eggs", "bread", "Milk"]
        )
        precondition(shoppingList == .init(isProject: true, title: "Shopping list", subtasks: ["milk", "eggs", "bread"]))

        let explicitProject = QuickAddDraftShape.resolve(
            request: "Create a project for the bathroom", modelSuggestedProject: true,
            title: "Bathroom", subtasks: ["Bathroom"]
        )
        precondition(explicitProject == .init(isProject: true, title: "Bathroom", subtasks: []))

        let explicitList = QuickAddDraftShape.resolve(
            request: "Make a shopping list with milk", modelSuggestedProject: false,
            title: "Shopping list", subtasks: ["milk"]
        )
        precondition(explicitList == .init(isProject: true, title: "Shopping list", subtasks: ["milk"]))

        let inferredProject = QuickAddDraftShape.resolve(
            request: "Buy milk, eggs and bread", modelSuggestedProject: false,
            title: "Groceries", subtasks: ["milk", "eggs", "bread"]
        )
        precondition(inferredProject.isProject)
        precondition(inferredProject.subtasks == ["milk", "eggs", "bread"])

        print("Quick Add draft-shape tests passed")
    }
}
