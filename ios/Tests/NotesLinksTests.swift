import Foundation

@main struct NotesLinksTests {
    static func main() {
        let notes = "App Store Connect: https://appstoreconnect.apple.com/appclips/ui/app-experience-review/abc\nSee it again: https://appstoreconnect.apple.com/appclips/ui/app-experience-review/abc"
        let links = NotesLinks.urls(in: notes)
        precondition(links.count == 1)
        precondition(links[0].host == "appstoreconnect.apple.com")
        precondition(NotesLinks.urls(in: "No links here").isEmpty)

        let contactNotes = "Email pedro@example.com or call +351 936 257 607. "
            + "Email pedro@example.com again; call +351 936 257 607 again. "
            + "Visit https://example.com. Build 202610031216."
        let actions = NotesLinks.actions(in: contactNotes)
        precondition(actions.map(\.kind) == [.email, .phone, .web])
        precondition(actions[0].destination.absoluteString == "mailto:pedro@example.com")
        precondition(actions[0].accessibilityLabel == "Email: pedro@example.com")
        precondition(actions[1].destination.absoluteString == "tel:+351936257607")
        precondition(actions[1].accessibilityLabel == "Call: +351 936 257 607")
        precondition(actions[2].destination.absoluteString == "https://example.com")
        precondition(NotesLinks.actions(in: "Call 936257607").first?.destination.absoluteString == "tel:936257607")
        precondition(NotesLinks.actions(in: "Phone (415) 555-2671").first?.destination.absoluteString == "tel:4155552671")
        precondition(NotesLinks.actions(in: "Build 202610031216; code 123456").isEmpty)
        precondition(NotesLinks.actions(in: "Due 2026-10-05; order 123456789").isEmpty)
        print("Notes contact action tests passed")
    }
}
