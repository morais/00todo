import Foundation
import UserNotifications

@MainActor enum AvailableBadge {
    private static let notificationPrefix = "00todo.available-badge."
    private static var generation = 0
    private static var lastCount: Int?

    static func updateCurrent(snapshot: WidgetSnapshot, expandProjects: Bool, at now: Date = Date()) async {
        let count = snapshot.availableItems(at: now, expandProjects: expandProjects).count
        guard count != lastCount else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.badgeSetting == .enabled else { return }
        do {
            try await center.setBadgeCount(count)
            lastCount = count
        } catch {
            lastCount = nil
        }
    }

    static func sync(snapshot: WidgetSnapshot, expandProjects: Bool) async {
        generation += 1
        let currentGeneration = generation
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard !snapshot.projects.isEmpty || !snapshot.tasks.isEmpty else { return }
            do {
                _ = try await center.requestAuthorization(options: [.badge])
                settings = await center.notificationSettings()
            } catch { return }
        }
        guard currentGeneration == generation, settings.badgeSetting == .enabled else { return }

        let now = Date()
        let count = snapshot.availableItems(at: now, expandProjects: expandProjects).count
        do {
            try await center.setBadgeCount(count)
            lastCount = count
        } catch {
            lastCount = nil
        }

        // Keep starts due while the app is closed reflected in the icon too.
        let oldRequests = await center.pendingNotificationRequests()
        guard currentGeneration == generation else { return }
        center.removePendingNotificationRequests(withIdentifiers:
            oldRequests.map(\.identifier).filter { $0.hasPrefix(notificationPrefix) })

        var previousCount = count
        for (index, start) in snapshot.upcomingStartDates(after: now).enumerated() {
            guard currentGeneration == generation else { return }
            let nextCount = snapshot.availableItems(at: start, expandProjects: expandProjects).count
            defer { previousCount = nextCount }
            guard nextCount != previousCount else { continue }
            let content = UNMutableNotificationContent()
            content.badge = NSNumber(value: nextCount)
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: start)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "\(notificationPrefix)\(index)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    static func clear() async {
        generation += 1
        lastCount = nil
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers:
            requests.map(\.identifier).filter { $0.hasPrefix(notificationPrefix) })
        try? await center.setBadgeCount(0)
    }
}
