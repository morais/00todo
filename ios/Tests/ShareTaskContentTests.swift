import Foundation

@main struct ShareTaskContentTests {
    static func main() {
        let url = URL(string: "https://example.com/article?id=7")!
        let link = ShareTaskContent.make(titleHint: "Useful article", texts: [], urls: [url])!
        precondition(link.title == "Useful article")
        precondition(link.notes == url.absoluteString)
        precondition(link.hasDescriptiveContext)

        let urlOnly = ShareTaskContent.make(titleHint: nil, texts: [], urls: [url])!
        precondition(urlOnly.title == "Review example.com")
        precondition(!urlOnly.hasDescriptiveContext)
        let domainOnly = ShareTaskContent.make(titleHint: "example.com", texts: [], urls: [url])!
        precondition(domainOnly.title == "Review example.com")
        precondition(!domainOnly.hasDescriptiveContext)

        let selected = ShareTaskContent.make(titleHint: nil, texts: ["Read this later"], urls: [url])!
        precondition(selected.title == "Read this later")
        precondition(selected.notes.contains("Read this later"))
        precondition(selected.notes.contains(url.absoluteString))
        precondition(selected.hasDescriptiveContext)

        precondition(ShareTaskContent.suggestedTitle("https://example.com/article?id=7") == nil)
        precondition(ShareTaskContent.suggestedTitle("HTTP://EXAMPLE.COM") == nil)
        precondition(ShareTaskContent.suggestedTitle("www.example.com/article") == nil)
        precondition(ShareTaskContent.suggestedTitle("example.com") == nil)
        precondition(ShareTaskContent.suggestedTitle("example.com.") == nil)
        precondition(ShareTaskContent.suggestedTitle("[https://example.com/article]") == nil)
        precondition(ShareTaskContent.suggestedTitle("Milk.") == "Milk.")
        precondition(ShareTaskContent.suggestedTitle("v1.0") == "v1.0")
        precondition(ShareTaskContent.suggestedTitle("Read the useful article\nsoon") == "Read the useful article soon")

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
