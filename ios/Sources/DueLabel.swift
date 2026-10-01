import SwiftUI
import UIKit

/// A due date for task and project rows. Overdue is spelled out and marked
/// with an icon, never shown by colour alone.
struct DueLabel: View {
    let dueDate: String
    let isOpen: Bool

    var body: some View {
        if isOpen && TodoDates.isOverdue(dueDate, at: Date()) {
            Label("Overdue · due \(dueDate)", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(Color.overdue)
        } else {
            Text("Due \(dueDate)")
        }
    }
}

extension Color {
    /// System red is about 3.6:1 on white, too faint for caption text. This
    /// darker light-mode red keeps 4.5:1; dark mode keeps system red.
    static let overdue = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemRed
            : UIColor(red: 0.75, green: 0.08, blue: 0.10, alpha: 1)
    })
}
