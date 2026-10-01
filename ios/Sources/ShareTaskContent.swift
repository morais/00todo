import Foundation

struct ShareTaskContent {
    let title: String
    let notes: String
    let modelPrompt: String
    let hasDescriptiveContext: Bool

    static func make(titleHint: String?, texts: [String], urls: [URL]) -> Self? {
        let textParts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let webURLs = Array(Set(urls.filter { ["https", "http"].contains($0.scheme?.lowercased() ?? "") }))
            .sorted { $0.absoluteString < $1.absoluteString }
        let urlNotes = webURLs.map(\.absoluteString).joined(separator: "\n\n")
        let textLimit = max(0, 20_000 - urlNotes.count - (urlNotes.isEmpty ? 0 : 2))
        var notes = String(textParts.joined(separator: "\n\n").prefix(textLimit))
        let missingURLs = webURLs.map(\.absoluteString).filter { !notes.contains($0) }
        if !notes.isEmpty && !missingURLs.isEmpty { notes += "\n\n" }
        notes += missingURLs.joined(separator: "\n\n")
        notes = String(notes.prefix(20_000))
        guard !notes.isEmpty else { return nil }

        let hint = cleanTitle(titleHint ?? "")
        let firstTextLine = textParts.flatMap { $0.components(separatedBy: .newlines) }
            .map(cleanTitle).first { !$0.isEmpty && !looksLikeURL($0) }
        let usefulHint = !hint.isEmpty && !looksLikeURL(hint)
        let fallback = usefulHint ? hint
            : (firstTextLine ?? webURLs.first.map { "Review \($0.host ?? "link")" } ?? "Review shared text")
        let prompt = "Source title: \(hint)\nShared text: \(String(textParts.joined(separator: " ").prefix(1_200)))\nLinks: \(webURLs.map(\.absoluteString).joined(separator: ", "))"
        return Self(title: String(fallback.prefix(240)), notes: notes, modelPrompt: prompt,
                    hasDescriptiveContext: usefulHint || firstTextLine != nil)
    }

    static func cleanTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func suggestedTitle(_ raw: String) -> String? {
        let title = cleanTitle(raw)
        guard !title.isEmpty, !looksLikeURL(title) else { return nil }
        return String(title.prefix(240))
    }

    private static func looksLikeURL(_ value: String) -> Bool {
        let wrappers = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’`<>[]().,;!"))
        let candidate = value.trimmingCharacters(in: wrappers)
        guard !candidate.isEmpty, !candidate.contains(where: \.isWhitespace) else { return false }
        let explicitScheme = candidate.lowercased().hasPrefix("https://") || candidate.lowercased().hasPrefix("http://")
        if explicitScheme { return true }
        let url = URLComponents(string: "https://\(candidate)")
        guard let host = url?.host else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let suffix = labels.last, suffix.count >= 2 else { return false }
        return suffix.allSatisfy(\.isLetter) || suffix.hasPrefix("xn--")
    }
}
