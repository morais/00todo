import Foundation

/// The user-visible app name, read from the `TodoAppName` Info.plist key so a
/// fork can rename the app from its project configuration alone.
enum AppBrand {
    static let name: String = {
        let bundle = Bundle.main
        for key in ["TodoAppName", "CFBundleDisplayName", "CFBundleName"] {
            if let value = bundle.object(forInfoDictionaryKey: key) as? String,
               !value.trimmingCharacters(in: .whitespaces).isEmpty {
                return value
            }
        }
        return "Todo"
    }()

    /// The URL scheme for widget and quick-action links, from the
    /// `TodoURLScheme` Info.plist key. Two apps registering the same scheme
    /// would steal each other's widget taps, so a fork sets its own.
    static let urlScheme: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "TodoURLScheme") as? String
        return value.flatMap { $0.isEmpty ? nil : $0.lowercased() } ?? "zerozerotodo"
    }()
}
