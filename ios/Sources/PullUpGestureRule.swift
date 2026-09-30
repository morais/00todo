import Foundation

enum PullUpGestureRule {
    static func shouldOpen(enabled: Bool, startedAtBottom: Bool, atBottom: Bool,
                           translation: CGSize) -> Bool {
        enabled && startedAtBottom && atBottom && translation.height < -90
            && abs(translation.height) > abs(translation.width) * 1.5
    }
}
