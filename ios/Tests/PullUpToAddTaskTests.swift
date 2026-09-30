import Foundation

@main struct PullUpToAddTaskTests {
    static func main() {
        let upward = CGSize(width: 8, height: -110)
        precondition(PullUpGestureRule.shouldOpen(enabled: true, startedAtBottom: true,
                                               atBottom: true, translation: upward))
        precondition(!PullUpGestureRule.shouldOpen(enabled: true, startedAtBottom: false,
                                                atBottom: true, translation: upward))
        precondition(!PullUpGestureRule.shouldOpen(enabled: false, startedAtBottom: true,
                                                atBottom: true, translation: upward))
        precondition(!PullUpGestureRule.shouldOpen(enabled: true, startedAtBottom: true,
                                                atBottom: true, translation: CGSize(width: 2, height: -40)))
        precondition(!PullUpGestureRule.shouldOpen(enabled: true, startedAtBottom: true,
                                                atBottom: true, translation: CGSize(width: 140, height: -110)))
        print("Pull-up-to-add tests passed")
    }
}
