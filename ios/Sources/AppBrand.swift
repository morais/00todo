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
}
