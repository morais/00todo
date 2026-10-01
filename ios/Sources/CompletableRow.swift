import SwiftUI

/// Makes a task or project row a single VoiceOver stop that reads the whole
/// row, with Complete or Reopen offered as a swipe action. VoiceOver lists
/// swipe actions in its Actions rotor, so the inline checkmark button can stay
/// out of the way instead of being a separate stop.
struct CompletableRow: ViewModifier {
    let isCompleted: Bool
    let onToggle: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityValue(isCompleted ? "Completed" : "")
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button(isCompleted ? "Reopen" : "Complete",
                       systemImage: isCompleted ? "arrow.uturn.backward" : "checkmark") { onToggle() }
                    .tint(isCompleted ? .gray : .accentColor)
            }
    }
}
