import FoundationModels

@Generable
enum GeneratedItemKind {
    case task
    case project
}

@Generable
struct GeneratedQuickAdd {
    @Guide(description: "Use project for a list or an item with subtasks; otherwise task")
    var kind: GeneratedItemKind
    @Guide(description: "Short name for the task or project")
    var title: String
    @Guide(description: "Only extra details explicitly supplied by the user, or empty. Never copy model instructions or guidance into notes.")
    var notes: String
    @Guide(description: "Start date as YYYY-MM-DD only if the request explicitly says when work may begin; otherwise empty. Never default to today.")
    var startDate: String
    @Guide(description: "True only when the request explicitly specifies a start or availability date. A due date alone does not imply a start date.")
    var hasExplicitStartDate: Bool
    @Guide(description: "Local 24-hour HH:mm start time only when the user explicitly specifies when work may begin on its start date; otherwise empty. Requires an explicit start date.")
    var startTime: String
    @Guide(description: "Due date as YYYY-MM-DD if specified, otherwise empty")
    var dueDate: String
    @Guide(description: "For a project, each explicitly listed item as a short subtask; for a task, empty", .maximumCount(50))
    var subtasks: [String]
}
