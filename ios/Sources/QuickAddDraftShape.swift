import Foundation

struct QuickAddDraftShape: Equatable {
    let isProject: Bool
    let title: String
    let subtasks: [String]

    static func resolve(request: String, modelSuggestedProject: Bool, title: String,
                        subtasks: [String]) -> Self {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        let distinctSubtasks = subtasks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(normalized($0)).inserted }
            .filter { normalized($0) != normalized(title) }

        let explicitContainer = request.range(
            of: #"(?i)\b(?:(?:create|make|start|add|new)\s+(?:a\s+|an\s+|the\s+)?(?:shopping\s+)?(?:project|list|checklist)|(?:project|shopping\s+list|checklist)\s*:)"#,
            options: .regularExpression
        ) != nil
        let isProject = distinctSubtasks.count >= 2 || explicitContainer
        if isProject {
            return Self(isProject: true, title: title, subtasks: distinctSubtasks)
        }
        let taskTitle = modelSuggestedProject && distinctSubtasks.count == 1
            ? distinctSubtasks[0] : title
        return Self(isProject: false, title: taskTitle, subtasks: [])
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }
}
