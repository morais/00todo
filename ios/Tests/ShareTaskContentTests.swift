import Foundation

@main struct ShareTaskContentTests {
    static func main() {
        let url = URL(string: "https://example.com/article?id=7")!
        let link = ShareTaskContent.make(titleHint: "Useful article", texts: [], urls: [url])!
        precondition(link.title == "Useful article")
        precondition(link.notes == url.absoluteString)

        let selected = ShareTaskContent.make(titleHint: nil, texts: ["Read this later"], urls: [url])!
        precondition(selected.title == "Read this later")
        precondition(selected.notes.contains("Read this later"))
        precondition(selected.notes.contains(url.absoluteString))

        let long = ShareTaskContent.make(titleHint: nil, texts: [String(repeating: "x", count: 30_000)], urls: [url])!
        precondition(long.notes.count <= 20_000)
        precondition(long.notes.hasSuffix(url.absoluteString))
        let buried = ShareTaskContent.make(titleHint: nil, texts: [String(repeating: "x", count: 25_000) + url.absoluteString], urls: [url])!
        precondition(buried.notes.hasSuffix(url.absoluteString))
        precondition(ShareTaskContent.cleanTitle("One\nTwo") == "One Two")
        precondition(ShareTaskContent.make(titleHint: nil, texts: ["  "], urls: [])?.title == nil)
        print("Share task content tests passed")
    }
}
