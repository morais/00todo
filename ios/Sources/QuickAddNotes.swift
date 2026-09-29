import Foundation

enum QuickAddNotes {
    private static let instructionFragments = [
        "a shopping list is a project",
        "every named item becomes a subtask",
        "do not invent items, dates, or times",
        "the start date is absent by default",
        "never fill it with today",
        "if no due date is specified",
        "convert the user's request to one task or one project",
        "notes may contain only extra details supplied by the user"
    ]

    static func cleaned(_ notes: String) -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        guard !instructionFragments.contains(where: lowercased.contains) else { return "" }
        return trimmed
    }
}
