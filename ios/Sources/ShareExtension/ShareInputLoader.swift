import Foundation
import UniformTypeIdentifiers

enum ShareInputLoader {
    static func load(_ inputItems: [Any]) async -> ShareTaskContent? {
        var titleHint: String?
        var texts: [String] = []
        var urls: [URL] = []
        for case let item as NSExtensionItem in inputItems {
            if titleHint == nil { titleHint = item.attributedTitle?.string }
            if let attributed = item.attributedContentText {
                texts.append(attributed.string)
                attributed.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                    if let url = value as? URL { urls.append(url) }
                    else if let value = value as? String, let url = URL(string: value) { urls.append(url) }
                }
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await loadURL(from: provider) {
                    urls.append(url)
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = await loadText(from: provider) {
                    texts.append(text)
                }
            }
        }
        return ShareTaskContent.make(titleHint: titleHint, texts: texts, urls: urls)
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
                if let url = value as? URL { continuation.resume(returning: url) }
                else if let value = value as? String { continuation.resume(returning: URL(string: value)) }
                else { continuation.resume(returning: nil) }
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { value, _ in
                if let text = value as? String { continuation.resume(returning: text) }
                else if let data = value as? Data { continuation.resume(returning: String(data: data, encoding: .utf8)) }
                else { continuation.resume(returning: nil) }
            }
        }
    }
}
