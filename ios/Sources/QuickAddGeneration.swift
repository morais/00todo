import FoundationModels

@Generable
enum GeneratedItemKind {
    case task
    case project
}

@Generable
struct GeneratedQuickAdd {
    @Guide(description: "Default to task for one action. Use project only for an explicitly requested project or list, or for two or more distinct related subtasks.")
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
    @Guide(description: "True only if the user explicitly wants this task or project on a Someday/maybe list, to consider later without scheduling it. A future start date alone is not Someday.")
    var someday: Bool
    @Guide(description: "True only if the user explicitly says the task or project is blocked or waiting on something. Do not infer Blocked from a future start date. Blocked and Someday cannot both be true.")
    var blocked: Bool
    @Guide(description: "For a project, distinct subtasks explicitly named by the user; never repeat the project title. For a task, empty.", .maximumCount(50))
    var subtasks: [String]
}
