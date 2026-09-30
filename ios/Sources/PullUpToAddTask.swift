import SwiftUI

/// Recognizes a deliberate upward pull that begins at the end of a task list.
/// The gesture runs alongside List scrolling, so an ordinary swipe that merely
/// reaches the bottom does not create a task.
struct PullUpToAddTask: ViewModifier {
    let enabled: Bool
    let addTask: () -> Void

    @State private var isAtBottom = false
    @State private var startedAtBottom: Bool?

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 12
            } action: { _, atBottom in
                isAtBottom = atBottom
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { _ in
                        if startedAtBottom == nil { startedAtBottom = isAtBottom }
                    }
                    .onEnded { value in
                        defer { startedAtBottom = nil }
                        guard PullUpGestureRule.shouldOpen(enabled: enabled, startedAtBottom: startedAtBottom == true,
                                                           atBottom: isAtBottom, translation: value.translation) else { return }
                        addTask()
                    },
                isEnabled: enabled
            )
            .onDisappear { startedAtBottom = nil }
    }
}
