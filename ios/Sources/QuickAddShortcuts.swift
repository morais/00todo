import Observation
import SwiftUI
import UIKit

@MainActor @Observable final class QuickAddShortcuts {
    static let shared = QuickAddShortcuts()
    var pendingLaunch: QuickAddLaunch?

    func handle(_ item: UIApplicationShortcutItem) -> Bool {
        switch item.type {
        case "com.00todo.quick-add.voice": pendingLaunch = .voice
        case "com.00todo.quick-add.text": pendingLaunch = .text
        default: return false
        }
        return true
    }
}

final class TodoAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = TodoSceneDelegate.self
        return configuration
    }
}

final class TodoSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let item = connectionOptions.shortcutItem else { return }
        Task { @MainActor in _ = QuickAddShortcuts.shared.handle(item) }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            completionHandler(QuickAddShortcuts.shared.handle(shortcutItem))
        }
    }
}
