import Foundation

@main struct NotesLinksTests {
    static func main() {
        let notes = "App Store Connect: https://appstoreconnect.apple.com/appclips/ui/app-experience-review/abc\nSee it again: https://appstoreconnect.apple.com/appclips/ui/app-experience-review/abc"
        let links = NotesLinks.urls(in: notes)
        precondition(links.count == 1)
        precondition(links[0].host == "appstoreconnect.apple.com")
        precondition(NotesLinks.urls(in: "No links here").isEmpty)
        print("Notes link tests passed")
    }
}
