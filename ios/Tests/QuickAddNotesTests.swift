import Foundation

@main struct QuickAddNotesTests {
    static func main() {
        precondition(QuickAddNotes.cleaned(
            "A shopping list is a project; every named item becomes a subtask; do not invent items, dates, or times"
        ).isEmpty)
        precondition(QuickAddNotes.cleaned("  Buy ingredients at the market.  ") == "Buy ingredients at the market.")
        precondition(QuickAddNotes.cleaned("\n\t").isEmpty)
        print("Quick Add notes tests passed")
    }
}
