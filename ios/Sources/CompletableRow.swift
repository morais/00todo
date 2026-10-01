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

/// The secondary line of a row: side by side when it fits, otherwise
/// stacked, so larger text sizes never squeeze or truncate it.
struct RowDetails<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(alignment: .leading, spacing: 2) { content }
        }
    }
}
