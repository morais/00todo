import Foundation
import SwiftUI

struct NotesAction: Identifiable {
    enum Kind: String {
        case web, email, phone
    }

    let kind: Kind
    let title: String
    let destination: URL

    var id: String { "\(kind.rawValue):\(destination.absoluteString)" }

    var systemImage: String {
        switch kind {
        case .web: "link"
        case .email: "envelope"
        case .phone: "phone"
        }
    }

    var accessibilityLabel: String {
        switch kind {
        case .web: "Open link: \(title)"
        case .email: "Email: \(title)"
        case .phone: "Call: \(title)"
        }
    }
}

enum NotesLinks {
    static func actions(in notes: String) -> [NotesAction] {
        let types = NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        guard let detector = try? NSDataDetector(types: types) else { return [] }
        let matches = detector.matches(in: notes, range: NSRange(notes.startIndex..., in: notes))
        var seen = Set<String>()
        return matches.compactMap { match -> NotesAction? in
            guard let range = Range(match.range, in: notes) else { return nil }
            let text = String(notes[range])
            let action: NotesAction
            switch match.resultType {
            case .link:
                guard let url = match.url else { return nil }
                switch url.scheme?.lowercased() {
                case "http", "https":
                    action = NotesAction(kind: .web, title: url.absoluteString, destination: url)
                case "mailto":
                    guard text.contains("@") else { return nil }
                    action = NotesAction(kind: .email, title: text, destination: url)
                default:
                    return nil
                }
            case .phoneNumber:
                guard let phone = match.phoneNumber else { return nil }
                let digits = String(phone.filter { "0123456789".contains($0) })
                guard (7...15).contains(digits.count) else { return nil }
                let hasCountryPrefix = phone.trimmingCharacters(in: .whitespaces).hasPrefix("+")
                // Long bare digit strings are often references or build IDs;
                // require an explicit + for numbers longer than 11 digits.
                guard hasCountryPrefix || digits.count <= 11 else { return nil }
                let normalized = (hasCountryPrefix ? "+" : "") + digits
                guard let url = URL(string: "tel:\(normalized)") else { return nil }
                action = NotesAction(kind: .phone, title: text, destination: url)
            default:
                return nil
            }
            return seen.insert(action.id).inserted ? action : nil
        }
    }

    static func urls(in notes: String) -> [URL] {
        actions(in: notes).filter { $0.kind == .web }.map(\.destination)
    }
}

struct NotesLinkButtons: View {
    let notes: String

    var body: some View {
        ForEach(NotesLinks.actions(in: notes)) { action in
            Link(destination: action.destination) {
                Label(action.title, systemImage: action.systemImage)
                    .lineLimit(1)
            }
            .accessibilityLabel(action.accessibilityLabel)
        }
    }
}
