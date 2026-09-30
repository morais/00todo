import Foundation
import SwiftUI

enum NotesLinks {
    static func urls(in notes: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let matches = detector.matches(in: notes, range: NSRange(notes.startIndex..., in: notes))
        var seen = Set<URL>()
        return matches.compactMap(\.url).filter { url in
            guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return false }
            return seen.insert(url).inserted
        }
    }
}

struct NotesLinkButtons: View {
    let notes: String

    var body: some View {
        ForEach(NotesLinks.urls(in: notes), id: \.absoluteString) { url in
            Link(destination: url) {
                Label(url.absoluteString, systemImage: "link")
                    .lineLimit(1)
            }
            .accessibilityLabel("Open link: \(url.absoluteString)")
        }
    }
}
